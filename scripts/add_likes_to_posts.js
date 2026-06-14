/**
 * 全バルクダミー投稿に50いいねを付与するスクリプト
 *
 * 実行: cd scripts && node add_likes_to_posts.js
 *
 * 処理:
 * 1. dummy_config/bulkDummyUsers の UID 一覧を取得
 * 2. 全バルクダミーの投稿を取得
 * 3. 各投稿に対し、自分以外のバルクダミーから50人をランダム選出
 * 4. likeCount=50, likedUserIds=[50人] を設定（上書き）
 *
 * adlLikeAggregation がトリガーされ各班の likeCount も自動更新される。
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const LIKES_PER_POST = 50;

function shuffleAndPick(arr, n) {
  const copy = [...arr];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy.slice(0, n);
}

async function main() {
  console.log('=== 全投稿に50いいね付与 ===\n');

  // ── Step 1: バルクダミーUIDを取得 ─────────────────────────────────
  const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
  if (!bulkSnap.exists) {
    console.error('❌ bulkDummyUsers がありません');
    process.exit(1);
  }
  const bulkUids = bulkSnap.data().userIds || [];
  console.log(`バルクダミー: ${bulkUids.length}人`);

  if (bulkUids.length < LIKES_PER_POST + 1) {
    console.error(`❌ いいね用ユーザーが不足: 最低${LIKES_PER_POST + 1}人必要`);
    process.exit(1);
  }

  // ── Step 2: バルクダミーの投稿を全取得 ──────────────────────────
  console.log('\n投稿を集計中...');
  const allPosts = [];
  for (let c = 0; c < bulkUids.length; c += 30) {
    const chunk = bulkUids.slice(c, c + 30);
    const snap = await db.collection('posts').where('userId', 'in', chunk).get();
    for (const doc of snap.docs) {
      allPosts.push({ ref: doc.ref, userId: doc.data().userId });
    }
  }
  console.log(`バルクダミー投稿: ${allPosts.length}件`);
  if (allPosts.length === 0) {
    console.error('❌ 対象投稿がありません');
    process.exit(0);
  }

  // ── Step 3: 各投稿に50いいねを付与 ──────────────────────────────
  console.log(`\n各投稿に${LIKES_PER_POST}いいねを付与中...`);
  const BATCH = 400;
  const batchPromises = [];
  let batch = db.batch();
  let ops = 0;
  let updated = 0;
  const start = Date.now();

  for (const { ref, userId } of allPosts) {
    // 投稿者本人を除外して50人をランダム選出
    const candidates = bulkUids.filter(uid => uid !== userId);
    const likers = shuffleAndPick(candidates, LIKES_PER_POST);

    batch.update(ref, {
      likeCount:    LIKES_PER_POST,
      likedUserIds: likers,
    });
    ops++;
    updated++;

    if (ops >= BATCH) {
      batchPromises.push(batch.commit());
      batch = db.batch();
      ops = 0;
      process.stdout.write(`\r  進行: ${updated}/${allPosts.length}`);
    }
  }
  if (ops > 0) batchPromises.push(batch.commit());
  await Promise.all(batchPromises);
  process.stdout.write(`\r  進行: ${updated}/${allPosts.length}\n`);

  const elapsed = Math.round((Date.now() - start) / 1000);
  console.log(`\n✅ ${updated}件の投稿に${LIKES_PER_POST}いいねずつ付与 (${elapsed}秒)`);
  console.log('   adlLikeAggregation トリガーが順次実行され各班の集計も更新されます');
  console.log('   管理パネル「再集計」で即座に正しい値に揃えることも可能');
  process.exit(0);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
