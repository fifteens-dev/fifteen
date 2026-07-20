const { onDocumentCreated, onDocumentDeleted, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const crypto = require('crypto');

admin.initializeApp();

/**
 * Apple Music Developer Token を .p8 秘密鍵からその場で署名生成する（ES256/JWT）。
 * これによりトークンは常に新鮮になり、6か月ごとの手動再発行・アプリ更新が不要になる。
 * 必要な環境変数（functions/.env）:
 *   APPLE_MUSIC_TEAM_ID, APPLE_MUSIC_KEY_ID, APPLE_MUSIC_PRIVATE_KEY(PEM, \n エスケープ可)
 * 生成不可（鍵未設定等）の場合は静的な APPLE_MUSIC_DEVELOPER_TOKEN にフォールバック。
 */
function generateAppleMusicDeveloperToken() {
  const teamId = process.env.APPLE_MUSIC_TEAM_ID;
  const keyId = process.env.APPLE_MUSIC_KEY_ID;
  let pem = process.env.APPLE_MUSIC_PRIVATE_KEY;
  if (!teamId || !keyId || !pem) {
    throw new Error('Apple Music 署名用の環境変数が未設定です');
  }
  pem = pem.replace(/\\n/g, '\n');

  const now = Math.floor(Date.now() / 1000);
  const exp = now + 15552000; // 180日（Apple の上限は約6か月）
  const b64url = (obj) =>
    Buffer.from(JSON.stringify(obj)).toString('base64url');
  const signingInput =
    `${b64url({ alg: 'ES256', kid: keyId, typ: 'JWT' })}.` +
    `${b64url({ iss: teamId, iat: now, exp })}`;
  const signature = crypto
    .sign('sha256', Buffer.from(signingInput), {
      key: pem,
      dsaEncoding: 'ieee-p1363', // JOSE 形式（r||s, 64byte）
    })
    .toString('base64url');
  return `${signingInput}.${signature}`;
}

/**
 * クライアントに Apple Music Developer Token を配信する callable。
 * クライアントはこれを取得・キャッシュして API 呼び出しに使う。
 * トークン失効時はこの関数の再デプロイ（or 鍵差し替え）だけで直り、アプリ更新は不要。
 */
exports.getAppleMusicDeveloperToken = onCall(async (request) => {
  try {
    return { token: generateAppleMusicDeveloperToken() };
  } catch (e) {
    const fallback = process.env.APPLE_MUSIC_DEVELOPER_TOKEN;
    if (fallback) {
      console.warn('署名生成に失敗、静的トークンにフォールバック:', e.message);
      return { token: fallback };
    }
    console.error('Apple Music トークン発行に失敗:', e);
    throw new HttpsError('internal', 'developer token unavailable');
  }
});

/** 投稿通知のタイトルをランダムに選ぶ */
function randomPostTitle() {
  return Math.random() < 0.5 ? 'もう見た？' : '気になる？';
}

/**
 * 指定ユーザー群へ FCM プッシュ通知を一斉送信する共通ヘルパー。
 * user_fcm_tokens からトークンを集め、500件ずつ送信し、無効トークンを掃除する。
 */
async function broadcastPush(db, userIds, { title, body, data }) {
  if (!userIds || userIds.length === 0) return { success: 0, failure: 0 };

  // トークン収集（10件ずつ逐次で Firestore 負荷分散）
  const tokenChunkSize = 10;
  const allTokenEntries = []; // { uid, token }
  for (let i = 0; i < userIds.length; i += tokenChunkSize) {
    const chunk = userIds.slice(i, i + tokenChunkSize);
    const tokenDocs = await Promise.all(
      chunk.map((uid) => db.collection('user_fcm_tokens').doc(uid).get())
    );
    tokenDocs.forEach((tokenDoc, j) => {
      if (tokenDoc.exists && tokenDoc.data().tokens) {
        for (const t of tokenDoc.data().tokens) {
          if (t && t.token) allTokenEntries.push({ uid: chunk[j], token: t.token });
        }
      }
    });
  }

  const allTokens = allTokenEntries.map((e) => e.token);
  const fcmChunkSize = 500;
  let success = 0;
  let failure = 0;

  for (let i = 0; i < allTokens.length; i += fcmChunkSize) {
    const chunk = allTokens.slice(i, i + fcmChunkSize);
    const chunkEntries = allTokenEntries.slice(i, i + fcmChunkSize);
    const response = await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      notification: { title, body },
      data: data || {},
      apns: { payload: { aps: { sound: 'default' } } },
      android: { notification: { sound: 'default' } },
    });
    success += response.successCount;
    failure += response.failureCount;

    if (response.failureCount > 0) {
      const invalidByUid = {};
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          if (
            resp.error?.code === 'messaging/invalid-registration-token' ||
            resp.error?.code === 'messaging/registration-token-not-registered'
          ) {
            const uid = chunkEntries[idx].uid;
            (invalidByUid[uid] = invalidByUid[uid] || []).push(chunk[idx]);
          }
        }
      });
      for (const [uid, invalidTokens] of Object.entries(invalidByUid)) {
        const ref = db.collection('user_fcm_tokens').doc(uid);
        const doc = await ref.get();
        if (doc.exists) {
          await ref.update({
            tokens: doc.data().tokens.filter((t) => !invalidTokens.includes(t.token)),
          });
        }
      }
    }
  }
  return { success, failure };
}

/**
 * Music Memory 投稿通知。
 *
 * - 毎日 19:00〜23:30 JST の「ランダムな 5 分刻みの時刻」に 1 回だけ全ユーザーへ送る。
 * - 実際に発火した時刻を `music_memory_state/current.notifiedAt` に記録し、
 *   これがクライアントの「投稿サイクル境界（＝この時刻以降がその日の投稿）」になる。
 * - 5分間隔で走り、(1) 当日の発火時刻を未決なら決定、(2) 到来していれば発火。
 *   at-least-once の重複起動に備え、状態ドキュメントのトランザクションで発火を排他。
 *
 * 文言は Apple Music / Spotify 共通の統一版。
 */
const MM_STATE_REF_PATH = 'music_memory_state/current';
const MM_WINDOW_START_MIN = 19 * 60;      // 19:00
const MM_WINDOW_END_MIN = 23 * 60 + 30;   // 23:30
const MM_NOTIF_TITLE = '🎵 Music Memoryの時間です。';
const MM_NOTIF_BODY = '25:00までに投稿すると、友達の今日が見られます。';

