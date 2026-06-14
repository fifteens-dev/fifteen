/**
 * バルクダミーユーザーの修正スクリプト（緊急対応用）
 *
 * 実行: cd scripts && node fix_bulk_dummies.js
 *
 * 処理:
 * 1. 既存600ユーザーに uid / name / bio / savedPosts を補完
 * 2. 既存ダミー投稿の isDummyPost フラグを外してタイムライン表示可能に
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function fixUserFields() {
  console.log('=== Step 1: ユーザードキュメント修正 ===');
  const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
  if (!bulkSnap.exists) {
    console.error('bulkDummyUsers がありません');
    return;
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
  console.log(`  → ${fixed}件のユーザーに uid / name / bio / savedPosts を追加`);
}

async function unflagDummyPosts() {
  console.log('\n=== Step 2: 既存ダミー投稿のフラグ解除 ===');
  const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
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
  console.log(`  → ${updated}件の投稿の isDummyPost フラグを解除`);
}

async function main() {
  await fixUserFields();
  await unflagDummyPosts();
  console.log('\n✅ 完了');
  console.log('実機アプリでタイムラインを更新（プルダウン）すると投稿が流れるはずです');
  process.exit(0);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
