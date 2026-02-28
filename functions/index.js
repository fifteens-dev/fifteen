const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

const getsongbpmApiKey = defineSecret('GETSONGBPM_API_KEY');

admin.initializeApp();

/**
 * プッシュ通知送信Cloud Function
 *
 * トリガー: Firestore `push_notification_requests` コレクションへの書き込み
 *
 * 処理:
 * 1. user_fcm_tokensコレクションから受信者のトークンを取得
 * 2. admin.messaging().sendEachForMulticast() でプッシュ通知送信
 * 3. 無効なトークンを削除
 * 4. リクエストドキュメントを processed: true に更新
 */
exports.sendPushNotification = onDocumentCreated(
  'push_notification_requests/{requestId}',
  async (event) => {
    const snap = event.data;
    const request = snap.data();
    const {
      recipientId,
      notificationType,
      senderUsername,
      message,
      postId,
    } = request;

    try {
      // 受信者のFCMトークンを取得
      const tokenDoc = await admin.firestore()
        .collection('user_fcm_tokens')
        .doc(recipientId)
        .get();

      if (!tokenDoc.exists || !tokenDoc.data().tokens) {
        console.log(`No FCM tokens found for user: ${recipientId}`);
        await snap.ref.update({ processed: true, error: 'No FCM tokens' });
        return;
      }

      const tokens = tokenDoc.data().tokens.map(t => t.token);

      if (tokens.length === 0) {
        console.log(`Empty FCM tokens array for user: ${recipientId}`);
        await snap.ref.update({ processed: true, error: 'Empty tokens array' });
        return;
      }

      // プッシュ通知のペイロード
      const payload = {
        notification: {
          title: `${senderUsername}`,
          body: message,
        },
        data: {
          notificationType: notificationType,
          postId: postId || '',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        tokens: tokens,
      };

      // プッシュ通知を送信
      const response = await admin.messaging().sendEachForMulticast(payload);

      console.log(`Successfully sent ${response.successCount} notifications`);
      console.log(`Failed to send ${response.failureCount} notifications`);

      // 無効なトークンを削除
      if (response.failureCount > 0) {
        const invalidTokens = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.error(`Error sending to token ${tokens[idx]}:`, resp.error);
            // 無効なトークンや登録解除されたトークンを記録
            if (
              resp.error?.code === 'messaging/invalid-registration-token' ||
              resp.error?.code === 'messaging/registration-token-not-registered'
            ) {
              invalidTokens.push(tokens[idx]);
            }
          }
        });

        // 無効なトークンを削除
        if (invalidTokens.length > 0) {
          const updatedTokens = tokenDoc.data().tokens.filter(
            t => !invalidTokens.includes(t.token)
          );
          await tokenDoc.ref.update({ tokens: updatedTokens });
          console.log(`Removed ${invalidTokens.length} invalid tokens`);
        }
      }

      // リクエストを処理済みとしてマーク
      await snap.ref.update({
        processed: true,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        successCount: response.successCount,
        failureCount: response.failureCount,
      });

    } catch (error) {
      console.error('Error sending push notification:', error);
      await snap.ref.update({
        processed: true,
        error: error.message,
      });
    }
  }
);

/**
 * 公式通知送信Cloud Function（管理者→全ユーザー）
 *
 * HTTPSエンドポイント（呼び出し可能関数）
 *
 * 認証: 管理者のみ（admin_usersコレクションでチェック）
 *
 * パラメータ:
 * - title: 通知タイトル
 * - body: 通知本文
 * - imageUrl: 通知画像URL（オプション）
 * - actionUrl: タップ時の遷移先URL（オプション）
 *
 * 処理:
 * 1. 管理者権限チェック
 * 2. 全ユーザーにFirestore通知を作成（バッチ処理）
 * 3. FCMトピック "all_users" にプッシュ通知を送信
 */
