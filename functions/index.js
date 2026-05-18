const { onDocumentCreated, onDocumentDeleted, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

admin.initializeApp();

/** 投稿通知のタイトルをランダムに選ぶ */
function randomPostTitle() {
  return Math.random() < 0.5 ? 'もう見た？' : '気になる？';
}

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

      const senderId = request.senderId || '';

      // 通知タイプ別タイトル・本文
      let notifTitle;
      let notifBody = message;
      if (notificationType === 'post') {
        notifTitle = randomPostTitle();
      } else if (notificationType === 'follow') {
        notifTitle = 'フォロー通知';
        notifBody = `${senderUsername}があなたをフォローしました`;
      } else {
        notifTitle = senderUsername;
      }

      // プッシュ通知のペイロード
      const payload = {
        notification: {
          title: notifTitle,
          body: notifBody,
        },
        data: {
          notificationType: notificationType,
          senderId: senderId,
          postId: postId || '',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
        apns: {
          payload: { aps: { sound: 'default' } },
        },
        android: {
          notification: { sound: 'default' },
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

  // 管理者チェック（users/{uid}.isAdmin で確認）
  const adminDoc = await admin.firestore()
    .collection('users')
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
    // notifOfficialEnabled が false のユーザーはスキップ
    const batchSize = 500;
    const batches = [];
    let currentBatch = admin.firestore().batch();
    let operationCount = 0;
    const enabledUserIds = [];

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      // フィールドが未設定の場合はデフォルトで通知あり（true）
      if (userData.notifOfficialEnabled === false) continue;

      const userId = userDoc.id;
      enabledUserIds.push(userId);

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
    console.log(`Created notifications for ${enabledUserIds.length} / ${usersSnapshot.docs.length} users`);

    // FCMプッシュ通知を通知有効ユーザーにのみ個別送信
    if (enabledUserIds.length > 0) {
      const tokenDocs = await Promise.all(
        enabledUserIds.map(uid => admin.firestore().collection('user_fcm_tokens').doc(uid).get())
      );
      const allTokens = [];
      for (const tokenDoc of tokenDocs) {
        if (tokenDoc.exists && tokenDoc.data().tokens) {
          allTokens.push(...tokenDoc.data().tokens.map(t => t.token));
        }
      }
      const tokenChunkSize = 500;
      for (let i = 0; i < allTokens.length; i += tokenChunkSize) {
        const chunk = allTokens.slice(i, i + tokenChunkSize);
        const fcmMsg = {
          tokens: chunk,
          notification: { title, body },
          data: { notificationType: 'official', actionUrl: actionUrl || '', click_action: 'FLUTTER_NOTIFICATION_CLICK' },
        };
        if (imageUrl) fcmMsg.notification.imageUrl = imageUrl;
        await admin.messaging().sendEachForMulticast(fcmMsg);
      }
      console.log(`Official FCM sent to ${allTokens.length} tokens`);
    }

    return {
      success: true,
      notificationCount: enabledUserIds.length,
      message: `${enabledUserIds.length}人のユーザーに公式通知を送信しました`,
    };

  } catch (error) {
    console.error('Error sending official notification:', error);
    throw new HttpsError('internal', `公式通知の送信に失敗しました: ${error.message}`);
  }
});

// ========== 投稿通知状態管理 ==========
//
// post_notification_states/{recipientId} の構造:
// {
//   phase: 'TIMER_ACTIVE' | 'TIMER_EXPIRED_EMPTY' | 'DONE',
//   notificationsSentToday: number,       // 今日送った通知数（最大2）
//   batchedSenderIds: string[],           // TIMER_ACTIVE中に溜めた投稿者UID
//   batchedSenderUsernames: string[],     // 同上（表示名）
//   timerStartedAt: Timestamp,            // タイマー開始時刻
//   lastResetDate: string,                // JST 'YYYY-MM-DD'（日付リセット判定用）
// }

/** JST基準の今日の日付文字列 (YYYY-MM-DD) を返す */
function getJstDateString() {
  const now = new Date();
  const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  return `${jst.getFullYear()}-${String(jst.getMonth() + 1).padStart(2, '0')}-${String(jst.getDate()).padStart(2, '0')}`;
}

/**
 * 通知ドキュメントを作成してFCMプッシュを送信するヘルパー
 * notifDocId を固定化することで冪等性を保証
 */
async function sendPostNotificationDoc(db, recipientId, senderId, senderUsername, senderIconUrl, message, notifDocId, postId, albumArtUrl, postIds) {
  // 重複チェック
  const notifRef = db.collection('notifications').doc(notifDocId);
  const existing = await notifRef.get();
  if (existing.exists) {
    console.log(`sendPostNotificationDoc: already exists ${notifDocId}, skipping`);
    return;
  }

  await notifRef.set({
    type: 'post',
    recipientId: recipientId,
    senderId: senderId,
    senderUsername: senderUsername,
    senderIconUrl: senderIconUrl || null,
    postId: postId || null,
    albumArtUrl: albumArtUrl || null,
    postIds: postIds && postIds.length > 0 ? postIds : null,
    body: message,
    isRead: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    readAt: null,
  });

  // FCMプッシュ送信
  const tokenDoc = await db.collection('user_fcm_tokens').doc(recipientId).get();
  if (!tokenDoc.exists || !tokenDoc.data().tokens) return;

  const tokens = tokenDoc.data().tokens.map(t => t.token).filter(Boolean);
  if (tokens.length === 0) return;

  const payload = {
    notification: { title: randomPostTitle(), body: message },
    data: {
      notificationType: 'post',
      senderId: senderId || '',
      postId: postId || '',
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
    apns: {
      payload: { aps: { sound: 'default' } },
    },
    android: {
      notification: { sound: 'default' },
    },
    tokens: tokens,
  };

  const response = await admin.messaging().sendEachForMulticast(payload);

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
 * 1フォロワーへの通知処理
 *
 * ① 即時通知: 投稿ごとに毎回送信（タイマー状態に関わらず常に実行）
 * ② バッチ追跡: TIMER_ACTIVE で投稿を蓄積し、3時間後にまとめ通知（checkPostNotificationTimers で送信）
 *    → ①と②は独立して動作する
 */
async function processPostNotificationForRecipient(db, recipientId, senderId, senderUsername, senderIconUrl, postId, albumArtUrl) {
  // ① 即時通知（常に送信）
  const notifDocId = `post_${postId}_${recipientId}`;
  const notifMessage = `${senderUsername}が投稿しました。`;
  await sendPostNotificationDoc(
    db, recipientId, senderId, senderUsername, senderIconUrl,
    notifMessage, notifDocId, postId, albumArtUrl
  );

  // ② バッチトラッキング（3時間後まとめ通知用・即時通知とは独立）
  try {
    const today = getJstDateString();
    const stateRef = db.collection('post_notification_states').doc(recipientId);
    await db.runTransaction(async (tx) => {
      const stateDoc = await tx.get(stateRef);
      const state = stateDoc.exists ? stateDoc.data() : null;
      const isNewCycle = !state || state.lastResetDate !== today ||
                         state.phase === 'DONE' || state.phase === 'TIMER_EXPIRED_EMPTY';

      if (isNewCycle) {
        // 新しいタイマーサイクルを開始
        // ※ 最初の投稿者は即時通知で名前が出るため、バッチには含めない
        //   → 3時間後バッチには2人目以降のみ蓄積し、誰も投稿しなければ通知なし
        tx.set(stateRef, {
          phase: 'TIMER_ACTIVE',
          batchedSenderIds: [],
          batchedSenderUsernames: [],
          batchedPostIds: [],
          timerStartedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastResetDate: today,
        });
      } else if (state.phase === 'TIMER_ACTIVE') {
        // タイマー中 → 各投稿を独立エントリとして追加
        tx.update(stateRef, {
          batchedSenderIds: [...(state.batchedSenderIds || []), senderId],
          batchedSenderUsernames: [...(state.batchedSenderUsernames || []), senderUsername],
          batchedPostIds: [...(state.batchedPostIds || []), postId],
        });
      }
    });
  } catch (e) {
    console.error(`Batch tracking error for ${recipientId}:`, e);
  }
}

/**
 * 投稿作成時のCloud Function
 *
 * トリガー: Firestore `posts` コレクションへの書き込み
 *
 * 処理:
 * 1. 投稿者のフォロワーリストを取得
 * 2. 各フォロワーの通知状態に応じて状態遷移を実行
 */
exports.onPostCreated = onDocumentCreated(
  { document: 'posts/{postId}', timeoutSeconds: 300, retry: false },
  async (event) => {
    const postDocId = event.data.id;
    const post = event.data.data();
    const posterId = post.userId;
    const posterUsername = post.username || 'Unknown';
    const posterIconUrl = post.userIconUrl || null;
    const posterAlbumArtUrl = post.track?.albumImageUrl || null;

    if (!posterId) {
      console.log('onPostCreated: userId not found in post');
      return;
    }

    try {
      const db = admin.firestore();

      const posterDoc = await db.collection('users').doc(posterId).get();
      if (!posterDoc.exists) {
        console.log(`onPostCreated: user ${posterId} not found`);
        return;
      }

      const followers = posterDoc.data().followers || [];
      if (followers.length === 0) {
        console.log(`onPostCreated: user ${posterId} has no followers`);
        return;
      }

      console.log(`onPostCreated: processing ${followers.length} followers for ${posterUsername}`);

      // notifPostEnabled チェック（未設定はデフォルトで通知あり）
      // 大量フォロワー対策: 最大1000人まで処理
      const followersToProcess = followers.length > 1000 ? followers.slice(0, 1000) : followers;
      const chunkSize = 20;
      const enabledFollowers = [];
      for (let i = 0; i < followersToProcess.length; i += chunkSize) {
        const chunk = followersToProcess.slice(i, i + chunkSize);
        const docs = await Promise.all(chunk.map(id => db.collection('users').doc(id).get()));
        for (const doc of docs) {
          if (doc.exists && doc.data().notifPostEnabled !== false) {
            enabledFollowers.push(doc.id);
          }
        }
      }

      console.log(`onPostCreated: ${enabledFollowers.length} / ${followers.length} followers enabled`);

      // 各フォロワーの状態遷移を処理
      for (let i = 0; i < enabledFollowers.length; i += chunkSize) {
        const chunk = enabledFollowers.slice(i, i + chunkSize);
        await Promise.all(
          chunk.map((followerId) =>
            processPostNotificationForRecipient(
              db, followerId, posterId, posterUsername, posterIconUrl, postDocId, posterAlbumArtUrl
            ).catch((err) => {
              console.error(`Error processing notification for ${followerId}:`, err);
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

/**
 * 15分ごとに TIMER_ACTIVE 状態をチェックし、3時間経過したものを処理
 *
 * - batchedSenderIds > 0 → 「〇人が投稿しました」まとめ通知 → DONE
 *   ※ バッチには最初の投稿者(即時通知済み)は含まれず、2人目以降のみ
 * - batchedSenderIds == 0 → 通知なし → DONE（最初の1人しか投稿しなかった場合）
 */
exports.checkPostNotificationTimers = onSchedule(
  { schedule: '*/15 * * * *', timeZone: 'Asia/Tokyo' },
  async () => {
    const db = admin.firestore();
    const threeHoursAgo = new Date(Date.now() - 3 * 60 * 60 * 1000);
    const today = getJstDateString();

    try {
      const activeStates = await db
        .collection('post_notification_states')
        .where('phase', '==', 'TIMER_ACTIVE')
        .get();

      // コード側で3時間経過フィルタ（複合インデックス不要）
      const expiredDocs = activeStates.docs.filter(doc => {
        const ts = doc.data().timerStartedAt;
        return ts && ts.toDate() <= threeHoursAgo;
      });

      console.log(`checkPostNotificationTimers: ${expiredDocs.length} expired timers`);

      for (const doc of expiredDocs) {
        const recipientId = doc.id;

        // ── アトミックにタイマーをクレーム ──────────────────────────
        // 2インスタンスが同時に同じ TIMER_ACTIVE ドキュメントを処理しないよう
        // トランザクションで phase を DONE に更新し、データを取り出す。
        // 他のインスタンスが先に DONE にしていたら claimed === null でスキップ。
        let claimedData = null;
        try {
          claimedData = await db.runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            if (!fresh.exists || fresh.data().phase !== 'TIMER_ACTIVE') {
              return null; // 既に別インスタンスが処理済み
            }
            const freshTs = fresh.data().timerStartedAt?.toDate();
            if (!freshTs || freshTs > threeHoursAgo) {
              return null; // リセットされた or まだ期限前
            }
            const data = fresh.data();
            tx.update(doc.ref, {
              phase: 'DONE',
              batchedSenderIds: [],
              batchedSenderUsernames: [],
              batchedPostIds: [],
            });
            return data; // クレーム成功: 元データを返す
          });
        } catch (txErr) {
          console.error(`checkPostNotificationTimers: transaction error for ${recipientId}:`, txErr);
          continue;
        }

        if (!claimedData) {
          console.log(`checkPostNotificationTimers: ${recipientId} already claimed, skipping`);
          continue;
        }

        const batchedSenderIds      = claimedData.batchedSenderIds || [];
        const batchedSenderUsernames = claimedData.batchedSenderUsernames || [];
        const batchedPostIds        = claimedData.batchedPostIds || [];

        if (batchedSenderIds.length === 0) {
          console.log(`checkPostNotificationTimers: ${recipientId} -> DONE (empty batch)`);
          continue;
        }

        const uniqueSenderIds = [...new Set(batchedSenderIds)];
        const count = uniqueSenderIds.length;
        const firstUsername = batchedSenderUsernames[0] || 'Unknown';
        const firstPostId = batchedPostIds[0] || null;
        const message = count === 1
          ? `${firstUsername}が投稿しました。`
          : `${firstUsername}など${count}人が投稿しました。`;

        // timerStartedAt ベースの決定的 ID（Date.now() を使うと2インスタンスで別IDになる）
        const timerMs = claimedData.timerStartedAt?.toDate().getTime() || Date.now();
        const notifDocId = `batch_${recipientId}_${timerMs}`;
        await sendPostNotificationDoc(
          db, recipientId,
          batchedSenderIds[0], firstUsername, null,
          message, notifDocId, firstPostId, null, batchedPostIds
        );

        console.log(`checkPostNotificationTimers: batch sent to ${recipientId} (${count} unique senders, ${batchedSenderIds.length} posts)`);
      }

      console.log('checkPostNotificationTimers: completed');
    } catch (error) {
      console.error('checkPostNotificationTimers error:', error);
    }
  }
);

// ========== Vibeお題ローテーション & 通知 ==========

/**
 * 事前定義されたVibeお題リスト
 * カテゴリごとに絵文字を固定し、同カテゴリが連続しないようローテーション
 */
const PREDEFINED_VIBE_TOPICS = [
  // 🌙夜・エモ系
  { title: '夜中に1人で聴きたい曲', emoji: '🌙', category: '夜・エモ系' },
  { title: '帰り道に聴きたい曲', emoji: '🌙', category: '夜・エモ系' },
  { title: '寝る前に浸りたい曲', emoji: '🌙', category: '夜・エモ系' },
  { title: '夜のドライブで流したい曲', emoji: '🌙', category: '夜・エモ系' },
  { title: '夜景見ながら聴きたい曲', emoji: '🌙', category: '夜・エモ系' },
  { title: 'ちょっと寂しい夜に聴きたい曲', emoji: '🌙', category: '夜・エモ系' },
  { title: '泣きたい時に聴きたい曲', emoji: '🌙', category: '夜・エモ系' },
  { title: '失恋した日に聴きたい曲', emoji: '🌙', category: '夜・エモ系' },
  { title: '誰にも会いたくない日に聞きたい曲', emoji: '🌙', category: '夜・エモ系' },
  { title: '夜散歩しながら聴きたい曲', emoji: '🌙', category: '夜・エモ系' },
  // 🚗日常シーン系
  { title: '朝起きてすぐ聴きたい曲', emoji: '🚗', category: '日常シーン系' },
  { title: '学校行く前に聴きたい曲', emoji: '🚗', category: '日常シーン系' },
  { title: '電車で聴きたい曲', emoji: '🚗', category: '日常シーン系' },
  { title: '友達といる時に流したい曲', emoji: '🚗', category: '日常シーン系' },
  { title: 'カフェで流したい曲', emoji: '🚗', category: '日常シーン系' },
  { title: '1人で外出する時に聴きたい曲', emoji: '🚗', category: '日常シーン系' },
  { title: '帰り道ちょっとテンション上げたい時の曲', emoji: '🚗', category: '日常シーン系' },
  { title: '何も予定ない日に聞きたい曲', emoji: '🚗', category: '日常シーン系' },
  { title: '休日の昼に聴きたい曲', emoji: '🚗', category: '日常シーン系' },
  { title: 'だらだらしている時に聴きたい曲', emoji: '🚗', category: '日常シーン系' },
  // ❤️恋愛系
  { title: '好きな人を思い浮かべる曲', emoji: '❤️', category: '恋愛系' },
  { title: '付き合いたてで聴きたい曲', emoji: '❤️', category: '恋愛系' },
  { title: 'デート前に聴きたい曲', emoji: '❤️', category: '恋愛系' },
  { title: '別れた後に聴きたい曲', emoji: '❤️', category: '恋愛系' },
  { title: '会いたいときに聴きたい曲', emoji: '❤️', category: '恋愛系' },
  { title: '片想いしてるときの曲', emoji: '❤️', category: '恋愛系' },
  { title: '友達以上恋人未満のときに聴きたい曲', emoji: '❤️', category: '恋愛系' },
  { title: '思い出の人を思い出す曲', emoji: '❤️', category: '恋愛系' },
  { title: 'なんか恋したくなる曲', emoji: '❤️', category: '恋愛系' },
  { title: '幸せな気分のときの曲', emoji: '❤️', category: '恋愛系' },
  // 🔥テンション・感情系
  { title: '気分上げたいときの曲', emoji: '🔥', category: 'テンション・感情系' },
  { title: '落ち込んでるときに聴きたい曲', emoji: '🔥', category: 'テンション・感情系' },
  { title: '自信つけたいときの曲', emoji: '🔥', category: 'テンション・感情系' },
  { title: 'なんか無敵な気分のときの曲', emoji: '🔥', category: 'テンション・感情系' },
  { title: 'ストレス発散したいときの曲', emoji: '🔥', category: 'テンション・感情系' },
  { title: 'イライラしてるときに聴きたい曲', emoji: '🔥', category: 'テンション・感情系' },
  { title: '頑張ろうと思える曲', emoji: '🔥', category: 'テンション・感情系' },
  { title: '何もかもどうでもいいときの曲', emoji: '🔥', category: 'テンション・感情系' },
  { title: 'テンションぶち上げたいときの曲', emoji: '🔥', category: 'テンション・感情系' },
  { title: 'ちょっとチルしたいときの曲', emoji: '🔥', category: 'テンション・感情系' },
  // 🌆シーン・映像浮かぶ系
  { title: '海を見ながら聴きたい曲', emoji: '🌆', category: 'シーン・映像浮かぶ系' },
  { title: '雨の日に聴きたい曲', emoji: '🌆', category: 'シーン・映像浮かぶ系' },
  { title: '夕焼け見ながら聴きたい曲', emoji: '🌆', category: 'シーン・映像浮かぶ系' },
  { title: '夜の街を歩きながら聴きたい曲', emoji: '🌆', category: 'シーン・映像浮かぶ系' },
  { title: '高速乗ってるときに聴きたい曲', emoji: '🌆', category: 'シーン・映像浮かぶ系' },
  { title: '夏の終わりに聴きたい曲', emoji: '🌆', category: 'シーン・映像浮かぶ系' },
  { title: '冬の朝に聴きたい曲', emoji: '🌆', category: 'シーン・映像浮かぶ系' },
  { title: '春っぽい気分のときの曲', emoji: '🌆', category: 'シーン・映像浮かぶ系' },
  { title: '夜更かししてるときに聴きたい曲', emoji: '🌆', category: 'シーン・映像浮かぶ系' },
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

      // ── 冪等チェック ────────────────────────────────────────────────
      const dateKey = `${jst.getUTCFullYear()}-${String(jst.getUTCMonth() + 1).padStart(2,'0')}-${String(jst.getUTCDate()).padStart(2,'0')}`;
      const jobRef = db.doc(`daily_job_locks/vibeTopicRotation_${dateKey}`);
      try {
        await jobRef.create({ createdAt: admin.firestore.FieldValue.serverTimestamp() });
      } catch (err) {
        if (err.code === 6) {
          console.log(`dailyVibeTopicRotation: already ran for ${dateKey}, skipping duplicate`);
          return;
        }
        throw err;
      }
      // ── 冪等チェックここまで ─────────────────────────────────────
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

        // 直近使われたお題を取得（重複・連続カテゴリ回避）
        const recentTopics = await db
          .collection('vibe_topics')
          .orderBy('date', 'desc')
          .limit(10)
          .get();

        const recentTitles = recentTopics.docs.slice(0, 5).map(d => d.data().title);
        const lastCategory = recentTopics.docs.length > 0 ? recentTopics.docs[0].data().category : null;

        // 直近5つと被らず、かつ直前と異なるカテゴリのお題を選ぶ
        let availableTopics = PREDEFINED_VIBE_TOPICS.filter(
          t => !recentTitles.includes(t.title) && t.category !== lastCategory
        );

        // 候補がなければカテゴリ制約を外す
        if (availableTopics.length === 0) {
          availableTopics = PREDEFINED_VIBE_TOPICS.filter(t => !recentTitles.includes(t.title));
        }

        // それでも候補がなければ全リストから選ぶ
        const pool = availableTopics.length > 0 ? availableTopics : PREDEFINED_VIBE_TOPICS;
        const selected = pool[Math.floor(Math.random() * pool.length)];

        await db.collection('vibe_topics').add({
          title: selected.title,
          emoji: selected.emoji,
          category: selected.category,
          date: todayTimestamp,
          status: 'active',
          voteCount: 0,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`Created new vibe topic: "${selected.title}" [${selected.category}]`);
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
  { schedule: '0 20 * * *', timeZone: 'Asia/Tokyo', timeoutSeconds: 300 },
  async () => {
    const db = admin.firestore();

    try {
      // 今日のactiveなお題を取得（JST基準）
      const now = new Date();
      const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
      const todayStart = new Date(jst.getFullYear(), jst.getMonth(), jst.getDate());

      // ── 冪等チェック ────────────────────────────────────────────────
      // Cloud Scheduler は at-least-once 保証のため同じジョブが2回起動される場合がある。
      // Firestore の createIfNotExists (create) をアトミックに行い、
      // すでに当日実行済みなら即リターン。
      const dateKey = `${jst.getUTCFullYear()}-${String(jst.getUTCMonth() + 1).padStart(2,'0')}-${String(jst.getUTCDate()).padStart(2,'0')}`;
      const jobRef = db.doc(`daily_job_locks/vibeNotification_${dateKey}`);
      try {
        await jobRef.create({
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // create() が成功 = 初回実行 → 処理を続行
      } catch (err) {
        if (err.code === 6 /* ALREADY_EXISTS */) {
          console.log(`dailyVibeNotification: already ran for ${dateKey}, skipping duplicate`);
          return;
        }
        throw err; // 予期しないエラーは再スロー
      }
      // ── 冪等チェックここまで ─────────────────────────────────────
      const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);

      // statusのみでクエリし、コード側で日付フィルタ（複合インデックス不要）
      const activeTopics = await db
        .collection('vibe_topics')
        .where('status', '==', 'active')
        .get();

      const todayTopicDocs = activeTopics.docs.filter(doc => {
        const topicDate = doc.data().date?.toDate();
        return topicDate && topicDate >= todayStart && topicDate < todayEnd;
      });

      if (todayTopicDocs.length === 0) {
        console.log('dailyVibeNotification: no active topic for today, skipping');
        return;
      }

      const topicDoc = todayTopicDocs[0];
      const topicData = topicDoc.data();
      const topicTitle = topicData.title; // 例: "夜中に1人で聴きたい曲"
      const topicEmoji = topicData.emoji || '🎵';
      const topicId = topicDoc.id;

      const notificationTitle = 'タップして今日の15sを投稿しよう。';
      const notificationBody = `${topicEmoji}${topicTitle}は？？`;

      // 今日のVibeにすでに投稿済みのユーザーIDを取得
      const alreadyPostedSnapshot = await db.collection('posts')
        .where('vibeTopicId', '==', topicId)
        .get();
      const alreadyPostedUserIds = new Set(
        alreadyPostedSnapshot.docs.map(d => d.data().userId).filter(Boolean)
      );
      console.log(`dailyVibeNotification: ${alreadyPostedUserIds.size} users already posted today`);

      // 全ユーザーに通知を作成（バッチ処理、500件ずつ）
      // notifVibeEnabled が false のユーザーはスキップ
      // すでに今日投稿済みのユーザーもスキップ
      const usersSnapshot = await db.collection('users').get();

      const batchSize = 500;
      let currentBatch = db.batch();
      let operationCount = 0;
      const batches = [];
      const enabledUserIds = [];

      for (const userDoc of usersSnapshot.docs) {
        const userData = userDoc.data();
        // フィールドが未設定の場合はデフォルトで通知あり（true）
        if (userData.notifVibeEnabled === false) continue;
        // 今日すでにVibe投稿済みのユーザーはスキップ
        if (alreadyPostedUserIds.has(userDoc.id)) continue;

        enabledUserIds.push(userDoc.id);

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
      console.log(`Created vibe notifications for ${enabledUserIds.length} / ${usersSnapshot.size} users`);

      // FCMプッシュ通知を通知有効ユーザーにのみ個別送信
      if (enabledUserIds.length > 0) {
        // トークン取得を10件ずつ逐次処理してFirestoreの負荷を分散
        const tokenChunkSize = 10;
        const allTokenEntries = []; // { uid, token } の配列
        for (let i = 0; i < enabledUserIds.length; i += tokenChunkSize) {
          const chunk = enabledUserIds.slice(i, i + tokenChunkSize);
          const tokenDocs = await Promise.all(
            chunk.map(uid => db.collection('user_fcm_tokens').doc(uid).get())
          );
          for (let j = 0; j < tokenDocs.length; j++) {
            const tokenDoc = tokenDocs[j];
            if (tokenDoc.exists && tokenDoc.data().tokens) {
              for (const t of tokenDoc.data().tokens) {
                allTokenEntries.push({ uid: chunk[j], token: t.token });
              }
            }
          }
        }

        const allTokens = allTokenEntries.map(e => e.token);
        const fcmChunkSize = 500;
        let totalSuccess = 0;
        let totalFailure = 0;

        for (let i = 0; i < allTokens.length; i += fcmChunkSize) {
          const chunk = allTokens.slice(i, i + fcmChunkSize);
          const chunkEntries = allTokenEntries.slice(i, i + fcmChunkSize);
          const response = await admin.messaging().sendEachForMulticast({
            tokens: chunk,
            notification: { title: notificationTitle, body: notificationBody },
            data: { notificationType: 'vibe', click_action: 'FLUTTER_NOTIFICATION_CLICK' },
            apns: {
              payload: { aps: { sound: 'default' } },
            },
            android: {
              notification: { sound: 'default' },
            },
          });

          totalSuccess += response.successCount;
          totalFailure += response.failureCount;

          // 無効なトークンを削除
          if (response.failureCount > 0) {
            const invalidByUid = {};
            response.responses.forEach((resp, idx) => {
              if (!resp.success) {
                console.error(`Vibe FCM error for token ${chunk[idx]}:`, resp.error?.code);
                if (
                  resp.error?.code === 'messaging/invalid-registration-token' ||
                  resp.error?.code === 'messaging/registration-token-not-registered'
                ) {
                  const uid = chunkEntries[idx].uid;
                  if (!invalidByUid[uid]) invalidByUid[uid] = [];
                  invalidByUid[uid].push(chunk[idx]);
                }
              }
            });

            for (const [uid, invalidTokens] of Object.entries(invalidByUid)) {
              const tokenDocRef = db.collection('user_fcm_tokens').doc(uid);
              const tokenDoc = await tokenDocRef.get();
              if (tokenDoc.exists) {
                const updatedTokens = tokenDoc.data().tokens.filter(
                  t => !invalidTokens.includes(t.token)
                );
                await tokenDocRef.update({ tokens: updatedTokens });
                console.log(`Removed ${invalidTokens.length} invalid tokens for user ${uid}`);
              }
            }
          }
        }

        console.log(`Vibe FCM sent: success=${totalSuccess}, failure=${totalFailure}, total=${allTokens.length} tokens`);
      }

      console.log('dailyVibeNotification: completed');
    } catch (error) {
      console.error('dailyVibeNotification error:', error);
    }
  }
);

/**
 * FCMトークン重複除去の共通ロジック
 */
async function _deduplicateFcmTokens(db) {
  const snapshot = await db.collection('user_fcm_tokens').get();
  let totalDocs = 0;
  let fixedDocs = 0;
  let totalRemoved = 0;

  for (const doc of snapshot.docs) {
    totalDocs++;
    const tokens = doc.data().tokens;
    if (!Array.isArray(tokens)) continue;

    // token文字列でユニーク化（最新エントリを残す）
    const seen = new Map();
    for (const entry of tokens) {
      if (entry && entry.token) seen.set(entry.token, entry);
    }

    const deduplicated = Array.from(seen.values());
    const removed = tokens.length - deduplicated.length;

    if (removed > 0) {
      await doc.ref.update({ tokens: deduplicated });
      fixedDocs++;
      totalRemoved += removed;
      console.log(`Cleaned ${doc.id}: removed ${removed} duplicate(s)`);
    }
  }

  return { totalDocs, fixedDocs, totalRemoved };
}

/**
 * FCMトークン重複クリーンアップ（管理者用HTTPS呼び出し）
 */
exports.cleanupDuplicateFcmTokens = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    const db = admin.firestore();
    const result = await _deduplicateFcmTokens(db);
    console.log('cleanupDuplicateFcmTokens completed:', result);
    return result;
  }
);

/**
 * FCMトークン重複クリーンアップ（毎週日曜 3:00 JST に自動実行）
 */
exports.weeklyCleanupDuplicateFcmTokens = onSchedule(
  { schedule: '0 3 * * 0', timeZone: 'Asia/Tokyo', timeoutSeconds: 540 },
  async () => {
    const db = admin.firestore();
    const result = await _deduplicateFcmTokens(db);
    console.log('weeklyCleanupDuplicateFcmTokens completed:', result);
  }
);

/**
 * Vibe通知を手動でテスト送信（管理者用HTTPS呼び出し）
 *
 * - skipPostedCheck: true を渡すと「今日すでに投稿済み」チェックをスキップ
 * - targetUserId を渡すと特定ユーザーにのみ送信（省略時は全ユーザー）
 */
exports.testVibeNotification = onCall(
  { timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');

    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }

    const skipPostedCheck = request.data?.skipPostedCheck === true;
    const targetUserId = request.data?.targetUserId || null;

    // 今日のactiveなお題を取得
    const now = new Date();
    const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
    const todayStart = new Date(jst.getFullYear(), jst.getMonth(), jst.getDate());
    const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);

    const activeTopics = await db.collection('vibe_topics')
      .where('status', '==', 'active')
      .get();

    const todayTopicDocs = activeTopics.docs.filter(doc => {
      const topicDate = doc.data().date?.toDate();
      return topicDate && topicDate >= todayStart && topicDate < todayEnd;
    });

    const todaysTopics = { empty: todayTopicDocs.length === 0, docs: todayTopicDocs };

    if (todaysTopics.empty) {
      // activeなお題がなければ最新のお題を使う
      const latestTopics = await db.collection('vibe_topics')
        .orderBy('date', 'desc')
        .limit(1)
        .get();

      if (latestTopics.empty) {
        throw new HttpsError('not-found', '送信できるVibeお題がありません');
      }

      console.log('testVibeNotification: no active topic today, using latest topic');
      const topicDoc = latestTopics.docs[0];
      return _sendVibeNotificationToUsers(db, topicDoc, skipPostedCheck, targetUserId);
    }

    const topicDoc = todayTopicDocs[0];
    console.log(`testVibeNotification: using topic "${topicDoc.data().title}"`);
    return _sendVibeNotificationToUsers(db, topicDoc, skipPostedCheck, targetUserId);
  }
);

/** Vibe通知送信の共通処理 */
async function _sendVibeNotificationToUsers(db, topicDoc, skipPostedCheck, targetUserId) {
  const topicData = topicDoc.data();
  const topicId = topicDoc.id;
  const notificationTitle = 'タップして今日の15sを投稿しよう。';
  const notificationBody = `${topicData.emoji || '🎵'}${topicData.title}は？？`;

  let alreadyPostedUserIds = new Set();
  if (!skipPostedCheck) {
    const alreadyPostedSnapshot = await db.collection('posts')
      .where('vibeTopicId', '==', topicId)
      .get();
    alreadyPostedUserIds = new Set(
      alreadyPostedSnapshot.docs.map(d => d.data().userId).filter(Boolean)
    );
  }

  // 送信対象ユーザーを絞り込む
  let usersToNotify = [];
  if (targetUserId) {
    const userDoc = await db.collection('users').doc(targetUserId).get();
    if (userDoc.exists && userDoc.data().notifVibeEnabled !== false) {
      if (skipPostedCheck || !alreadyPostedUserIds.has(targetUserId)) {
        usersToNotify = [targetUserId];
      }
    }
  } else {
    const usersSnapshot = await db.collection('users').get();
    for (const userDoc of usersSnapshot.docs) {
      if (userDoc.data().notifVibeEnabled === false) continue;
      if (!skipPostedCheck && alreadyPostedUserIds.has(userDoc.id)) continue;
      usersToNotify.push(userDoc.id);
    }
  }

  if (usersToNotify.length === 0) {
    return { success: true, message: '送信対象ユーザーが0人でした（全員投稿済みか通知オフ）', notificationCount: 0 };
  }

  // Firestore通知を作成
  const batchSize = 500;
  let currentBatch = db.batch();
  let operationCount = 0;
  const batches = [];
  for (const userId of usersToNotify) {
    const notificationRef = db.collection('notifications').doc();
    currentBatch.set(notificationRef, {
      type: 'vibe',
      recipientId: userId,
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
  if (operationCount > 0) batches.push(currentBatch.commit());
  await Promise.all(batches);

  // FCMプッシュ通知
  const tokenDocs = await Promise.all(
    usersToNotify.map(uid => db.collection('user_fcm_tokens').doc(uid).get())
  );
  const allTokens = [];
  for (const tokenDoc of tokenDocs) {
    if (tokenDoc.exists && tokenDoc.data().tokens) {
      allTokens.push(...tokenDoc.data().tokens.map(t => t.token).filter(Boolean));
    }
  }

  let totalSuccess = 0;
  for (let i = 0; i < allTokens.length; i += 500) {
    const chunk = allTokens.slice(i, i + 500);
    const response = await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      notification: { title: notificationTitle, body: notificationBody },
      data: { notificationType: 'vibe', click_action: 'FLUTTER_NOTIFICATION_CLICK' },
      apns: { payload: { aps: { sound: 'default' } } },
      android: { notification: { sound: 'default' } },
    });
    totalSuccess += response.successCount;
  }

  console.log(`testVibeNotification: sent to ${usersToNotify.length} users, ${totalSuccess}/${allTokens.length} FCM tokens`);
  return {
    success: true,
    message: `${usersToNotify.length}人にVibe通知を送信しました`,
    notificationCount: usersToNotify.length,
    fcmTokenCount: allTokens.length,
    fcmSuccessCount: totalSuccess,
  };
}

/**
 * ユーザードキュメント削除時のクリーンアップ
 *
 * deleteUserData() の補完として、サーバー側でも補助データを削除する。
 */
/**
 * ADL いいね集計
 *
 * 投稿の likeCount が変化したとき、投稿者の ADL 班に反映する。
 * adl_memberships/{userId} が存在する場合のみ adl_teams/{teamId}.likeCount を ±delta する。
 */
exports.adlLikeAggregation = onDocumentWritten(
  'posts/{postId}',
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after  = event.data.after.exists  ? event.data.after.data()  : null;

    const beforeCount = before?.likeCount ?? 0;
    const afterCount  = after?.likeCount  ?? 0;
    const delta = afterCount - beforeCount;
    if (delta === 0) return;

    const userId = (after ?? before)?.userId;
    if (!userId) return;

    const db = admin.firestore();
    const memberSnap = await db.doc(`adl_memberships/${userId}`).get();
    if (!memberSnap.exists) return;

    const { teamId } = memberSnap.data();
    if (!teamId) return;

    await db.doc(`adl_teams/${teamId}`).update({
      likeCount: admin.firestore.FieldValue.increment(delta),
    });

    console.log(`adlLikeAggregation: team=${teamId} delta=${delta}`);
  }
);

exports.onUserDocDeleted = onDocumentDeleted(
  'users/{userId}',
  async (event) => {
    const userId = event.params.userId;
    const db = admin.firestore();

    await Promise.allSettled([
      db.collection('user_fcm_tokens').doc(userId).delete(),
      db.collection('post_notification_states').doc(userId).delete(),
    ]);

    console.log(`onUserDocDeleted: cleaned up auxiliary data for ${userId}`);
  }
);

// ── ダミーユーザー毎日投稿 ───────────────────────────────────────────
//
// 毎日 23:55 JST に実行。
// dummy_config/{users, photos, tracks} を読み込み、
// 10人のダミーユーザーが当日ランダムな時刻（8:00〜22:59 JST）に
// 投稿したように見せる Firestore ドキュメントを一括作成する。
//
// セットアップスクリプト (scripts/setup_dummy_users.js) を先に実行して
// dummy_config を作成しておく必要がある。

// ── ダミー投稿用: アルバムアートからPostThemeを抽出するヘルパー ──
function _rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s = 0;
  const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
      case g: h = ((b - r) / d + 2) / 6; break;
      case b: h = ((r - g) / d + 4) / 6; break;
    }
  }
  return [h, s, l];
}

function _hslToRgb(h, s, l) {
  if (s === 0) { const v = Math.round(l * 255); return [v, v, v]; }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const hue2rgb = (t) => {
    if (t < 0) t += 1; if (t > 1) t -= 1;
    if (t < 1/6) return p + (q - p) * 6 * t;
    if (t < 1/2) return q;
    if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
    return p;
  };
  return [Math.round(hue2rgb(h + 1/3) * 255), Math.round(hue2rgb(h) * 255), Math.round(hue2rgb(h - 1/3) * 255)];
}

function _toArgbInt(alpha, r, g, b) {
  return (alpha & 0xFF) * 16777216 + (r & 0xFF) * 65536 + (g & 0xFF) * 256 + (b & 0xFF);
}

const _DUMMY_DEFAULT_THEME = {
  gradientStart:      0x001A1A2E,
  gradientEnd:        0xFF1A1A2E,
  commentButtonColor: 0xFF253A5E,
  textColor:          0xFFFFFFFF,
  iconColor:          0xFFFFFFFF,
};

async function _extractThemeFromAlbumArt(albumArtUrl) {
  try {
    const res = await fetch(albumArtUrl);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());

    // Flutter の PaletteGenerator.fromImageProvider と同じパイプライン:
    //   1. 200×200 にリサイズ (Flutter: size: Size(200, 200))
    //   2. デフォルトフィルタ適用（透明・白に近いピクセルを除外）
    //   3. MMCQ で colorCount=20 に量子化 (Flutter: maximumColorCount: 20)
    //   4. population 最大のスウォッチ = dominantColor
    // eslint-disable-next-line
    const NodeImage = require('node-vibrant/lib/image/node').default;
    // eslint-disable-next-line
    const { MMCQ } = require('node-vibrant/lib/quantizer');
    // eslint-disable-next-line
    const defaultFilter = require('node-vibrant/lib/filter/default').default;

    const img = new NodeImage();
    await img.load(buf);
    img.resize(200, 200, 1);

    const imageData = img.getImageData();
    const pixels = imageData.data;
    for (let i = 0; i < pixels.length / 4; i++) {
      const off = i * 4;
      if (!defaultFilter(pixels[off], pixels[off+1], pixels[off+2], pixels[off+3])) {
        pixels[off+3] = 0;
      }
    }

    const swatches = MMCQ(imageData.data, { colorCount: 20 });
    img.remove();
    if (!swatches.length) return _DUMMY_DEFAULT_THEME;

    swatches.sort((a, b) => b.population - a.population);
    const [r, g, b] = swatches[0].getRgb();

    const [h, s, l] = _rgbToHsl(r, g, b);
    const isDark = l < 0.5;
    const [cr, cg, cb] = _hslToRgb(h, s, Math.min(l * 1.1, 1.0));
    return {
      gradientStart:      _toArgbInt(0,   r,  g,  b),
      gradientEnd:        _toArgbInt(255, r,  g,  b),
      commentButtonColor: _toArgbInt(255, cr, cg, cb),
      textColor:  isDark ? 0xFFFFFFFF : 0xFF000000,
      iconColor:  isDark ? 0xFFFFFFFF : 0xFF000000,
    };
  } catch (e) {
    console.error('Theme extraction error:', e.message);
    return _DUMMY_DEFAULT_THEME;
  }
}

// レイアウト別サイズ (363×645 px カード基準) — index 0 は使用しない
const _LAYOUT_CARD_SIZES = [
  { w: 196, h: 150 }, // 0: standard (歌詞テキスト・使用しない)
  { w: 105, h: 147 }, // 1: largeAlbumArt
  { w: 172, h:  42 }, // 2: horizontalBar
  { w: 140, h: 152 }, // 3: albumArtOnly
  { w: 130, h:  61 }, // 4: musicPlayer
];

function _getCenteredCardPos(layoutIndex) {
  const size = _LAYOUT_CARD_SIZES[layoutIndex] || _LAYOUT_CARD_SIZES[1];
  return { x: (363 - size.w) / 2, y: (645 - size.h) / 2 };
}

exports.dailyDummyUserPosts = onSchedule(
  { schedule: '55 23 * * *', timeZone: 'Asia/Tokyo' },
  async () => {
    const db = admin.firestore();

    try {
      // ── 今日の JST 日付を計算 ─────────────────────────────────────
      const now = new Date();
      const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
      const jstYear  = jstNow.getUTCFullYear();
      const jstMonth = jstNow.getUTCMonth();
      const jstDate  = jstNow.getUTCDate();
      const dateKey  = `${jstYear}-${String(jstMonth + 1).padStart(2,'0')}-${String(jstDate).padStart(2,'0')}`;

      // ── 冪等チェック（日付単位で1回だけ実行）─────────────────────
      const jobRef = db.doc(`daily_job_locks/dummyPosts_${dateKey}`);
      try {
        await jobRef.create({ createdAt: admin.firestore.FieldValue.serverTimestamp() });
      } catch (err) {
        if (err.code === 6) {
          console.log(`dailyDummyUserPosts: already ran for ${dateKey}, skipping`);
          return;
        }
        throw err;
      }

      // ── 設定読み込み ────────────────────────────────────────────────
      const [usersSnap, photosSnap, tracksSnap] = await Promise.all([
        db.doc('dummy_config/users').get(),
        db.doc('dummy_config/photos').get(),
        db.doc('dummy_config/tracks').get(),
      ]);

      if (!usersSnap.exists || !photosSnap.exists || !tracksSnap.exists) {
        console.error('dailyDummyUserPosts: dummy_config が未作成です。');
        return;
      }

      const userIds       = usersSnap.data().userIds || [];
      const postPhotoUrls = photosSnap.data().postPhotoUrls || [];
      const fallbackTracks = tracksSnap.data().list || [];

      if (userIds.length === 0 || postPhotoUrls.length === 0) {
        console.error('dailyDummyUserPosts: 設定データが不足しています。');
        return;
      }

      // ── Apple Music 日本 TOP チャートを取得 ──────────────────────
      let tracks = fallbackTracks;
      try {
        const rssRes = await fetch('https://itunes.apple.com/jp/rss/topsongs/limit=50/json');
        if (!rssRes.ok) throw new Error(`RSS HTTP ${rssRes.status}`);
        const rssData = await rssRes.json();
        const entries = rssData.feed?.entry || [];
        const trackIds = entries.map(e => e.id?.attributes?.['im:id']).filter(Boolean).join(',');
        if (!trackIds) throw new Error('トラックID取得失敗');

        const lookupRes = await fetch(`https://itunes.apple.com/lookup?id=${trackIds}&country=jp`);
        const lookupData = await lookupRes.json();
        const appleTracks = (lookupData.results || [])
          .filter(r => r.wrapperType === 'track')
          .map(r => ({
            trackId:       String(r.trackId),
            trackName:     r.trackName,
            artistName:    r.artistName,
            albumImageUrl: (r.artworkUrl100 || '').replace('100x100bb', '600x600bb'),
            previewUrl:    r.previewUrl || null,
          }));
        if (appleTracks.length === 0) throw new Error('トラック0件');
        tracks = appleTracks;
        console.log(`dailyDummyUserPosts: Apple Music Japan TOP50取得成功 (${tracks.length}件)`);
      } catch (e) {
        console.error('dailyDummyUserPosts: Apple Music TOP50取得失敗、フォールバックを使用:', e.message);
      }

      // ── 今日のアクティブなVibe topicを取得 ──────────────────────
      let activeTopic = null;
      try {
        const topicSnap = await db.collection('vibe_topics').where('status', '==', 'active').limit(1).get();
        if (!topicSnap.empty) {
          const doc = topicSnap.docs[0];
          activeTopic = { id: doc.id, ...doc.data() };
          console.log(`dailyDummyUserPosts: Vibe topic="${activeTopic.title}"`);
        }
      } catch (e) {
        console.error('dailyDummyUserPosts: Vibeトピック取得エラー:', e.message);
      }

      function randomInt(min, max) {
        return Math.floor(Math.random() * (max - min + 1)) + min;
      }
      function pickRandom(arr) {
        return arr[Math.floor(Math.random() * arr.length)];
      }

      // ── ユーザーをシャッフルして投稿時刻を割り当て ──────────────
      // 0:xx JST: 7人、1:xx JST: 1人、2:xx JST: 1人、3:xx JST: 1人
      const shuffledIds = [...userIds].sort(() => Math.random() - 0.5);
      function getPostHour(index) {
        return index < 7 ? 0 : index - 6; // 0..6→0h, 7→1h, 8→2h, 9→3h
      }

      // ── ユーザー情報を一括取得 ──────────────────────────────────
      const userDocs = await Promise.all(
        shuffledIds.map(uid => db.collection('users').doc(uid).get())
      );

      // ── ランダムデータを事前に計算 ──────────────────────────────────
      const selections = shuffledIds.map(() => ({
        photoUrl:    pickRandom(postPhotoUrls),
        track:       pickRandom(tracks),
        layoutIndex: pickRandom([1, 2, 3]), // 0(歌詞テキスト)は使用しない
      }));

      // ── アルバムアートから色を並列抽出 ─────────────────────────────
      const themes = await Promise.all(
        selections.map(sel => _extractThemeFromAlbumArt(sel.track.albumImageUrl))
      );

      // ── 各ユーザーの投稿を作成 ──────────────────────────────────
      const batch = db.batch();
      let createdCount = 0;

      for (let i = 0; i < shuffledIds.length; i++) {
        const userId  = shuffledIds[i];
        const userDoc = userDocs[i];
        if (!userDoc.exists) {
          console.log(`  Skip ${userId}: ユーザードキュメントなし`);
          continue;
        }

        const userData = userDoc.data();
        const { photoUrl, track, layoutIndex } = selections[i];
        const theme   = themes[i];
        const cardPos = _getCenteredCardPos(layoutIndex);

        // 投稿時刻: getPostHour(i) 時 JST、分秒はランダム
        const postHour   = getPostHour(i);
        const postMinute = randomInt(0, 59);
        const postSecond = randomInt(0, 59);
        const postTimeJst = new Date(Date.UTC(jstYear, jstMonth, jstDate, postHour, postMinute, postSecond));
        const postTimeUtc = new Date(postTimeJst.getTime() - 9 * 60 * 60 * 1000);
        const postTimestamp = admin.firestore.Timestamp.fromDate(postTimeUtc);

        const postRef = db.collection('posts').doc();
        batch.set(postRef, {
          userId,
          username:    userData.username || '',
          userIconUrl: userData.profileImageUrl || null,
          track: {
            trackId:       track.trackId,
            trackName:     track.trackName,
            artistName:    track.artistName,
            albumImageUrl: track.albumImageUrl,
            previewUrl:    track.previewUrl || null,
            trackUrl:      null,
            lyrics:        null,
            tempo:         null,
          },
          photoUrl,
          imageOffsetX: 0.0,
          imageOffsetY: 0.0,
          imageScale:   1.0,
          imageNaturalWidth:  0.0,
          imageNaturalHeight: 0.0,
          selectedLayoutIndex: layoutIndex,
          cardPositionX: cardPos.x,
          cardPositionY: cardPos.y,
          cardScale:     1.0,
          cardRotation:  0.0,
          theme: {
            gradientStart:        theme.gradientStart,
            gradientEnd:          theme.gradientEnd,
            commentButtonColor:   theme.commentButtonColor,
            textColor:            theme.textColor,
            iconColor:            theme.iconColor,
          },
          likeCount:           0,
          commentCount:        0,
          likedUserIds:        [],
          likedByUserIconUrls: [],
          savedByUserIds:      [],
          savedByUserIconUrls: [],
          isVibe:           activeTopic !== null,
          vibeTopicId:      activeTopic?.id   || null,
          vibeTopicTitle:   activeTopic?.title || null,
          vibeDate:         activeTopic?.date  || null,
          emotionTag:       null,
          lyricsText:       null,
          audioStartMs:     0,
          audioDurationSec: 15,
          university:       userData.university || null,
          campusVibeParticipating: false,
          campusVibePost:   false,
          adlTeamId:        null,
          isDummyPost:      true,
          createdAt:        postTimestamp,
          updatedAt:        postTimestamp,
        });

        batch.update(db.collection('users').doc(userId), {
          postsCount: admin.firestore.FieldValue.increment(1),
          updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
        });

        createdCount++;
        console.log(`  ✓ ${userData.username}: ${track.trackName} - ${track.artistName} (${postHour}:${String(postMinute).padStart(2,'0')} JST)`);
      }

      await batch.commit();
      console.log(`dailyDummyUserPosts: ${createdCount}件の投稿を作成しました`);
    } catch (err) {
      console.error('dailyDummyUserPosts error:', err);
    }
  }
);