exports.musicMemoryDailyNotification = onSchedule(
  { schedule: '*/5 * * * *', timeZone: 'Asia/Tokyo', timeoutSeconds: 300 },
  async () => {
    const db = admin.firestore();
    const now = new Date();
    const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
    const dateKey = `${jst.getUTCFullYear()}-${String(jst.getUTCMonth() + 1).padStart(2, '0')}-${String(jst.getUTCDate()).padStart(2, '0')}`;
    const jstMinutes = jst.getUTCHours() * 60 + jst.getUTCMinutes();
    const jstDayStartUtc = jstDayStartFor(now); // JST 00:00 に対応する UTC Date
    const stateRef = db.doc(MM_STATE_REF_PATH);

    try {
      // 発火を排他的に「予約→確定」する。副作用(FCM送信)はトランザクション外で行う。
      const shouldFire = await db.runTransaction(async (tx) => {
        const snap = await tx.get(stateRef);
        const s = snap.exists ? snap.data() : {};
        const updates = {};

        // (1) 当日の発火時刻が未決なら、19:00〜23:30 の 5 分刻みからランダムに決定。
        //     過去スロットは避けるため現在時刻以降のスロットから選ぶ。
        let scheduledForTs = s.scheduleDate === dateKey ? s.scheduledFor : null;
        if (!scheduledForTs && jstMinutes <= MM_WINDOW_END_MIN) {
          const startSlot = Math.max(MM_WINDOW_START_MIN, Math.ceil(jstMinutes / 5) * 5);
          if (startSlot <= MM_WINDOW_END_MIN) {
            const nSlots = Math.floor((MM_WINDOW_END_MIN - startSlot) / 5) + 1;
            const pickMin = startSlot + 5 * Math.floor(Math.random() * nSlots);
            const fireDate = new Date(jstDayStartUtc.getTime() + pickMin * 60 * 1000);
            scheduledForTs = admin.firestore.Timestamp.fromDate(fireDate);
            updates.scheduleDate = dateKey;
            updates.scheduledFor = scheduledForTs;
          }
        }

        // (2) 予約時刻を過ぎており、当日未送信なら発火を確定。
        let fire = false;
        if (
          scheduledForTs &&
          now >= scheduledForTs.toDate() &&
          s.lastNotifiedDate !== dateKey
        ) {
          fire = true;
          updates.lastNotifiedDate = dateKey;
          updates.notifiedAt = admin.firestore.FieldValue.serverTimestamp();
        }

        if (Object.keys(updates).length > 0) {
          tx.set(stateRef, updates, { merge: true });
        }
        return fire;
      });

      if (!shouldFire) return;

      // 通知有効ユーザー（notifVibeEnabled !== false）を対象に送信。
      const usersSnapshot = await db.collection('users').get();
      const targetUserIds = usersSnapshot.docs
        .filter((d) => d.data().notifVibeEnabled !== false)
        .map((d) => d.id);

      // アプリ内通知（一覧表示用）をバッチ作成。
      const batchSize = 500;
      let batch = db.batch();
      let ops = 0;
      const batches = [];
      for (const uid of targetUserIds) {
        const ref = db.collection('notifications').doc();
        batch.set(ref, {
          type: 'music_memory',
          recipientId: uid,
          senderId: 'system',
          senderUsername: '15s',
          title: MM_NOTIF_TITLE,
          body: MM_NOTIF_BODY,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          readAt: null,
        });
        if (++ops >= batchSize) {
          batches.push(batch.commit());
          batch = db.batch();
          ops = 0;
        }
      }
      if (ops > 0) batches.push(batch.commit());
      await Promise.all(batches);

      const res = await broadcastPush(db, targetUserIds, {
        title: MM_NOTIF_TITLE,
        body: MM_NOTIF_BODY,
        data: { notificationType: 'music_memory', click_action: 'FLUTTER_NOTIFICATION_CLICK' },
      });
      console.log(
        `musicMemoryDailyNotification fired for ${dateKey}: users=${targetUserIds.length}, fcm success=${res.success}, failure=${res.failure}`
      );
    } catch (error) {
      console.error('musicMemoryDailyNotification error:', error);
    }
  }
);

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
      // ラウンドトリップ削減のため whereIn (最大30件/クエリ) で一括取得
      const followersToProcess = followers.length > 1000 ? followers.slice(0, 1000) : followers;
      const whereInLimit = 30;
      const enabledFollowers = [];
      for (let i = 0; i < followersToProcess.length; i += whereInLimit) {
        const chunk = followersToProcess.slice(i, i + whereInLimit);
        const snap = await db
          .collection('users')
          .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
          .get();
        for (const doc of snap.docs) {
          if (doc.data().notifPostEnabled !== false) {
            enabledFollowers.push(doc.id);
          }
        }
      }

      console.log(`onPostCreated: ${enabledFollowers.length} / ${followers.length} followers enabled`);

      // 各フォロワーの状態遷移を処理 (10件ずつ並列実行)
      const chunkSize = 10;
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
      // jstDayStartFor() は JST 00:00 を UTC モーメントとして返す。
      // 以前は new Date(y,m,d) を使っていたが、Cloud Functions の TZ が UTC のため
      // 結果が「JST 09:00」相当にずれ、JST 00:00 に手動作成された当日のお題が
      // todayStart 未満と判定されて archive → ランダム生成に置き換わるバグがあった。
      const now = new Date();
      const jst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
      const todayStart = jstDayStartFor(now);
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

// 旧 dailyVibeNotification(20:00固定) は削除。
// Music Memory 投稿通知は musicMemoryDailyNotification（19:00-23:30 ランダム）に統合。

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

    // 今日のactiveなお題を取得（JST基準）
    // jstDayStartFor() で正しい JST 00:00 UTC モーメントを得る。
    const now = new Date();
    const todayStart = jstDayStartFor(now);
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
 * adl_config/current から チーム賞期間（teamRankingStart〜teamRankingEnd）を読む。
 * 設定されていない場合は null を返し、呼び出し側は「期間制限なし（全期間集計）」として扱う。
 *
 * インスタンス内で5分間キャッシュし、いいね集中時の Firestore 読み取りを削減する。
 * ADL期間中に設定変更した場合、最大5分後に反映される。
 */
let _teamRankingWindowCache = undefined;
let _teamRankingWindowCacheExpiry = 0;
const _TEAM_RANKING_WINDOW_TTL_MS = 5 * 60 * 1000;

async function getTeamRankingWindow() {
  const now = Date.now();
  if (_teamRankingWindowCache !== undefined && now < _teamRankingWindowCacheExpiry) {
    return _teamRankingWindowCache;
  }
  try {
    const snap = await admin.firestore().doc('adl_config/current').get();
    if (!snap.exists) {
      _teamRankingWindowCache = null;
    } else {
      const data = snap.data() || {};
      const start = data.teamRankingStart?.toDate?.() || null;
      const end = data.teamRankingEnd?.toDate?.() || null;
      _teamRankingWindowCache = (!start || !end) ? null : { start, end };
    }
    _teamRankingWindowCacheExpiry = now + _TEAM_RANKING_WINDOW_TTL_MS;
    return _teamRankingWindowCache;
  } catch (e) {
    console.warn('getTeamRankingWindow failed:', e);
    // エラー時は古いキャッシュをそのまま返す（nullよりはマシ）
    return _teamRankingWindowCache ?? null;
  }
}

/**
 * 投稿の作成日時がチーム賞期間内かを判定する。
 * window が null（期間未設定）の場合は常に true（全期間集計）。
 */
function isPostInTeamRankingWindow(postData, window) {
  if (!window) return true;
  const createdAt = postData?.createdAt?.toDate?.() || null;
  if (!createdAt) return false;
  return createdAt >= window.start && createdAt < window.end;
}

/**
 * 与えた UTC Date を含む JST 日付の 0:00:00 (UTCで表現) を返す。
 * 例: 2026-06-08 14:00:00 UTC → 2026-06-08 15:00:00 UTC（JSTでは6/9 0:00）の手前である
 *     6/8 15:00 JST = 6/8 06:00 UTC を返す
 */
function jstDayStartFor(utcDate) {
  const jstOffsetMs = 9 * 60 * 60 * 1000;
  const jstTs = new Date(utcDate.getTime() + jstOffsetMs);
  const jstDayUtcMs = Date.UTC(
    jstTs.getUTCFullYear(), jstTs.getUTCMonth(), jstTs.getUTCDate()
  );
  return new Date(jstDayUtcMs - jstOffsetMs);
}

/**
 * 同じ userId が同 JST 日にこれより早い ADL 投稿を持っているか判定する。
 * いれば「初回ではない」= false を返す。
 *
 * 既存の `userId ASC + createdAt DESC` 複合インデックスにマッチさせるため
 * 明示的に orderBy('createdAt', 'desc') を付ける（無いとクエリが失敗していた）。
 */
async function isFirstAdlPostOfDay(post, db) {
  const userId = post?.userId;
  const createdAt = post?.createdAt?.toDate?.();
  if (!userId || !createdAt) return false;
  const dayStart = jstDayStartFor(createdAt);
  const snap = await db.collection('posts')
    .where('userId', '==', userId)
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart))
    .where('createdAt', '<', admin.firestore.Timestamp.fromDate(createdAt))
    .orderBy('createdAt', 'desc')
    .limit(20)
    .get();
  for (const d of snap.docs) {
    if (d.data().adlTeamId) return false;
  }
  return true;
}