exports.sendOfficialNotification = onCall(async (request) => {
  // 認証チェック
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'ログインが必要です');
  }

  // 管理者チェック
  const adminDoc = await admin.firestore()
    .collection('admin_users')
    .doc(request.auth.uid)
    .get();

  if (!adminDoc.exists || !adminDoc.data().isAdmin) {
    throw new HttpsError('permission-denied', '管理者権限がありません');
  }

  const { title, body, imageUrl, actionUrl } = request.data;

  if (!title || !body) {
    throw new HttpsError('invalid-argument', 'titleとbodyは必須です');
  }

  try {
    // 全ユーザーを取得
    const usersSnapshot = await admin.firestore().collection('users').get();

    console.log(`Creating notifications for ${usersSnapshot.docs.length} users`);

    // バッチで通知を作成（500件ずつ）
    const batchSize = 500;
    const batches = [];
    let currentBatch = admin.firestore().batch();
    let operationCount = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;

      const notificationRef = admin.firestore().collection('notifications').doc();
      currentBatch.set(notificationRef, {
        type: 'official',
        recipientId: userId,
        senderId: 'system',
        senderUsername: '運営チーム',
        title: title,
        body: body,
        imageUrl: imageUrl || null,
        actionUrl: actionUrl || null,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        readAt: null,
      });

      operationCount++;

      if (operationCount >= batchSize) {
        batches.push(currentBatch.commit());
        currentBatch = admin.firestore().batch();
        operationCount = 0;
      }
    }

    // 残りのバッチをコミット
    if (operationCount > 0) {
      batches.push(currentBatch.commit());
    }

    await Promise.all(batches);
    console.log(`Created notifications for ${usersSnapshot.docs.length} users`);

    // FCMプッシュ通知を送信（トピック購読方式）
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        type: 'official',
        actionUrl: actionUrl || '',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      topic: 'all_users',
    };

    // 画像URLがある場合は追加
    if (imageUrl) {
      message.notification.imageUrl = imageUrl;
    }

    const fcmResponse = await admin.messaging().send(message);
    console.log('FCM topic message sent:', fcmResponse);

    return {
      success: true,
      notificationCount: usersSnapshot.docs.length,
      message: `${usersSnapshot.docs.length}人のユーザーに公式通知を送信しました`,
    };

  } catch (error) {
    console.error('Error sending official notification:', error);
    throw new HttpsError('internal', `公式通知の送信に失敗しました: ${error.message}`);
  }
});

/**
 * BPM取得Cloud Function
 *
 * GetSongBPM APIをサーバー側から呼び出してBPMを取得する
 * Cloudflare保護をバイパスするためCloud Function経由で実行
 *
 * パラメータ:
 * - trackName: 楽曲名（必須）
 * - artistName: アーティスト名（オプション）
 *
 * レスポンス:
 * - tempo: BPM値（数値 or null）
 */
exports.getBpm = onCall({ secrets: [getsongbpmApiKey] }, async (request) => {
  const { trackName, artistName } = request.data;

  if (!trackName) {
    throw new HttpsError('invalid-argument', 'trackName is required');
  }

  const apiKey = getsongbpmApiKey.value();
  if (!apiKey) {
    throw new HttpsError('failed-precondition', 'GETSONGBPM_API_KEY is not configured');
  }

  try {
    // 1. 楽曲を検索
    const lookup = encodeURIComponent(trackName);
    const searchUrl = `https://api.getsong.co/search/?api_key=${apiKey}&type=song&lookup=${lookup}`;

    const searchRes = await fetch(searchUrl, {
      headers: { 'Accept': 'application/json' },
    });

    if (!searchRes.ok) {
      console.error(`GetSongBPM search error: ${searchRes.status}`);
      return { tempo: null };
    }

    const searchData = await searchRes.json();
    const results = searchData.search;
    if (!Array.isArray(results) || results.length === 0) {
      console.log(`No results for: ${trackName}`);
      return { tempo: null };
    }

    // アーティスト名でマッチング
    let songId = null;
    if (artistName) {
      const artistLower = artistName.toLowerCase();
      for (const r of results) {
        const name = (r.artist?.name || '').toLowerCase();
        if (name.includes(artistLower) || artistLower.includes(name)) {
          songId = r.id;
          break;
        }
      }
    }
    if (!songId) {
      songId = results[0].id;
    }

    // 2. BPMを取得
    const songUrl = `https://api.getsong.co/song/?api_key=${apiKey}&id=${songId}`;
    const songRes = await fetch(songUrl, {
      headers: { 'Accept': 'application/json' },
    });

    if (!songRes.ok) {
      console.error(`GetSongBPM song error: ${songRes.status}`);
      return { tempo: null };
    }

    const songData = await songRes.json();
    const tempo = songData.song?.tempo;
    if (!tempo) {
      return { tempo: null };
    }

    const bpm = parseFloat(tempo);
    console.log(`BPM for "${trackName}": ${bpm}`);
    return { tempo: isNaN(bpm) ? null : bpm };

  } catch (error) {
    console.error('getBpm error:', error);
    return { tempo: null };
  }
});

