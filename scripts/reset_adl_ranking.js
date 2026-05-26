/**
 * ADL ランキング状況リセットスクリプト
 *
 * 実行方法:
 *   cd scripts && node reset_adl_ranking.js
 *
 * 処理内容（冪等）:
 * 1. 全ユーザーの adlTeamId/adlTeamName/adlEventId をクリア
 *    followers/following から班UIDを除去
 * 2. adl_memberships コレクションを全削除
 * 3. 9班アカウント（users/{teamId}）の followers/following を空配列に
 * 4. adl_teams/{teamId} の likeCount / memberCount を 0 にリセット
 *
 * 保持されるもの:
 * - 9班自体（adl_teams, users/{teamId} の本体）
 * - 班の name, inviteCode（構造データ）
 * - posts の adlTeamId（履歴は維持）
 */

const admin = require('firebase-admin');

const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const TEAM_IDS = [
  'adl_house', 'adl_break', 'adl_girls', 'adl_hiphop', 'adl_new',
  'adl_free', 'adl_lock', 'adl_waack', 'adl_jazz',
];
const TEAM_ID_SET = new Set(TEAM_IDS);

const BATCH_LIMIT = 400; // Firestoreの500書き込み制限に余裕を持たせる

async function commitBatchIfFull(batchState) {
  if (batchState.count >= BATCH_LIMIT) {
    await batchState.batch.commit();
    batchState.batch = db.batch();
    batchState.count = 0;
  }
}

async function flushBatch(batchState) {
  if (batchState.count > 0) {
    await batchState.batch.commit();
    batchState.batch = db.batch();
    batchState.count = 0;
  }
}

async function reset() {
  console.log('=== ADL ランキング状況リセット開始 ===');

  // ── 1. 全ユーザーの adlTeam* と 相互フォローをクリア ──
  console.log('\n[1/4] ユーザー走査中...');
  const usersSnap = await db.collection('users').get();
  let unregistered = 0;
  const batchState = { batch: db.batch(), count: 0 };

  for (const doc of usersSnap.docs) {
    if (TEAM_ID_SET.has(doc.id)) continue; // 班アカウント自身はスキップ
    const data = doc.data();
    const hasTeamId = !!data.adlTeamId;
    const followers = Array.isArray(data.followers) ? data.followers : [];
    const following = Array.isArray(data.following) ? data.following : [];
    const hasTeamFollow =
      followers.some((u) => TEAM_ID_SET.has(u)) ||
      following.some((u) => TEAM_ID_SET.has(u));

    if (!hasTeamId && !hasTeamFollow) continue;

    batchState.batch.update(doc.ref, {
      adlTeamId: null,
      adlTeamName: null,
      adlEventId: null,
      followers: FieldValue.arrayRemove(TEAM_IDS),
      following: FieldValue.arrayRemove(TEAM_IDS),
      updatedAt: FieldValue.serverTimestamp(),
    });
    batchState.count++;
    unregistered++;
    await commitBatchIfFull(batchState);
  }
  await flushBatch(batchState);
  console.log(`  ✓ ${unregistered} 人のユーザーを班から解除しました`);

  // ── 2. adl_memberships を全削除 ──
  console.log('\n[2/4] adl_memberships 削除中...');
  const memberSnap = await db.collection('adl_memberships').get();
  let deletedMemberships = 0;
  for (const doc of memberSnap.docs) {
    batchState.batch.delete(doc.ref);
    batchState.count++;
    deletedMemberships++;
    await commitBatchIfFull(batchState);
  }
  await flushBatch(batchState);
  console.log(`  ✓ ${deletedMemberships} 件削除しました`);

  // ── 3. 9班アカウントの followers/following をクリア ──
  console.log('\n[3/4] 班アカウントのフォロー関係クリア中...');
  for (const teamId of TEAM_IDS) {
    await db.collection('users').doc(teamId).update({
      followers: [],
      following: [],
      updatedAt: FieldValue.serverTimestamp(),
    });
    console.log(`  ✓ users/${teamId}`);
  }

  // ── 4. adl_teams の likeCount / memberCount をリセット ──
  console.log('\n[4/4] adl_teams 統計値をゼロリセット中...');
  for (const teamId of TEAM_IDS) {
    await db.collection('adl_teams').doc(teamId).update({
      likeCount: 0,
      memberCount: 0,
    });
    console.log(`  ✓ adl_teams/${teamId}`);
  }

  console.log('\n=== リセット完了 ===');
}

reset().then(() => process.exit(0)).catch((err) => {
  console.error('ERROR:', err);
  process.exit(1);
});