/**
 * 初回投稿が消えた時の昇格処理。
 * 同 JST 日・同 userId の中で次に古い ADL 投稿を探し、
 * countsForAdl=false なら true に書き換える（書き換えがトリガーされて加算される）。
 * countsForAdl=true は既に集計済み、undefined はレガシー（既に集計済みとして放置）。
 */
async function promoteNextAdlPostIfAny(before, db) {
  const userId = before?.userId;
  const createdAt = before?.createdAt?.toDate?.();
  if (!userId || !createdAt) return;
  const dayStart = jstDayStartFor(createdAt);
  const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
  // 既存の `userId ASC + createdAt DESC` インデックスに合わせ DESC で取得 → 反転で最古を取る。
  const snap = await db.collection('posts')
    .where('userId', '==', userId)
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart))
    .where('createdAt', '<', admin.firestore.Timestamp.fromDate(dayEnd))
    .orderBy('createdAt', 'desc')
    .get();
  const docs = snap.docs.slice().reverse();
  for (const d of docs) {
    const data = d.data();
    if (!data.adlTeamId) continue;
    if (data.countsForAdl === true) return; // 既に集計済み
    if (data.countsForAdl === false) {
      await d.ref.set({ countsForAdl: true }, { merge: true });
      return;
    }
    // countsForAdl === undefined（レガシー）はバックフィル後 false/true のいずれかになるので
    // ここでは扱わない（バックフィル前は集計済みとして放置）。
    return;
  }
}

/**
 * 集計対象として扱うかどうかを判定する。
 * - team window 外 → false
 * - adlTeamId なし → false
 * - countsForAdl === true → true
 * - それ以外（false / undefined）→ false
 *
 * 既存（フラグなし）投稿は backfillCountsForAdl callable で flag が付くまで集計対象外。
 * 既存 adl_teams 集計値は触らない方針なので、新規 like だけが影響を受ける。
 */
function effectiveCountedForAdl(state, window) {
  if (!state) return false;
  if (!state.adlTeamId) return false;
  if (!isPostInTeamRankingWindow(state, window)) return false;
  return state.countsForAdl === true;
}

/**
 * ADL いいね・投稿数集計
 *
 * posts コレクションの書き込みを監視し、post.adlTeamId に紐づく
 * adl_teams/{teamId} の likeCount / postCount を増減する。
 *
 * 投稿の adlTeamId が書き換わった場合は旧班から減算し新班に加算する（班変更対応）。
 * 投稿削除時は対応する班から likeCount と postCount を減算する。
 * post.adlTeamId フィールドを使用するため、投稿時点の所属班に固定される
 * （投稿者が後で別班に移っても、過去投稿のいいねは元の班に帰属し続ける）。
 *
 * チーム賞期間（teamRankingStart〜teamRankingEnd）が設定されている場合、
 * post.createdAt が期間内のときだけ集計対象になる。
 */
exports.adlLikeAggregation = onDocumentWritten(
  'posts/{postId}',
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after  = event.data.after.exists  ? event.data.after.data()  : null;
    const postId = event.params.postId;

    const window = await getTeamRankingWindow();
    const db = admin.firestore();
    const FieldValue = admin.firestore.FieldValue;

    // ── Case 1: 新規投稿でフラグ未付与 ─────────────────────────────
    // 「1人1日1投稿（初回のみカウント）」を判定し、フラグを書き戻す。
    // フラグ書き戻しが次の trigger を引き起こすが、Case 2 で早期 return する。
    if (!before && after && after.countsForAdl === undefined) {
      let desired = false;
      let reason = 'default';
      try {
        if (!after.adlTeamId) {
          reason = 'no-adlTeamId';
        } else if (!isPostInTeamRankingWindow(after, window)) {
          reason = 'outside-window';
        } else {
          desired = await isFirstAdlPostOfDay(after, db);
          reason = desired ? 'first-of-day' : 'already-posted-today';
        }
      } catch (e) {
        // クエリ失敗時は安全側 (false) に倒し、必ずフラグは書き込む。
        // 過去はクエリエラーで関数全体が落ち、フラグが書かれず legacy 扱いになり
        // すべてカウントされてしまっていた。
        console.error(`adlLikeAggregation[new]: ${postId} query failed`, e);
        desired = false;
        reason = 'query-error';
      }
      try {
        if (desired && after.adlTeamId) {
          await db.doc(`adl_teams/${after.adlTeamId}`).update({
            likeCount: FieldValue.increment(after.likeCount || 0),
            postCount: FieldValue.increment(1),
          });
        }
        await event.data.after.ref.set({ countsForAdl: desired }, { merge: true });
      } catch (e) {
        console.error(`adlLikeAggregation[new]: ${postId} write failed`, e);
      }
      console.log(`adlLikeAggregation[new]: ${postId} countsForAdl=${desired} reason=${reason}`);
      return;
    }

    // ── Case 2: 自分の書き戻しで発火した phase 3 ───────────────────
    // before にフラグが無く after に付いた状態。集計は Case 1 で済んでいるのでスキップ。
    if (before && after &&
        before.countsForAdl === undefined &&
        after.countsForAdl !== undefined) {
      return;
    }

    // ── Case 3: 通常の更新/削除/班変更/フラグ昇格 ────────────────────
    const beforeCounted = effectiveCountedForAdl(before, window);
    const afterCounted  = effectiveCountedForAdl(after,  window);
    const beforeCount   = before?.likeCount ?? 0;
    const afterCount    = after?.likeCount  ?? 0;
    const beforeTeamId  = before?.adlTeamId ?? null;
    const afterTeamId   = after?.adlTeamId  ?? null;

    const updates = new Map();
    const addUpdate = (teamId, likeDelta, postDelta) => {
      if (!teamId) return;
      const cur = updates.get(teamId) || { likeDelta: 0, postDelta: 0 };
      cur.likeDelta += likeDelta;
      cur.postDelta += postDelta;
      updates.set(teamId, cur);
    };

    if (beforeCounted) addUpdate(beforeTeamId, -beforeCount, -1);
    if (afterCounted)  addUpdate(afterTeamId,  afterCount,  1);

    if (updates.size > 0) {
      const batch = db.batch();
      for (const [teamId, { likeDelta, postDelta }] of updates) {
        const update = {};
        if (likeDelta !== 0) update.likeCount = FieldValue.increment(likeDelta);
        if (postDelta !== 0) update.postCount = FieldValue.increment(postDelta);
        if (Object.keys(update).length > 0) {
          batch.update(db.doc(`adl_teams/${teamId}`), update);
        }
      }
      await batch.commit();
    }

    // ── Case 3 補助: 初回投稿を失った場合は次の投稿を昇格 ─────────
    // before が集計対象、after が（削除 or 班外し or フラグ false）になった時のみ。
    if (beforeCounted && !afterCounted) {
      await promoteNextAdlPostIfAny(before, db);
    }

    if (updates.size > 0) {
      console.log(`adlLikeAggregation[diff]: ${JSON.stringify(Array.from(updates))}`);
    }
  }
);

/**
 * ADL 班集計の再計算（管理者限定 callable）
 *
 * posts コレクションを全走査し、adlTeamId ごとに likeCount/postCount を再集計して
 * adl_teams/{teamId} に書き戻す。ドリフト修正用。
 *
 * チーム賞期間（teamRankingStart〜teamRankingEnd）が設定されている場合は
 * 期間内の投稿のみを集計対象にする。
 *
 * 9固定班すべてに対して書き込む（対象投稿がない班は 0 にリセット）。
 */
