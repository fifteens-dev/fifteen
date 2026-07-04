const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  const usersSnap = await db.doc('dummy_config/users').get();
  const dummyUids = usersSnap.data()?.userIds || [];
  console.log(`ダミーユーザー: ${dummyUids.length}人`);

  const now = new Date();
  console.log(`現在: ${new Date(now.getTime() + 9 * 3600 * 1000).toISOString()} JST\n`);

  for (const uid of dummyUids.slice(0, 3)) {
    const snap = await db.collection('posts')
      .where('userId', '==', uid)
      .orderBy('createdAt', 'desc')
      .limit(3)
      .get();
    console.log(`=== ${uid} ===`);
    for (const doc of snap.docs) {
      const d = doc.data();
      const created = d.createdAt?.toDate?.();
      if (!created) {
        console.log(`  postId: ${doc.id} createdAt: NULL/INVALID (${typeof d.createdAt})`);
        continue;
      }
      const diffMs = now.getTime() - created.getTime();
      const diffH = Math.floor(diffMs / 3600 / 1000);
      const diffMin = Math.floor(diffMs / 60 / 1000);
      console.log(`  postId: ${doc.id}`);
      console.log(`    createdAt(JST): ${new Date(created.getTime() + 9*3600*1000).toISOString()}`);
      console.log(`    diff: ${diffH}時間 (${diffMin}分)`);
    }
    console.log();
  }
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