// ========== 投稿通知システム ==========

/**
 * 投稿通知を送信するヘルパー
 * Firestore通知書き込み + FCM直接送信（リアルタイム）
 */
async function sendPostNotification(recipientId, senderId, senderUsername, senderIconUrl, message, postId) {
  const db = admin.firestore();

  // notifications コレクションに通知を作成（アプリ内通知）
  await db.collection('notifications').add({
    type: 'post',
    recipientId: recipientId,
    senderId: senderId,
    senderUsername: senderUsername,
    senderIconUrl: senderIconUrl || null,
    postId: postId || null,
    body: message,
    isRead: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    readAt: null,
  });

  // FCMプッシュ通知を直接送信（push_notification_requests キューを経由しない）
  const tokenDoc = await db.collection('user_fcm_tokens').doc(recipientId).get();
  if (!tokenDoc.exists || !tokenDoc.data().tokens) return;

  const tokens = tokenDoc.data().tokens.map(t => t.token).filter(Boolean);
  if (tokens.length === 0) return;

  const payload = {
    notification: {
      title: senderUsername,
      body: message,
    },
    data: {
      notificationType: 'post',
      postId: postId || '',
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
    tokens: tokens,
  };

  const response = await admin.messaging().sendEachForMulticast(payload);

  // 無効なトークンを削除
  if (response.failureCount > 0) {
    const invalidTokens = [];
    response.responses.forEach((resp, idx) => {
      if (!resp.success && (
        resp.error?.code === 'messaging/invalid-registration-token' ||
        resp.error?.code === 'messaging/registration-token-not-registered'
      )) {
        invalidTokens.push(tokens[idx]);
      }
    });
    if (invalidTokens.length > 0) {
      const updatedTokens = tokenDoc.data().tokens.filter(t => !invalidTokens.includes(t.token));
      await tokenDoc.ref.update({ tokens: updatedTokens });
      console.log(`Removed ${invalidTokens.length} invalid tokens for ${recipientId}`);
    }
  }
}

/**
 * 投稿作成時のCloud Function
 *
 * トリガー: Firestore `posts` コレクションへの書き込み
 *
 * 処理:
 * 1. 投稿者のフォロワーリストを取得
 * 2. 全フォロワーへ即時通知（スロットリングなし・リアルタイム）
 */
exports.onPostCreated = onDocumentCreated(
  { document: 'posts/{postId}', timeoutSeconds: 300 },
  async (event) => {
    const postDocId = event.data.id;
    const post = event.data.data();
    const posterId = post.userId;
    const posterUsername = post.username || 'Unknown';
    const posterIconUrl = post.userIconUrl || null;
    const message = `${posterUsername}が投稿しました。`;

    if (!posterId) {
      console.log('onPostCreated: userId not found in post');
      return;
    }

    try {
      // 投稿者のフォロワーリストを取得
      const posterDoc = await admin.firestore()
        .collection('users')
        .doc(posterId)
        .get();

      if (!posterDoc.exists) {
        console.log(`onPostCreated: user ${posterId} not found`);
        return;
      }

      const followers = posterDoc.data().followers || [];

      if (followers.length === 0) {
        console.log(`onPostCreated: user ${posterId} has no followers`);
        return;
      }

      console.log(`onPostCreated: notifying ${followers.length} followers for ${posterUsername}`);

      // 10件ずつ並列処理で全フォロワーに即時通知
      const batchSize = 10;
      for (let i = 0; i < followers.length; i += batchSize) {
        const batch = followers.slice(i, i + batchSize);
        await Promise.all(
          batch.map((followerId) =>
            sendPostNotification(followerId, posterId, posterUsername, posterIconUrl, message, postDocId)
              .catch((err) => {
                console.error(`Error notifying ${followerId}:`, err);
              })
          )
        );
      }

      console.log(`onPostCreated: completed for ${posterUsername}`);
    } catch (error) {
      console.error('onPostCreated error:', error);
    }
  }
);

// ========== Vibeお題ローテーション & 通知 ==========

/**
 * 事前定義されたVibeお題リスト（Flutter側と同じ）
 */
const PREDEFINED_VIBE_TOPICS = [
  'ドライブで聴きたい曲',
  '雨の日に聴きたい曲',
  '朝に聴きたい曲',
  '夜に聴きたい曲',
  '作業中に聴きたい曲',
  '運動中に聴きたい曲',
  'リラックスしたい時の曲',
  'テンションを上げたい曲',
  '懐かしい曲',
  '最近ハマっている曲',
  '通勤・通学で聴きたい曲',
  '勉強中に聴きたい曲',
  '寝る前に聴きたい曲',
  '元気が出る曲',
  '切ない曲',
  '夏に聴きたい曲',
  '冬に聴きたい曲',
  '春に聴きたい曲',
  '秋に聴きたい曲',
  'デートで聴きたい曲',
];

/**
 * 毎日0:00(JST)にVibeお題を自動ローテーション
 *
 * 処理:
 * 1. 昨日までのactiveなお題をarchivedに変更
 * 2. 今日の日付のお題が既にあればactiveに変更
 * 3. なければ事前定義リストからランダムに選んで新規作成
 */
exports.dailyVibeTopicRotation = onSchedule(
  { schedule: '0 0 * * *', timeZone: 'Asia/Tokyo' },
  async () => {
    const db = admin.firestore();

    try {
      // JST基準で今日の日付を計算
      const now = new Date();
      const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
      const todayStart = new Date(jst.getFullYear(), jst.getMonth(), jst.getDate());
      const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
      const todayTimestamp = admin.firestore.Timestamp.fromDate(todayStart);
      const todayEndTimestamp = admin.firestore.Timestamp.fromDate(todayEnd);

      // 1. 昨日までのactiveなお題をarchivedに
      // ※ status + date の複合インデックスを避けるため、statusのみでクエリしてコード側で日付フィルタ
      const activeTopics = await db
        .collection('vibe_topics')
        .where('status', '==', 'active')
        .get();

      let archivedCount = 0;
      for (const doc of activeTopics.docs) {
        const topicDate = doc.data().date.toDate();
        if (topicDate < todayStart) {
          await doc.ref.update({
            status: 'archived',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          archivedCount++;
        }
      }
      console.log(`Archived ${archivedCount} old active topics`);

      // 2. 今日の日付のお題があるかチェック
      const todaysTopics = await db
        .collection('vibe_topics')
        .where('date', '>=', todayTimestamp)
        .where('date', '<', todayEndTimestamp)
        .get();

      if (todaysTopics.size > 0) {
        // 既に今日のお題がある → activeに変更
        for (const doc of todaysTopics.docs) {
          await doc.ref.update({
            status: 'active',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        console.log(`Activated ${todaysTopics.size} existing topics for today`);
      } else {
        // 3. 今日のお題がない → 事前定義リストからランダムに作成

        // 直近使われたお題を取得（重複回避）
        const recentTopics = await db
          .collection('vibe_topics')
          .orderBy('date', 'desc')
          .limit(5)
          .get();

        const recentTitles = recentTopics.docs.map(d => d.data().title);

        // 直近5つと被らないお題を選ぶ
        const availableTopics = PREDEFINED_VIBE_TOPICS.filter(
          t => !recentTitles.includes(t)
        );

        // 候補がなければ全リストから選ぶ
        const pool = availableTopics.length > 0 ? availableTopics : PREDEFINED_VIBE_TOPICS;
        const selectedTitle = pool[Math.floor(Math.random() * pool.length)];

        await db.collection('vibe_topics').add({
          title: selectedTitle,
          date: todayTimestamp,
          status: 'active',
          voteCount: 0,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`Created new vibe topic: "${selectedTitle}"`);
      }

      console.log('dailyVibeTopicRotation: completed');
    } catch (error) {
      console.error('dailyVibeTopicRotation error:', error);
    }
  }
);

/**
 * 毎日20:00(JST)にVibe通知を全ユーザーに送信
 *
 * 処理:
 * 1. 今日のactiveなお題を取得
 * 2. 全ユーザーに通知を作成（バッチ処理）
 * 3. FCMトピック「all_users」にプッシュ通知を送信
 *
 * 通知文面:
 * - タイトル:「今日のVibe、もう決めた？」
 * - 本文: お題を疑問形に変換（例:「夜に聴きたい曲は？」）
 */
exports.dailyVibeNotification = onSchedule(
  { schedule: '0 20 * * *', timeZone: 'Asia/Tokyo' },
  async () => {
    const db = admin.firestore();

    try {
      // 今日のactiveなお題を取得（JST基準）
      const now = new Date();
      const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
      const todayStart = new Date(jst.getFullYear(), jst.getMonth(), jst.getDate());
      const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);

      const todaysTopics = await db
        .collection('vibe_topics')
        .where('status', '==', 'active')
        .where('date', '>=', admin.firestore.Timestamp.fromDate(todayStart))
        .where('date', '<', admin.firestore.Timestamp.fromDate(todayEnd))
        .get();

      if (todaysTopics.empty) {
        console.log('dailyVibeNotification: no active topic for today, skipping');
        return;
      }

      const topicData = todaysTopics.docs[0].data();
      const topicTitle = topicData.title; // 例: "夜に聴きたい曲"

      const notificationTitle = '今日のVibe、もう決めた？';
      const notificationBody = `${topicTitle}は？`; // 例: "夜に聴きたい曲は？"

      // 全ユーザーに通知を作成（バッチ処理、500件ずつ）
      const usersSnapshot = await db.collection('users').get();

      const batchSize = 500;
      let currentBatch = db.batch();
      let operationCount = 0;
      const batches = [];

      for (const userDoc of usersSnapshot.docs) {
        const notificationRef = db.collection('notifications').doc();
        currentBatch.set(notificationRef, {
          type: 'vibe',
          recipientId: userDoc.id,
          senderId: 'system',
          senderUsername: '15s',
          title: notificationTitle,
          body: notificationBody,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          readAt: null,
        });

        operationCount++;

        if (operationCount >= batchSize) {
          batches.push(currentBatch.commit());
          currentBatch = db.batch();
          operationCount = 0;
        }
      }

      if (operationCount > 0) {
        batches.push(currentBatch.commit());
      }

      await Promise.all(batches);
      console.log(`Created vibe notifications for ${usersSnapshot.size} users`);

      // FCMプッシュ通知を送信（トピック購読方式）
      const fcmMessage = {
        notification: {
          title: notificationTitle,
          body: notificationBody,
        },
        data: {
          notificationType: 'vibe',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        topic: 'all_users',
      };

      const fcmResponse = await admin.messaging().send(fcmMessage);
      console.log('Vibe FCM topic message sent:', fcmResponse);

      console.log('dailyVibeNotification: completed');
    } catch (error) {
      console.error('dailyVibeNotification error:', error);
    }
  }
);