exports.adlRecomputeLikeCounts = onCall(async (request) => {
  // 認証 + 管理者チェック
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'ログインが必要です');
  }
  const uid = request.auth.uid;
  const userSnap = await admin.firestore().doc(`users/${uid}`).get();
  if (!userSnap.exists || userSnap.data()?.isAdmin !== true) {
    throw new HttpsError('permission-denied', '管理者権限がありません');
  }

  const FIXED_TEAM_IDS = [
    'adl_house', 'adl_break', 'adl_girls', 'adl_hiphop', 'adl_new',
    'adl_free', 'adl_lock', 'adl_waack', 'adl_jazz',
  ];

  const db = admin.firestore();
  const window = await getTeamRankingWindow();

  // 全 posts を読み（adlTeamId を持つもののみ集計、期間設定があれば絞る）
  const postsSnap = await db.collection('posts').get();
  const totals = {};
  for (const id of FIXED_TEAM_IDS) {
    totals[id] = { likeCount: 0, postCount: 0 };
  }
  for (const doc of postsSnap.docs) {
    const data = doc.data();
    const teamId = data.adlTeamId;
    if (!teamId || !totals[teamId]) continue;
    if (!isPostInTeamRankingWindow(data, window)) continue;
    // 「1人1日1投稿（初回のみカウント）」ルールに従い、countsForAdl=true のみ集計対象。
    // 自動集計トリガー (adlLikeAggregation) と整合性を保つため、ここでも必須。
    if (data.countsForAdl !== true) continue;
    totals[teamId].likeCount += data.likeCount ?? 0;
    totals[teamId].postCount += 1;
  }

  const batch = db.batch();
  for (const teamId of FIXED_TEAM_IDS) {
    batch.update(db.doc(`adl_teams/${teamId}`), {
      likeCount: totals[teamId].likeCount,
      postCount: totals[teamId].postCount,
    });
  }
  await batch.commit();

  console.log(`adlRecomputeLikeCounts by ${uid}: ${JSON.stringify(totals)}`);
  return { success: true, totals };
});

/**
 * Vibeお題の投稿数 (vibe_topics/{topicId}.postCount) をリアルタイム集計する。
 *
 * onPostCreated / onPostDeleted / onPostUpdated を統合し、
 * post.isVibe == true かつ post.vibeTopicId が変化したときに
 * 該当する vibe_topics ドキュメントの postCount を増減する。
 *
 * 検索画面の「N件の投稿」表示はこのフィールドを参照するため、
 * トリガーが落ちると 0 件表示のドリフトが起こる。
 */
exports.vibeTopicPostAggregation = onDocumentWritten(
  'posts/{postId}',
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after  = event.data.after.exists  ? event.data.after.data()  : null;

    // 「Vibe投稿として集計対象」かどうかの判定
    const countedBefore = !!(before && before.isVibe === true && before.vibeTopicId);
    const countedAfter  = !!(after  && after.isVibe  === true && after.vibeTopicId);

    const beforeTopicId = countedBefore ? before.vibeTopicId : null;
    const afterTopicId  = countedAfter  ? after.vibeTopicId  : null;

    if (beforeTopicId === afterTopicId) return; // 変化なし

    const db = admin.firestore();
    const FieldValue = admin.firestore.FieldValue;
    const batch = db.batch();
    if (beforeTopicId) {
      batch.set(
        db.doc(`vibe_topics/${beforeTopicId}`),
        { postCount: FieldValue.increment(-1) },
        { merge: true },
      );
    }
    if (afterTopicId) {
      batch.set(
        db.doc(`vibe_topics/${afterTopicId}`),
        { postCount: FieldValue.increment(1) },
        { merge: true },
      );
    }
    await batch.commit();
  }
);

/**
 * vibe_topics.postCount を全走査で再集計する管理者用 callable。
 * ドリフト修正・初回シード用。
 */
exports.recomputeVibeTopicPostCounts = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'ログインが必要です');
  }
  const uid = request.auth.uid;
  const userSnap = await admin.firestore().doc(`users/${uid}`).get();
  if (!userSnap.exists || userSnap.data()?.isAdmin !== true) {
    throw new HttpsError('permission-denied', '管理者権限がありません');
  }

  const db = admin.firestore();

  // 全 posts を走査 → vibeTopicId 別にカウント
  const postsSnap = await db.collection('posts')
    .where('isVibe', '==', true)
    .get();
  const counts = {};
  for (const doc of postsSnap.docs) {
    const topicId = doc.data().vibeTopicId;
    if (!topicId) continue;
    counts[topicId] = (counts[topicId] || 0) + 1;
  }

  // 既存 vibe_topics 一覧を取得（集計結果が無い場合は 0 にリセット）
  const topicsSnap = await db.collection('vibe_topics').get();
  const allTopicIds = new Set(topicsSnap.docs.map(d => d.id));
  for (const id of Object.keys(counts)) allTopicIds.add(id);

  // 450件ずつバッチコミット
  const ids = Array.from(allTopicIds);
  let written = 0;
  for (let i = 0; i < ids.length; i += 450) {
    const batch = db.batch();
    for (const id of ids.slice(i, i + 450)) {
      batch.set(
        db.collection('vibe_topics').doc(id),
        { postCount: counts[id] || 0 },
        { merge: true },
      );
      written++;
    }
    await batch.commit();
  }

  console.log(`recomputeVibeTopicPostCounts by ${uid}: ${written} topics, ${Object.keys(counts).length} non-zero`);
  return { success: true, topicCount: written, nonZeroCount: Object.keys(counts).length };
});

/**
 * 班員数 (adl_teams/{teamId}.memberCount) を実態に合わせて再集計する。
 * users.adlTeamId の実数を数え直し、班アカウント自身 (users/{teamId}) は除外する。
 *
 * ドリフト要因:
 *   - ダミーユーザー一括削除で leaveTeam を経由していない
 *   - 管理 console から直接 users を削除した
 *   - アカウント削除フローで班抜けが呼ばれていない
 */
exports.adlRecomputeMemberCounts = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'ログインが必要です');
  }
  const uid = request.auth.uid;
  const userSnap = await admin.firestore().doc(`users/${uid}`).get();
  if (!userSnap.exists || userSnap.data()?.isAdmin !== true) {
    throw new HttpsError('permission-denied', '管理者権限がありません');
  }

  const FIXED_TEAM_IDS = [
    'adl_house', 'adl_break', 'adl_girls', 'adl_hiphop', 'adl_new',
    'adl_free', 'adl_lock', 'adl_waack', 'adl_jazz',
  ];

  const db = admin.firestore();
  const counts = {};
  for (const id of FIXED_TEAM_IDS) counts[id] = 0;

  // users コレクションを一括で読む（adlTeamId を持つもののみ集計）
  const usersSnap = await db.collection('users').get();
  for (const doc of usersSnap.docs) {
    const teamId = doc.data().adlTeamId;
    if (!teamId || !FIXED_TEAM_IDS.includes(teamId)) continue;
    // 班アカウント自身 (users/{teamId}) は実メンバーに含めない
    if (doc.id === teamId) continue;
    counts[teamId] += 1;
  }

  const batch = db.batch();
  for (const teamId of FIXED_TEAM_IDS) {
    batch.update(db.doc(`adl_teams/${teamId}`), {
      memberCount: counts[teamId],
    });
  }
  await batch.commit();

  console.log(`adlRecomputeMemberCounts by ${uid}: ${JSON.stringify(counts)}`);
  return { success: true, counts };
});

/**
 * 本人アカウント削除（Admin SDK 経由）
 *
 * クライアントの user.delete() は requires-recent-login が必要だが、
 * Admin SDK は制約なしで削除できるため、再認証が完了できないケースでも動作する。
 * request.auth で呼び出し元が本人であることを検証する。
 */
