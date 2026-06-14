/**
 * 通知システムの診断スクリプト
 *
 * 実行: cd scripts && node diagnose_notifications.js
 *
 * 通知が来ない原因を切り分けるために以下を確認:
 * 1. dummy_config/testFollows のターゲットUID
 * 2. テストユーザーの user document の状態
 *    - notifPostEnabled
 *    - following 配列の中身
 * 3. ダミー10人のサンプル: followers にテストユーザーが入っているか
 * 4. ダミー10人のサンプル: 投稿が存在するか
 * 5. notifications コレクションでテストユーザー宛の件数
 * 6. user_fcm_tokens にトークンがあるか
 * 7. 最近の onPostCreated 実行ログ確認方法
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  console.log('=== 通知システム診断 ===\n');

  // ── Step 1: テストフォロー設定の確認 ──────────────────────────
  const followsSnap = await db.doc('dummy_config/testFollows').get();
  if (!followsSnap.exists) {
    console.error('❌ dummy_config/testFollows がありません');
    console.error('   管理パネルで「フォロー設定」ボタンを実行してください');
    process.exit(1);
  }
  const { targetUid, dummyUids, bidirectional } = followsSnap.data();
  console.log(`【1】テストフォロー設定:`);
  console.log(`  targetUid: ${targetUid}`);
  console.log(`  dummyUids: ${dummyUids.length}人`);
  console.log(`  bidirectional: ${bidirectional}`);

  // ── Step 2: テストユーザーの状態 ─────────────────────────────
  const targetSnap = await db.collection('users').doc(targetUid).get();
  if (!targetSnap.exists) {
    console.error(`❌ users/${targetUid} がありません`);
    process.exit(1);
  }
  const targetData = targetSnap.data();
  console.log(`\n【2】テストユーザー (${targetUid.substring(0, 8)}...):`);
  console.log(`  username: ${targetData.username}`);
  console.log(`  notifPostEnabled: ${targetData.notifPostEnabled} ${targetData.notifPostEnabled === false ? '❌ 通知無効' : '✅ 通知有効(または未設定→デフォルト有効)'}`);
  console.log(`  following: ${(targetData.following || []).length}人`);
  console.log(`  followers: ${(targetData.followers || []).length}人`);
  const followingSet = new Set(targetData.following || []);
  const dummyInFollowing = dummyUids.filter(uid => followingSet.has(uid)).length;
  console.log(`  → following 内のダミー数: ${dummyInFollowing}/${dummyUids.length}`);

  // ── Step 3: ダミー10人のサンプル：followers確認 ───────────────
  console.log(`\n【3】ダミー10人サンプル: followers にテストユーザーが入っているか`);
  const sample = dummyUids.slice(0, 10);
  let withTarget = 0;
  for (const uid of sample) {
    const snap = await db.collection('users').doc(uid).get();
    if (!snap.exists) {
      console.log(`  ❌ ${uid.substring(0, 8)}... ドキュメントなし`);
      continue;
    }
    const followers = snap.data().followers || [];
    const has = followers.includes(targetUid);
    console.log(`  ${has ? '✅' : '❌'} ${uid.substring(0, 8)}... followers=${followers.length}人 ${has ? '(target含む)' : '(target含まず)'}`);
    if (has) withTarget++;
  }
  console.log(`  → ${withTarget}/10 のダミーが target をフォロワーに含む`);

  // ── Step 4: ダミーの投稿数確認 ──────────────────────────────
  console.log(`\n【4】ダミー10人サンプル: 投稿数`);
  let totalSamplePosts = 0;
  for (const uid of sample) {
    const snap = await db.collection('posts').where('userId', '==', uid).get();
    totalSamplePosts += snap.size;
  }
  console.log(`  → 10人合計 ${totalSamplePosts}件 (平均 ${(totalSamplePosts/10).toFixed(1)}件/人)`);

  // ── Step 5: notifications コレクションのカウント ───────────────
  console.log(`\n【5】notifications コレクション (recipientId=target)`);
  const notifSnap = await db.collection('notifications')
    .where('recipientId', '==', targetUid)
    .get();
  console.log(`  → 合計: ${notifSnap.size}件`);
  const byType = {};
  for (const doc of notifSnap.docs) {
    const t = doc.data().type || 'unknown';
    byType[t] = (byType[t] || 0) + 1;
  }
  for (const [type, count] of Object.entries(byType)) {
    console.log(`    ${type}: ${count}件`);
  }

  // ── Step 6: FCMトークン確認 ──────────────────────────────────
  console.log(`\n【6】FCMトークン`);
  const fcmSnap = await db.collection('user_fcm_tokens').doc(targetUid).get();
  if (!fcmSnap.exists) {
    console.log(`  ❌ user_fcm_tokens/${targetUid} がありません → push通知が届きません`);
  } else {
    const tokens = fcmSnap.data().tokens || [];
    console.log(`  ✅ トークン数: ${tokens.length}件`);
    if (tokens.length === 0) {
      console.log(`  ⚠️ tokens配列が空 → push通知が届きません`);
    }
  }

  // ── 診断結果 ────────────────────────────────────────────────
  console.log(`\n=== 診断結果 ===`);
  if (targetData.notifPostEnabled === false) {
    console.log(`❌ 致命的: notifPostEnabled=false → どんな投稿でも通知が来ません`);
    console.log(`   修正: アプリの設定 → 通知をON にする`);
  } else if (withTarget === 0) {
    console.log(`❌ 致命的: ダミーの followers にテストユーザーが入っていません`);
    console.log(`   修正: setupTestFollows を再実行（管理パネル「フォロー解除」→「フォロー設定」）`);
  } else if (notifSnap.size === 0 && totalSamplePosts > 0) {
    console.log(`❌ 致命的: 投稿はあるが通知レコードが0件 → onPostCreated が動いていない`);
    console.log(`   確認: Firebase Console → Functions → ログ → onPostCreated を絞り込み`);
  } else if (notifSnap.size > 0 && notifSnap.size < totalSamplePosts * 60) {
    console.log(`⚠️ 部分的: 投稿 ${totalSamplePosts}件のサンプル比で通知が少ない (${notifSnap.size}件)`);
    console.log(`   → onPostCreated でエラーが起きている可能性。Functions ログを確認`);
  } else {
    console.log(`✅ Firestore側の通知レコードは作成されている`);
    console.log(`   届かないのは iOS APNs スロットリング・通知許可OFF・トークン無効など端末側要因`);
  }

  console.log(`\n📊 Firebase Console のログ: https://console.firebase.google.com/project/fifteens-39cfe/functions/logs?functionFilter=onPostCreated`);
  process.exit(0);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
