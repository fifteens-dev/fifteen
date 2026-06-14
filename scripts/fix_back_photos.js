/**
 * バルクダミー投稿の裏面写真 (photoUrl) を本物のFirebase Storage写真に置き換えるスクリプト
 *
 * 実行: cd scripts && node fix_back_photos.js
 *
 * 背景:
 * 前回 fix_dummy_photos.js で photoUrl をアルバムアートに上書きしたため、
 * カード裏面までアルバムアートになってしまっていた。
 *
 * 投稿カードは:
 *   表面 = post.track.albumImageUrl (アルバムアート)
 *   裏面 = post.photoUrl (事前用意の写真)
 *
 * このスクリプトは photoUrl を Firebase Storage の本物写真 (Picsum 以外) からランダム選出して上書きする。
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

function isStoragePhoto(url) {
  return typeof url === 'string'
    && url.startsWith('http')
    && !url.includes('picsum.photos');
}
function pickRandom(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

async function main() {
  console.log('=== バルクダミー投稿の裏面写真を本物のStorage写真に修正 ===\n');

  // ── Step 1: postPhotoUrls から本物だけ抽出 ──────────────────────
  const photosSnap = await db.doc('dummy_config/photos').get();
  const allPhotos = photosSnap.data()?.postPhotoUrls || [];
  const storagePhotos = allPhotos.filter(isStoragePhoto);
  console.log(`postPhotoUrls: 全${allPhotos.length}件 → Storage写真${storagePhotos.length}件 (Picsum除外${allPhotos.length - storagePhotos.length}件)`);

  if (storagePhotos.length === 0) {
    console.error('❌ Storage写真が0件。dummy_config/photos.postPhotoUrls にFirebase Storage URLがありません');
    process.exit(1);
  }

  // ── Step 2: dummy_config/photos.postPhotoUrls をクリーンアップ ──
  // 将来作成される投稿も本物写真のみを使うように
  await db.doc('dummy_config/photos').set({
    postPhotoUrls: storagePhotos,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log(`  → dummy_config/photos.postPhotoUrls を ${storagePhotos.length} 件に再構築`);

  // ── Step 3: バルクダミー投稿を取得 ───────────────────────────────
  const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
  if (!bulkSnap.exists) {
    console.error('❌ bulkDummyUsers がありません');
    process.exit(1);
  }
  const bulkUids = bulkSnap.data().userIds || [];

  console.log('\n投稿を集計中...');
  const allPosts = [];
  for (let c = 0; c < bulkUids.length; c += 30) {
    const chunk = bulkUids.slice(c, c + 30);
    const snap = await db.collection('posts').where('userId', 'in', chunk).get();
    for (const doc of snap.docs) {
      allPosts.push({ ref: doc.ref, data: doc.data() });
    }
  }
  console.log(`バルクダミー投稿: ${allPosts.length}件`);
  if (allPosts.length === 0) {
    console.log('対象なし');
    process.exit(0);
  }

  // ── Step 4: photoUrl を本物のStorage写真にランダム上書き ────────
  console.log('\n各投稿のphotoUrlを本物写真にランダム上書き中...');
  const BATCH = 400;
  const batchPromises = [];
  let batch = db.batch();
  let ops = 0;
  let updated = 0;

  for (const { ref } of allPosts) {
    batch.update(ref, { photoUrl: pickRandom(storagePhotos) });
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

  console.log(`\n✅ ${updated}件の photoUrl を Storage 写真に置き換え`);
  console.log('   実機で投稿カードをタップして裏返すと、写真が表示されます（アルバムアートではなく）');
  process.exit(0);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