exports.deleteCurrentUser = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'ログインが必要です');
  }
  const uid = request.auth.uid;
  await admin.auth().deleteUser(uid);
  console.log(`deleteCurrentUser: deleted auth user ${uid}`);
  return { success: true };
});

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

/**
 * ダミー投稿生成で使う「今日(JST)のアクティブな汎用Vibeトピック」を1件返す。
 *
 * 条件:
 *   - status == 'active'
 *   - date が JST の今日 0:00 以上、翌日 0:00 未満
 *   - isAdlOnly !== true（ダミーはADL班に所属していないため汎用トピックに割り当てる）
 *
 * 該当ゼロなら null。複合インデックスを避けるため status のみで取得して
 * 日付フィルタはコード側で行う（[dailyVibeNotification] と同じ方針）。
 */
async function _findTodayActiveVibeTopic(db) {
  const todayStart = jstDayStartFor(new Date());
  const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
  const snap = await db.collection('vibe_topics')
    .where('status', '==', 'active')
    .get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const topicDate = data.date?.toDate?.();
    if (!topicDate) continue;
    if (topicDate < todayStart || topicDate >= todayEnd) continue;
    if (data.isAdlOnly === true) continue;
    return { id: doc.id, ...data };
  }
  return null;
}

exports.dailyDummyUserPosts = onSchedule(
  { schedule: '1 0 * * *', timeZone: 'Asia/Tokyo', timeoutSeconds: 540 },
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

      // ── Apple Music API で日本 TOP チャートを取得 ────────────────
      let tracks = fallbackTracks;
      try {
        const appleMusicToken = process.env.APPLE_MUSIC_DEVELOPER_TOKEN;
        if (!appleMusicToken) throw new Error('APPLE_MUSIC_DEVELOPER_TOKEN未設定');

        const chartRes = await fetch(
          'https://api.music.apple.com/v1/catalog/jp/charts?types=songs&limit=50&l=ja-JP',
          { headers: { 'Authorization': `Bearer ${appleMusicToken}` } }
        );
        if (!chartRes.ok) throw new Error(`HTTP ${chartRes.status}`);
        const chartData = await chartRes.json();

        const songs = chartData.results?.songs?.[0]?.data || [];
        const appleTracks = songs.map(d => {
          const attr = d.attributes;
          const artworkUrl = (attr.artwork?.url || '').replace('{w}', '640').replace('{h}', '640');
          return {
            trackId:       d.id,
            trackName:     attr.name,
            artistName:    attr.artistName,
            albumImageUrl: artworkUrl,
            previewUrl:    attr.previews?.[0]?.url || null,
          };
        });
        if (appleTracks.length === 0) throw new Error('トラック0件');
        tracks = appleTracks;
        console.log(`dailyDummyUserPosts: Apple Music Japan TOP50取得成功 (${tracks.length}件)`);
      } catch (e) {
        console.error('dailyDummyUserPosts: Apple Music TOP50取得失敗、フォールバックを使用:', e.message);
      }

      // ── 今日(JST)のアクティブなVibe topicを取得 ──────────────────────
      // 旧コードは status=='active' で limit(1) するだけだったため、未来日付の
      // active topic が複数残っていると、その中から「適当な1件」が選ばれていた。
      // 結果としてダミー投稿が翌日や数日後のトピックに割り当たり、ユーザー側の
      // 「今日のVibeプレイリスト」には何も表示されない事故が発生していた。
      let activeTopic = null;
      try {
        activeTopic = await _findTodayActiveVibeTopic(db);
        if (activeTopic) {
          console.log(`dailyDummyUserPosts: Vibe topic="${activeTopic.title}"`);
        } else {
          console.warn('dailyDummyUserPosts: 今日(JST)のactive topicが見つかりません');
        }
      } catch (e) {
        console.error('dailyDummyUserPosts: Vibeトピック取得エラー:', e.message);
      }

      // ── ダミー投稿を実際に生成する共通処理 ──────────────────────
      const createdCount = await _createDummyPosts(
        db, userIds, postPhotoUrls, tracks, activeTopic, jstYear, jstMonth, jstDate
      );
      console.log(`dailyDummyUserPosts: ${createdCount}件の投稿を作成しました`);
    } catch (err) {
      console.error('dailyDummyUserPosts error:', err);
    }
  }
);

/**
 * ダミー投稿生成の共通ロジック（スケジュール版・手動版で共有）
 * 1ユーザーあたり POSTS_PER_USER 件の投稿を作成し、作成件数を返す。
 */
const POSTS_PER_USER = 1;

async function _createDummyPosts(db, userIds, postPhotoUrls, tracks, activeTopic, jstYear, jstMonth, jstDate) {
  function randomInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }
  function pickRandom(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
  }

  const shuffledIds = [...userIds].sort(() => Math.random() - 0.5);

  // ── ユーザー情報を100件ずつ並列取得 ──────────────────────────
  const FETCH_CHUNK = 100;
  const userDocs = [];
  for (let c = 0; c < shuffledIds.length; c += FETCH_CHUNK) {
    const chunk = await Promise.all(
      shuffledIds.slice(c, c + FETCH_CHUNK).map(uid => db.collection('users').doc(uid).get())
    );
    userDocs.push(...chunk);
  }

  // ── ユーザー×投稿数分のランダムデータを事前計算 ──────────────
  // 表面はカードコードが track.albumImageUrl を使う。裏面は photoUrl を使うため
  // photoUrl には事前用意の Storage 写真を割り当てる。
  const allSelections = shuffledIds.map(() =>
    Array.from({ length: POSTS_PER_USER }, () => ({
      photoUrl:    pickRandom(postPhotoUrls),
      track:       pickRandom(tracks),
      layoutIndex: pickRandom([1, 2, 3]),
    }))
  );

  // ── URLの重複を排除してアルバムアートから色を効率よく抽出 ─────
  // Apple Music TOP50 は最大50曲なので最大50回のHTTPリクエストに収まる
  const uniqueUrls = [...new Set(allSelections.flat().map(s => s.track.albumImageUrl))];
  const urlToTheme = {};
  const THEME_CHUNK = 50;
  for (let c = 0; c < uniqueUrls.length; c += THEME_CHUNK) {
    const chunkUrls = uniqueUrls.slice(c, c + THEME_CHUNK);
    const themes = await Promise.all(chunkUrls.map(url => _extractThemeFromAlbumArt(url)));
    chunkUrls.forEach((url, i) => { urlToTheme[url] = themes[i]; });
  }

  // ── 各ユーザーの投稿をバッチ作成（500件上限を考慮して分割）───
  // 1ユーザーにつき post.set + user.update = 2ops → 400ops/batch = 200人/batch
  const BATCH_THRESHOLD = 400;
  const batchPromises = [];
  let batch = db.batch();
  let batchOps = 0;
  let createdCount = 0;

  function flushIfNeeded() {
    if (batchOps >= BATCH_THRESHOLD) {
      batchPromises.push(batch.commit());
      batch = db.batch();
      batchOps = 0;
    }
  }

  for (let i = 0; i < shuffledIds.length; i++) {
    const userId  = shuffledIds[i];
    const userDoc = userDocs[i];
    if (!userDoc.exists) {
      console.log(`  Skip ${userId}: ユーザードキュメントなし`);
      continue;
    }

    const userData = userDoc.data();

    for (let p = 0; p < POSTS_PER_USER; p++) {
      const { photoUrl, track, layoutIndex } = allSelections[i][p];
      const theme   = urlToTheme[track.albumImageUrl] || _DUMMY_DEFAULT_THEME;
      const cardPos = _getCenteredCardPos(layoutIndex);

      // createdAt は「今この瞬間から過去 0〜23 時間のランダム」にする。
      // 旧コードは Date.UTC(jstY,jstM,jstD, randHour, ...) で「今日の8〜22時JST」を
      // 計算していたため、関数実行時刻（≈ 0:01 JST）から見ると未来の時刻が
      // 大量に生まれ、Flutter 側の time-ago 表示が「たった今」固定になっていた。
      const offsetMinutes = randomInt(0, 23 * 60);
      const postTimeUtc = new Date(Date.now() - offsetMinutes * 60 * 1000);
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
        adlTeamId:        userData.adlTeamId || null,
        isDummyPost:      true,
        createdAt:        postTimestamp,
        updatedAt:        postTimestamp,
      });
      batchOps++;
      createdCount++;
      flushIfNeeded();
    }

    batch.update(db.collection('users').doc(userId), {
      postsCount: admin.firestore.FieldValue.increment(POSTS_PER_USER),
      updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
    });
    batchOps++;
    flushIfNeeded();
  }

  if (batchOps > 0) batchPromises.push(batch.commit());
  await Promise.all(batchPromises);
  console.log(`_createDummyPosts: ${createdCount}件を${batchPromises.length}バッチで作成`);
  return createdCount;
}

