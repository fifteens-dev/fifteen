const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  const usersSnap = await db.doc('dummy_config/users').get();
  const dummyUids = usersSnap.data().userIds || [];

  console.log('=== 10ダミーユーザーの postsCount ===');
  let dummyWithPosts = 0;
  for (const uid of dummyUids) {
    const u = await db.collection('users').doc(uid).get();
    const data = u.data() || {};
    const pc = data.postsCount ?? 0;
    console.log(`  ${uid} (${data.username || '?'}): postsCount=${pc}`);
    if (pc > 0) dummyWithPosts++;
  }
  console.log(`\n→ postsCount > 0 のダミー: ${dummyWithPosts}/${dummyUids.length}`);

  // 「投稿者数」と同じクエリ
  const posterSnap = await db.collection('users')
    .where('postsCount', '>', 0)
    .count()
    .get();
  console.log(`\n=== 管理者パネル「投稿者数」(users.postsCount > 0) ===`);
  console.log(`  合計: ${posterSnap.data().count}`);
  console.log(`  うちダミー: ${dummyWithPosts}`);
  console.log(`  人間相当: ${posterSnap.data().count - dummyWithPosts}`);

  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
