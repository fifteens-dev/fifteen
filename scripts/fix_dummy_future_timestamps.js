/**
 * 未来日付になっているダミー投稿の createdAt を「現在から過去 0〜23 時間のランダム」
 * に補正するスクリプト。
 *
 * 実行: cd scripts && node fix_dummy_future_timestamps.js [--dry]
 *
 * 対象:
 *   dummy_config/users.userIds に含まれる UID が投稿者で、createdAt が現在時刻
 *   より「未来」になっている投稿。
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const DRY_RUN = process.argv.includes('--dry');

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

async function main() {
  console.log(`=== ダミー投稿 createdAt 補正${DRY_RUN ? '（DRY-RUN）' : ''} ===\n`);

  const usersSnap = await db.doc('dummy_config/users').get();
  const dummyUids = usersSnap.data()?.userIds || [];
  console.log(`ダミーユーザー: ${dummyUids.length}人`);

  const now = new Date();
  const allFutureDocs = [];
  for (let i = 0; i < dummyUids.length; i += 30) {
    const batch = dummyUids.slice(i, i + 30);
    const snap = await db.collection('posts')
      .where('userId', 'in', batch)
      .get();
    for (const doc of snap.docs) {
      const created = doc.data().createdAt?.toDate?.();
      if (created && created.getTime() > now.getTime()) {
        allFutureDocs.push(doc);
      }
    }
  }
  console.log(`未来日付の投稿: ${allFutureDocs.length}件\n`);

  if (allFutureDocs.length === 0) {
    console.log('✅ 補正対象がありません');
    process.exit(0);
  }

  console.log('=== 補正対象（先頭5件）===');
  for (const doc of allFutureDocs.slice(0, 5)) {
    const d = doc.data();
    const created = d.createdAt.toDate();
    const futureMin = Math.round((created.getTime() - now.getTime()) / 60 / 1000);
    console.log(`  ${doc.id} (${d.username || d.userId})`);
    console.log(`    現在の createdAt: ${new Date(created.getTime() + 9*3600*1000).toISOString()} JST (${futureMin}分後)`);
  }
  if (allFutureDocs.length > 5) console.log(`  ... 他 ${allFutureDocs.length - 5}件\n`);

  if (DRY_RUN) {
    console.log('\n🔍 DRY-RUN なので書き込みはしません');
    process.exit(0);
  }

  console.log('\n書き込み中...');
  let batch = db.batch();
  let ops = 0;
  const promises = [];
  for (const doc of allFutureDocs) {
    const offsetMin = randomInt(0, 23 * 60);
    const newCreatedAt = admin.firestore.Timestamp.fromDate(
      new Date(now.getTime() - offsetMin * 60 * 1000)
    );
    batch.update(doc.ref, { createdAt: newCreatedAt });
    ops++;
    if (ops >= 400) {
      promises.push(batch.commit());
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) promises.push(batch.commit());
  await Promise.all(promises);

  console.log(`✅ ${allFutureDocs.length}件の createdAt を過去のランダム時刻に補正`);
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