/**
 * ダミー投稿を手動で今すぐ生成（管理者専用・日付ロックなし）
 * Firebase Console から呼び出し可能。テスト・デバッグ用。
 */
exports.manualDummyUserPosts = onCall(
  { timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }

    const now = new Date();
    const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
    const jstYear  = jstNow.getUTCFullYear();
    const jstMonth = jstNow.getUTCMonth();
    const jstDate  = jstNow.getUTCDate();

    const [usersSnap, photosSnap, tracksSnap] = await Promise.all([
      db.doc('dummy_config/users').get(),
      db.doc('dummy_config/photos').get(),
      db.doc('dummy_config/tracks').get(),
    ]);
    if (!usersSnap.exists || !photosSnap.exists || !tracksSnap.exists) {
      throw new HttpsError('not-found', 'dummy_config が未作成です');
    }

    const userIds       = usersSnap.data().userIds || [];
    const postPhotoUrls = photosSnap.data().postPhotoUrls || [];
    const tracks        = tracksSnap.data().list || [];

    // 今日(JST) のアクティブな汎用 Vibe トピックを取得（[dailyDummyUserPosts] と同じロジック）
    const activeTopic = await _findTodayActiveVibeTopic(db);

    const createdCount = await _createDummyPosts(
      db, userIds, postPhotoUrls, tracks, activeTopic, jstYear, jstMonth, jstDate
    );
    console.log(`manualDummyUserPosts: ${createdCount}件作成`);
    return { success: true, createdCount };
  }
);

// ── ADLプレテスト用: 大量ダミーユーザー作成・クリーンアップ ─────────────────────

const _ADL_TEAM_IDS = [
  'adl_house', 'adl_break', 'adl_girls', 'adl_hiphop', 'adl_new',
  'adl_free', 'adl_lock', 'adl_waack', 'adl_jazz',
];

/**
 * 大量ダミーユーザー作成（ADLプレテスト用・管理者限定）
 *
 * count 件（デフォルト600）のユーザードキュメントを Firestore に作成し、
 * 9チームに均等配分する。dummy_config/users に追加して毎日投稿対象にする。
 * クリーンアップ用に dummy_config/bulkDummyUsers に作成した UID 一覧を記録する。
 */
exports.createBulkDummyUsers = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }

    const totalCount = request.data?.count || 600;

    // プロフィール画像リストを取得（なければ postPhotoUrls で代用）
    const photosSnap = await db.doc('dummy_config/photos').get();
    const profileImageUrls = photosSnap.exists
      ? (photosSnap.data().profileImageUrls || photosSnap.data().postPhotoUrls || [])
      : [];

    const BATCH_THRESHOLD = 450;
    const newUserIds = [];
    let batch = db.batch();
    let batchOps = 0;
    const batchPromises = [];

    function flushIfNeeded() {
      if (batchOps >= BATCH_THRESHOLD) {
        batchPromises.push(batch.commit());
        batch = db.batch();
        batchOps = 0;
      }
    }

    for (let i = 0; i < totalCount; i++) {
      const teamId = _ADL_TEAM_IDS[i % _ADL_TEAM_IDS.length];
      const userNum = String(i + 1).padStart(4, '0');
      const userRef = db.collection('users').doc();
      newUserIds.push(userRef.id);

      const profileImageUrl = profileImageUrls.length > 0
        ? profileImageUrls[i % profileImageUrls.length]
        : null;

      batch.set(userRef, {
        uid:              userRef.id,
        username:         `dummy_${userNum}`,
        name:             `ダミー${userNum}`,
        displayName:      `ダミー${userNum}`,
        bio:              '',
        profileImageUrl,
        savedPosts:       [],
        isADLParticipant: true,
        adlTeamId:        teamId,
        isBulkDummyUser:  true,
        isDummyUser:      true,
        following:        [],
        followers:        [],
        followingCount:   0,
        followerCount:    0,
        postsCount:       0,
        likeCount:        0,
        university:       null,
        isAdmin:          false,
        createdAt:        admin.firestore.FieldValue.serverTimestamp(),
        updatedAt:        admin.firestore.FieldValue.serverTimestamp(),
      });
      batchOps++;
      flushIfNeeded();
    }
    if (batchOps > 0) batchPromises.push(batch.commit());
    await Promise.all(batchPromises);
    console.log(`createBulkDummyUsers: ${totalCount}件のユーザードキュメントを${batchPromises.length}バッチで作成`);

    // dummy_config/users を更新（既存 userIds にマージ）
    const existingUsersSnap = await db.doc('dummy_config/users').get();
    const existingIds = existingUsersSnap.exists ? (existingUsersSnap.data().userIds || []) : [];
    await db.doc('dummy_config/users').set({ userIds: [...existingIds, ...newUserIds] });

    // クリーンアップ用に作成 UID を記録
    await db.doc('dummy_config/bulkDummyUsers').set({
      userIds:   newUserIds,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const dist = _ADL_TEAM_IDS.map((id, idx) => ({
      teamId: id,
      count:  newUserIds.filter((_, i) => i % _ADL_TEAM_IDS.length === idx).length,
    }));
    console.log(`createBulkDummyUsers: 完了 チーム分布=${JSON.stringify(dist)}`);
    return { success: true, createdCount: totalCount, distribution: dist };
  }
);

/**
 * 大量ダミーユーザー一括削除（ADLプレテスト後クリーンアップ・管理者限定）
 *
 * dummy_config/bulkDummyUsers に記録された UID のユーザードキュメントと
 * その投稿をすべて削除し、dummy_config/users から除外する。
 */
