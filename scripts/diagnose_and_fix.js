/**
 * バルクダミー投稿の診断＆修正スクリプト
 *
 * 実行: cd scripts && node diagnose_and_fix.js
 *
 * 処理:
 * 1. バルクダミーユーザーの投稿数を診断
 * 2. アクティブVibeトピックを取得
 * 3. バルクダミー投稿に isVibe / vibeTopicId / vibeTopicTitle / vibeDate を補完
 *    → Vibeプレイリストに表示されるようになる
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  console.log('=== 診断・修正スクリプト ===\n');

  // ── Step 1: バルクダミーUIDを取得 ─────────────────────────────────
  const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
  if (!bulkSnap.exists) {
    console.error('❌ bulkDummyUsers がありません');
    process.exit(1);
  }
  const bulkUids = bulkSnap.data().userIds || [];
  console.log(`バルクダミー: ${bulkUids.length}人`);

  // ── Step 2: 投稿数の診断（先頭30人サンプル） ─────────────────────
  console.log('\n【診断】先頭30人の投稿数:');
  const sampleUids = bulkUids.slice(0, 30);
  const sampleSnap = await db.collection('posts').where('userId', 'in', sampleUids).get();
  const postsByUser = {};
  for (const doc of sampleSnap.docs) {
    const uid = doc.data().userId;
    postsByUser[uid] = (postsByUser[uid] || 0) + 1;
  }
  const sampleWithPosts = Object.keys(postsByUser).length;
  console.log(`  → ${sampleWithPosts}/30 人が投稿あり (合計 ${sampleSnap.size} 件)`);
  if (sampleWithPosts === 0) {
    console.log('  ⚠️ サンプル30人に投稿がありません。0:01の日次バッチが走っていない可能性');
  }

  // ── Step 3: 全バルクダミーの投稿を集計 ──────────────────────────
  console.log('\n【診断】全バルクダミーの投稿を集計中...');
  let totalPosts = 0;
  let postsWithIsVibe = 0;
  let postsWithCorrectTopic = 0;

  // アクティブトピックを先に取得
  const topicSnap = await db.collection('vibe_topics').where('status', '==', 'active').limit(1).get();
  let activeTopic = null;
  if (!topicSnap.empty) {
    const doc = topicSnap.docs[0];
    activeTopic = { id: doc.id, ...doc.data() };
    console.log(`  アクティブVibeトピック: "${activeTopic.title}" (${activeTopic.id})`);
  } else {
    console.log('  ⚠️ アクティブVibeトピックがありません');
  }

  const allBulkPostIds = [];
  for (let c = 0; c < bulkUids.length; c += 30) {
    const chunk = bulkUids.slice(c, c + 30);
    const snap = await db.collection('posts').where('userId', 'in', chunk).get();
    for (const doc of snap.docs) {
      const data = doc.data();
      totalPosts++;
      if (data.isVibe === true) postsWithIsVibe++;
      if (activeTopic && data.vibeTopicId === activeTopic.id) postsWithCorrectTopic++;
      allBulkPostIds.push({ ref: doc.ref, data });
    }
  }
  console.log(`  → バルクダミー総投稿数: ${totalPosts}`);
  console.log(`  → isVibe=true: ${postsWithIsVibe}`);
  console.log(`  → 今日のトピックに紐付き: ${postsWithCorrectTopic}`);

  if (totalPosts === 0) {
    console.log('\n⚠️ 投稿が0件です。日次バッチ未実行のため修正対象なし。');
    console.log('   負荷テスト投稿が完了するまで待ち、再実行してください。');
    process.exit(0);
  }

  // ── Step 4: Vibe情報を補完 ──────────────────────────────────────
  if (!activeTopic) {
    console.log('\n⚠️ アクティブトピックがないためVibe情報を補完できません');
    process.exit(0);
  }

  console.log('\n【修正】Vibe情報を補完中...');
  const BATCH = 400;
  const batchPromises = [];
  let batch = db.batch();
  let ops = 0;
  let updated = 0;

  for (const { ref, data } of allBulkPostIds) {
    // 既に正しく設定されているものはスキップ
    if (data.isVibe === true && data.vibeTopicId === activeTopic.id) continue;

    batch.update(ref, {
      isVibe:         true,
      vibeTopicId:    activeTopic.id,
      vibeTopicTitle: activeTopic.title,
      vibeDate:       activeTopic.date,
    });
    ops++;
    updated++;
    if (ops >= BATCH) {
      batchPromises.push(batch.commit());
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) batchPromises.push(batch.commit());
  await Promise.all(batchPromises);
  console.log(`  → ${updated}件の投稿を更新しました`);

  console.log('\n✅ 完了');
  console.log('実機アプリで:');
  console.log('  1. Vibeページ → プレイリストにダミー投稿が表示される');
  console.log('  2. ダミーユーザーのプロフィール → 自身の投稿が表示される');
  process.exit(0);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
