const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

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

      const senderId = request.senderId || '';

      // プッシュ通知のペイロード
      const payload = {
        notification: {
          title: `${senderUsername}`,
          body: message,
        },
        data: {
          notificationType: notificationType,
          senderId: senderId,
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
async function sendPostNotificationDoc(db, recipientId, senderId, senderUsername, senderIconUrl, message, notifDocId, postId) {
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
    notification: { title: senderUsername, body: message },
    data: {
      notificationType: 'post',
      senderId: senderId || '',
      postId: postId || '',
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
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
 * 1フォロワーへの通知状態遷移を処理
 *
 * 状態遷移:
 *   [ドキュメントなし / 日付違い] → 即時通知 → TIMER_ACTIVE (notificationsSentToday=1)
 *   [TIMER_ACTIVE]               → batchedSenderIds に追加（通知なし）
 *   [TIMER_EXPIRED_EMPTY]        → 即時通知 → DONE (notificationsSentToday=2)
 *   [DONE]                       → スキップ
 */
async function processPostNotificationForRecipient(db, recipientId, senderId, senderUsername, senderIconUrl, postId) {
  const today = getJstDateString();
  const stateRef = db.collection('post_notification_states').doc(recipientId);

  let action = 'skip';
  let notifDocId = null;
  let notifMessage = null;
  let notifPostId = null;

  await db.runTransaction(async (tx) => {
    const stateDoc = await tx.get(stateRef);
    const state = stateDoc.exists ? stateDoc.data() : null;
    const needsReset = !state || state.lastResetDate !== today;

    if (needsReset) {
      // その日の通知0通 → 即時通知 + TIMER_ACTIVE 開始
      action = 'send_immediate';
      notifDocId = `post_${postId}_${recipientId}`;
      notifMessage = `${senderUsername}が投稿しました。`;
      notifPostId = postId;
      tx.set(stateRef, {
        phase: 'TIMER_ACTIVE',
        notificationsSentToday: 1,
        batchedSenderIds: [],
        batchedSenderUsernames: [],
        timerStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastResetDate: today,
      });
    } else if (state.phase === 'TIMER_ACTIVE') {
      // タイマー中 → batchedSenderIds に追加（通知なし）
      action = 'batch';
      const newIds = [...(state.batchedSenderIds || [])];
      const newNames = [...(state.batchedSenderUsernames || [])];
      if (!newIds.includes(senderId)) {
        newIds.push(senderId);
        newNames.push(senderUsername);
      }
      tx.update(stateRef, {
        batchedSenderIds: newIds,
        batchedSenderUsernames: newNames,
      });
    } else if (state.phase === 'TIMER_EXPIRED_EMPTY') {
      // タイマー切れ（その日2件目の投稿） → 即時通知 → DONE
      action = 'send_immediate';
      notifDocId = `post_${postId}_${recipientId}`;
      notifMessage = `${senderUsername}が投稿しました。`;
      notifPostId = postId;
      tx.update(stateRef, {
        phase: 'DONE',
        notificationsSentToday: admin.firestore.FieldValue.increment(1),
      });
    }
    // DONE → action = 'skip' のまま
  });

  if (action === 'send_immediate') {
    await sendPostNotificationDoc(
      db, recipientId, senderId, senderUsername, senderIconUrl,
      notifMessage, notifDocId, notifPostId
    );
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
              db, followerId, posterId, posterUsername, posterIconUrl, postDocId
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
 * - batchedSenderIds > 0 → パターンA: 「〇人が投稿しました」まとめ通知 → DONE
 * - batchedSenderIds == 0 → パターンC: TIMER_EXPIRED_EMPTY へ遷移
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
        const state = doc.data();
        const recipientId = doc.id;
        const batchedSenderIds = state.batchedSenderIds || [];
        const batchedSenderUsernames = state.batchedSenderUsernames || [];

        if (batchedSenderIds.length > 0) {
          // パターンA: まとめ通知 → DONE
          const count = batchedSenderIds.length;
          const firstUsername = batchedSenderUsernames[0] || 'Unknown';
          const message = count === 1
            ? `${firstUsername}が投稿しました。`
            : `${firstUsername}さんなど${count}人が投稿しました。`;

          await doc.ref.update({
            phase: 'DONE',
            notificationsSentToday: admin.firestore.FieldValue.increment(1),
            batchedSenderIds: [],
            batchedSenderUsernames: [],
          });

          const notifDocId = `batch_${recipientId}_${today}`;
          await sendPostNotificationDoc(
            db, recipientId,
            batchedSenderIds[0], firstUsername, null,
            message, notifDocId, null
          );

          console.log(`checkPostNotificationTimers: batch sent to ${recipientId} (${count} senders)`);
        } else {
          // パターンC: 3時間タイマー切れ、溜まった投稿なし → TIMER_EXPIRED_EMPTY
          await doc.ref.update({ phase: 'TIMER_EXPIRED_EMPTY' });
          console.log(`checkPostNotificationTimers: ${recipientId} -> TIMER_EXPIRED_EMPTY`);
        }
      }

      console.log('checkPostNotificationTimers: completed');
    } catch (error) {
      console.error('checkPostNotificationTimers error:', error);
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
      // notifVibeEnabled が false のユーザーはスキップ
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
        const tokenDocs = await Promise.all(
          enabledUserIds.map(uid => db.collection('user_fcm_tokens').doc(uid).get())
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
          await admin.messaging().sendEachForMulticast({
            tokens: chunk,
            notification: { title: notificationTitle, body: notificationBody },
            data: { notificationType: 'vibe', click_action: 'FLUTTER_NOTIFICATION_CLICK' },
          });
        }
        console.log(`Vibe FCM sent to ${allTokens.length} tokens`);
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
 * ユーザードキュメント削除時のクリーンアップ
 *
 * deleteUserData() の補完として、サーバー側でも補助データを削除する。
 */
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