exports.cleanupBulkDummyUsers = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }

    const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
    if (!bulkSnap.exists) {
      return { success: true, message: 'dummy_config/bulkDummyUsers が存在しません', deletedUsers: 0, deletedPosts: 0 };
    }
    const bulkUserIds = bulkSnap.data().userIds || [];
    if (bulkUserIds.length === 0) {
      return { success: true, message: '削除対象ユーザーなし', deletedUsers: 0, deletedPosts: 0 };
    }
    console.log(`cleanupBulkDummyUsers: ${bulkUserIds.length}件のユーザーを削除します`);

    // ① 投稿を削除（userId が対象の全投稿を30件チャンクで取得）
    const IN_CHUNK = 30;
    let deletedPosts = 0;
    let postBatch = db.batch();
    let postOps = 0;
    const postBatchPromises = [];

    for (let c = 0; c < bulkUserIds.length; c += IN_CHUNK) {
      const chunk = bulkUserIds.slice(c, c + IN_CHUNK);
      const postsSnap = await db.collection('posts')
        .where('userId', 'in', chunk)
        .get();
      for (const doc of postsSnap.docs) {
        postBatch.delete(doc.ref);
        postOps++;
        deletedPosts++;
        if (postOps >= 450) {
          postBatchPromises.push(postBatch.commit());
          postBatch = db.batch();
          postOps = 0;
        }
      }
    }
    if (postOps > 0) postBatchPromises.push(postBatch.commit());
    await Promise.all(postBatchPromises);
    console.log(`cleanupBulkDummyUsers: ${deletedPosts}件の投稿を削除`);

    // ②-a 削除前に班別の所属頭数を集計（memberCount のドリフト防止）
    const teamMemberDelta = {};
    for (let c = 0; c < bulkUserIds.length; c += IN_CHUNK) {
      const chunk = bulkUserIds.slice(c, c + IN_CHUNK);
      const refs = chunk.map((uid) => db.collection('users').doc(uid));
      const docs = await db.getAll(...refs);
      for (const d of docs) {
        const teamId = d.exists ? d.data().adlTeamId : null;
        if (teamId) {
          teamMemberDelta[teamId] = (teamMemberDelta[teamId] || 0) + 1;
        }
      }
    }

    // ②-b ユーザードキュメントを削除
    let deletedUsers = 0;
    let userBatch = db.batch();
    let userOps = 0;
    const userBatchPromises = [];
    for (const uid of bulkUserIds) {
      userBatch.delete(db.collection('users').doc(uid));
      userOps++;
      deletedUsers++;
      if (userOps >= 450) {
        userBatchPromises.push(userBatch.commit());
        userBatch = db.batch();
        userOps = 0;
      }
    }
    if (userOps > 0) userBatchPromises.push(userBatch.commit());
    await Promise.all(userBatchPromises);
    console.log(`cleanupBulkDummyUsers: ${deletedUsers}件のユーザードキュメントを削除`);

    // ②-c 集計した班ごとの所属数を adl_teams.memberCount から減算
    if (Object.keys(teamMemberDelta).length > 0) {
      const memBatch = db.batch();
      for (const [teamId, delta] of Object.entries(teamMemberDelta)) {
        memBatch.update(db.collection('adl_teams').doc(teamId), {
          memberCount: admin.firestore.FieldValue.increment(-delta),
        });
      }
      await memBatch.commit();
      console.log(`cleanupBulkDummyUsers: memberCount を減算 ${JSON.stringify(teamMemberDelta)}`);
    }

    // ③ dummy_config/users から除外（元の10件だけ残す）
    const existingSnap = await db.doc('dummy_config/users').get();
    const existingIds = existingSnap.exists ? (existingSnap.data().userIds || []) : [];
    const bulkSet = new Set(bulkUserIds);
    const remaining = existingIds.filter(id => !bulkSet.has(id));
    await db.doc('dummy_config/users').set({ userIds: remaining });

    // ④ bulkDummyUsers レコードを削除
    await db.doc('dummy_config/bulkDummyUsers').delete();

    // ⑤ テストフォロー設定があれば連鎖クリーンアップ
    const followResult = await _cleanupTestFollowsInternal(db);

    // ⑥ Auth アカウントがあれば連鎖削除
    const authResult = await _cleanupBulkDummyAuthInternal(db);

    console.log(`cleanupBulkDummyUsers: 完了 (users: ${deletedUsers}, posts: ${deletedPosts}, follows: ${followResult.unfollowed}, auth: ${authResult.deleted})`);
    return {
      success: true,
      deletedUsers,
      deletedPosts,
      followsRemoved: followResult.unfollowed,
      authDeleted: authResult.deleted,
    };
  }
);

// ── 負荷テスト用 Auth アカウント作成・削除 ──────────────────────────────────────

const _LOAD_TEST_PASSWORD = 'LoadTest2026Secure!';
const _LOAD_TEST_EMAIL_DOMAIN = 'loadtest.fifteens.test';

/**
 * 600人のダミーユーザーに Firebase Auth アカウントを付与する。
 * 既存の Firestore UID をそのまま Auth UID として使用するため、
 * dummy_config/bulkDummyUsers が事前に作成されている必要がある。
 *
 * email pattern: lt_<UID先頭12文字>@loadtest.fifteens.test
 * password: 共通 (_LOAD_TEST_PASSWORD)
 *
 * 冪等: 既存アカウントは skipped にカウント
 */
exports.createBulkDummyAuthAccounts = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }

    const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
    if (!bulkSnap.exists) {
      throw new HttpsError('not-found', 'bulkDummyUsers がありません。先に600人作成してください');
    }
    const uids = bulkSnap.data().userIds || [];
    if (uids.length === 0) {
      return { created: 0, skipped: 0, failed: 0, total: 0 };
    }

    let created = 0, skipped = 0, failed = 0;
    const CONCURRENCY = 50; // Auth API rate limit を意識
    const errors = [];

    for (let i = 0; i < uids.length; i += CONCURRENCY) {
      const chunk = uids.slice(i, i + CONCURRENCY);
      const results = await Promise.allSettled(
        chunk.map(uid => {
          const email = `lt_${uid.substring(0, 12).toLowerCase()}@${_LOAD_TEST_EMAIL_DOMAIN}`;
          return admin.auth().createUser({
            uid,
            email,
            password: _LOAD_TEST_PASSWORD,
            emailVerified: false,
          });
        })
      );
      results.forEach((r, idx) => {
        if (r.status === 'fulfilled') {
          created++;
        } else {
          const code = r.reason?.code || '';
          if (code === 'auth/uid-already-exists' || code === 'auth/email-already-exists') {
            skipped++;
          } else {
            failed++;
            if (errors.length < 5) errors.push(`${chunk[idx]}: ${r.reason?.message || code}`);
          }
        }
      });
    }

    await db.doc('dummy_config/bulkDummyAuth').set({
      password: _LOAD_TEST_PASSWORD,
      emailDomain: _LOAD_TEST_EMAIL_DOMAIN,
      emailPrefix: 'lt_',
      emailUidLength: 12,
      uids,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`createBulkDummyAuthAccounts: created=${created}, skipped=${skipped}, failed=${failed}`);
    return { created, skipped, failed, total: uids.length, errors };
  }
);

async function _cleanupBulkDummyAuthInternal(db) {
  const authSnap = await db.doc('dummy_config/bulkDummyAuth').get();
  if (!authSnap.exists) return { deleted: 0, failed: 0 };
  const uids = authSnap.data().uids || [];
  if (uids.length === 0) {
    await db.doc('dummy_config/bulkDummyAuth').delete();
    return { deleted: 0, failed: 0 };
  }

  let deleted = 0, failed = 0;
  // deleteUsers は1呼び出しで最大1000件
  for (let i = 0; i < uids.length; i += 1000) {
    const chunk = uids.slice(i, i + 1000);
    try {
      const result = await admin.auth().deleteUsers(chunk);
      deleted += result.successCount;
      failed += result.failureCount;
    } catch (e) {
      console.warn(`deleteUsers chunk error: ${e.message}`);
      failed += chunk.length;
    }
  }

  await db.doc('dummy_config/bulkDummyAuth').delete();
  return { deleted, failed };
}

exports.cleanupBulkDummyAuthAccounts = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }
    const result = await _cleanupBulkDummyAuthInternal(db);
    console.log(`cleanupBulkDummyAuthAccounts: deleted=${result.deleted}, failed=${result.failed}`);
    return result;
  }
);

// ── 負荷テスト用テストフォロー設定 ───────────────────────────────────────────

/**
 * 指定ユーザー（デフォルト呼び出し元）に全バルクダミーをフォローさせる。
 * 双方向の場合、各ダミーも targetUid をフォローする（投稿時の通知配信テスト用）。
 *
 * 実機での通知暴発検証・タイムライン表示確認に使用。
 *
 * - count: フォロー対象を上限N件に絞る (省略時は全件)
 * - bidirectional: 双方向フォロー (デフォルト true)
 */
exports.setupTestFollows = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }

    const targetUid = request.data?.targetUid || request.auth.uid;
    const bidirectional = request.data?.bidirectional !== false;
    const limitCount = request.data?.count || null;

    const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
    if (!bulkSnap.exists) {
      throw new HttpsError('not-found', 'bulkDummyUsers がありません');
    }
    let dummyUids = bulkSnap.data().userIds || [];
    if (limitCount !== null && limitCount < dummyUids.length) {
      dummyUids = dummyUids.slice(0, limitCount);
    }
    if (dummyUids.length === 0) {
      return { followedCount: 0, message: 'ダミーユーザーがありません' };
    }

    // 既存設定があれば事前に解除（重複防止）
    const existingSnap = await db.doc('dummy_config/testFollows').get();
    if (existingSnap.exists) {
      console.log('setupTestFollows: 既存設定を解除中');
      await _cleanupTestFollowsInternal(db);
    }

    // 1. ターゲットの following にダミーを追加（arrayUnion を200件ずつ）
    const UNION_CHUNK = 200;
    for (let i = 0; i < dummyUids.length; i += UNION_CHUNK) {
      const chunk = dummyUids.slice(i, i + UNION_CHUNK);
      await db.collection('users').doc(targetUid).update({
        following: admin.firestore.FieldValue.arrayUnion(...chunk),
      });
    }
    await db.collection('users').doc(targetUid).update({
      followingCount: admin.firestore.FieldValue.increment(dummyUids.length),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2. 双方向: 各ダミーの followers に targetUid を追加（450件バッチ）
    if (bidirectional) {
      const BATCH = 450;
      const batchPromises = [];
      let batch = db.batch();
      let ops = 0;
      for (const uid of dummyUids) {
        batch.update(db.collection('users').doc(uid), {
          followers: admin.firestore.FieldValue.arrayUnion(targetUid),
          followerCount: admin.firestore.FieldValue.increment(1),
        });
        ops++;
        if (ops >= BATCH) {
          batchPromises.push(batch.commit());
          batch = db.batch();
          ops = 0;
        }
      }
      if (ops > 0) batchPromises.push(batch.commit());
      await Promise.all(batchPromises);
    }

    await db.doc('dummy_config/testFollows').set({
      targetUid,
      dummyUids,
      bidirectional,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`setupTestFollows: ${targetUid} → ${dummyUids.length}人 (bidirectional=${bidirectional})`);
    return { targetUid, followedCount: dummyUids.length, bidirectional };
  }
);

async function _cleanupTestFollowsInternal(db) {
  const setupSnap = await db.doc('dummy_config/testFollows').get();
  if (!setupSnap.exists) return { unfollowed: 0 };
  const { targetUid, dummyUids, bidirectional } = setupSnap.data();
  if (!targetUid || !Array.isArray(dummyUids) || dummyUids.length === 0) {
    await db.doc('dummy_config/testFollows').delete();
    return { unfollowed: 0 };
  }

  // 1. ターゲットの following からダミーを除外
  const REMOVE_CHUNK = 200;
  for (let i = 0; i < dummyUids.length; i += REMOVE_CHUNK) {
    const chunk = dummyUids.slice(i, i + REMOVE_CHUNK);
    try {
      await db.collection('users').doc(targetUid).update({
        following: admin.firestore.FieldValue.arrayRemove(...chunk),
      });
    } catch (e) {
      console.warn(`arrayRemove chunk error: ${e.message}`);
    }
  }
  try {
    await db.collection('users').doc(targetUid).update({
      followingCount: admin.firestore.FieldValue.increment(-dummyUids.length),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.warn(`followingCount update error: ${e.message}`);
  }

  // 2. 双方向だった場合、各ダミーの followers から除外（ダミーが存在する限り）
  if (bidirectional) {
    const BATCH = 450;
    const batchPromises = [];
    let batch = db.batch();
    let ops = 0;
    for (const uid of dummyUids) {
      batch.update(db.collection('users').doc(uid), {
        followers: admin.firestore.FieldValue.arrayRemove(targetUid),
        followerCount: admin.firestore.FieldValue.increment(-1),
      });
      ops++;
      if (ops >= BATCH) {
        batchPromises.push(batch.commit().catch(e => console.warn(`follower removal batch error: ${e.message}`)));
        batch = db.batch();
        ops = 0;
      }
    }
    if (ops > 0) batchPromises.push(batch.commit().catch(e => console.warn(`follower removal batch error: ${e.message}`)));
    await Promise.all(batchPromises);
  }

  await db.doc('dummy_config/testFollows').delete();
  return { unfollowed: dummyUids.length };
}

exports.cleanupTestFollows = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }
    const result = await _cleanupTestFollowsInternal(db);
    console.log(`cleanupTestFollows: ${result.unfollowed}人解除`);
    return result;
  }
);

/**
 * 既存バルクダミーユーザーに不足フィールドを追加する修正用関数
 *
 * createBulkDummyUsers の初期版では uid / name / bio / savedPosts が
 * 欠けており、UserModel.fromFirestore がプロフィール検索に失敗していた。
 * この関数を1回だけ実行すれば既存600人を正しい状態にできる。
 */
exports.fixBulkDummyUserFields = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }

    const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
    if (!bulkSnap.exists) {
      throw new HttpsError('not-found', 'bulkDummyUsers がありません');
    }
    const uids = bulkSnap.data().userIds || [];

    let fixed = 0;
    const BATCH = 400;
    const batchPromises = [];
    let batch = db.batch();
    let ops = 0;

    for (let i = 0; i < uids.length; i++) {
      const uid = uids[i];
      const num = String(i + 1).padStart(4, '0');
      batch.update(db.collection('users').doc(uid), {
        uid:        uid,
        name:       `ダミー${num}`,
        bio:        '',
        savedPosts: [],
        updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
      });
      ops++;
      fixed++;
      if (ops >= BATCH) {
        batchPromises.push(batch.commit());
        batch = db.batch();
        ops = 0;
      }
    }
    if (ops > 0) batchPromises.push(batch.commit());
    await Promise.all(batchPromises);

    console.log(`fixBulkDummyUserFields: ${fixed}件のユーザーを修正`);
    return { fixed };
  }
);

/**
 * 今日の0:01に作成された既存ダミー投稿の isDummyPost フラグを外す。
 * （バルクダミーユーザーの投稿のみ対象）
 * これによりタイムラインにダミー投稿が流れるようになる。
 */
exports.unflagBulkDummyPosts = onCall(
  { timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'ログインが必要です');
    const db = admin.firestore();
    const adminDoc = await db.collection('users').doc(request.auth.uid).get();
    if (!adminDoc.exists || !adminDoc.data().isAdmin) {
      throw new HttpsError('permission-denied', '管理者権限がありません');
    }

    const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
    if (!bulkSnap.exists) {
      throw new HttpsError('not-found', 'bulkDummyUsers がありません');
    }
    const bulkUids = bulkSnap.data().userIds || [];

    let updated = 0;
    const IN_CHUNK = 30;
    const batchPromises = [];
    let batch = db.batch();
    let ops = 0;

    for (let c = 0; c < bulkUids.length; c += IN_CHUNK) {
      const chunk = bulkUids.slice(c, c + IN_CHUNK);
      const snap = await db.collection('posts')
        .where('userId', 'in', chunk)
        .where('isDummyPost', '==', true)
        .get();
      for (const doc of snap.docs) {
        batch.update(doc.ref, { isDummyPost: false });
        ops++;
        updated++;
        if (ops >= 400) {
          batchPromises.push(batch.commit());
          batch = db.batch();
          ops = 0;
        }
      }
    }
    if (ops > 0) batchPromises.push(batch.commit());
    await Promise.all(batchPromises);

    console.log(`unflagBulkDummyPosts: ${updated}件の投稿のフラグを解除`);
    return { updated };
  }
);
