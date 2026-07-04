/**
 * 10人ダミーユーザーの現状診断
 *
 * 実行: cd scripts && node diagnose_10dummies.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

function jstStr(date) {
  if (!date) return 'null';
  const ts = date.toDate ? date.toDate() : date;
  return new Date(ts.getTime() + 9 * 3600 * 1000).toISOString().replace('Z', '+09:00');
}

async function main() {
  console.log('=== 10人ダミー診断 ===\n');

  // ── Step 1: dummy_config/users を取得 ─────────────────────────────
  const usersSnap = await db.doc('dummy_config/users').get();
  if (!usersSnap.exists) {
    console.error('❌ dummy_config/users が存在しません');
    process.exit(1);
  }
  const dummyUids = usersSnap.data().userIds || [];
  console.log(`dummy_config/users.userIds: ${dummyUids.length}人`);
  dummyUids.forEach((u, i) => console.log(`  [${i}] ${u}`));

  // bulkDummyUsers の有無もチェック
  const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
  if (bulkSnap.exists) {
    const bulkIds = bulkSnap.data().userIds || [];
    console.log(`\n参考: dummy_config/bulkDummyUsers: ${bulkIds.length}人 (存在）`);
  } else {
    console.log(`\n参考: dummy_config/bulkDummyUsers: なし（クリーンアップ済み）`);
  }

  // ── Step 2: 現在のアクティブ Vibe トピック ────────────────────────
  const topicSnap = await db
    .collection('vibe_topics')
    .where('status', '==', 'active')
    .get();
  console.log(`\n=== Active Vibeトピック: ${topicSnap.size}件 ===`);
  for (const doc of topicSnap.docs) {
    const d = doc.data();
    console.log(`  topicId: ${doc.id}`);
    console.log(`    title: ${d.title}`);
    console.log(`    date(JST): ${jstStr(d.date)}`);
    console.log(`    status: ${d.status}`);
    console.log(`    isAdlOnly: ${d.isAdlOnly === true}`);
    console.log(`    postCount: ${d.postCount || 0}`);
  }
  const activeTopicIds = topicSnap.docs.map(d => d.id);

  // ── Step 3: 10ダミーの各ユーザーの直近投稿を見る ──────────────────
  console.log('\n=== 各ダミーユーザーの直近投稿 ===');
  for (const uid of dummyUids) {
    const userSnap = await db.collection('users').doc(uid).get();
    const username = userSnap.data()?.username || '(no user doc)';
    console.log(`\nuser: ${username} (${uid})`);

    const postsSnap = await db
      .collection('posts')
      .where('userId', '==', uid)
      .orderBy('createdAt', 'desc')
      .limit(3)
      .get();
    console.log(`  投稿数(直近3件): ${postsSnap.size}`);
    for (const doc of postsSnap.docs) {
      const p = doc.data();
      const matchActiveTopic = activeTopicIds.includes(p.vibeTopicId);
      console.log(`  - postId: ${doc.id}`);
      console.log(`    createdAt(JST): ${jstStr(p.createdAt)}`);
      console.log(`    isVibe: ${p.isVibe}`);
      console.log(`    vibeTopicId: ${p.vibeTopicId || 'null'} ${matchActiveTopic ? '✓match active' : '✗no match'}`);
      console.log(`    vibeTopicTitle: ${p.vibeTopicTitle || 'null'}`);
      console.log(`    vibeDate(JST): ${jstStr(p.vibeDate)}`);
      console.log(`    audience: ${p.audience ?? '(field missing → public扱い)'}`);
      console.log(`    isDummyPost: ${p.isDummyPost === true}`);
    }
  }

  // ── Step 4: アクティブトピックでの投稿数集計（実数）────────────────
  console.log('\n=== アクティブトピック別 実投稿数（dummyフラグ問わず） ===');
  for (const topicId of activeTopicIds) {
    const snap = await db
      .collection('posts')
      .where('isVibe', '==', true)
      .where('vibeTopicId', '==', topicId)
      .get();
    let publicCount = 0, followersCount = 0, dummyCount = 0;
    for (const doc of snap.docs) {
      const d = doc.data();
      if (d.audience === 'followers') followersCount++; else publicCount++;
      if (d.isDummyPost === true) dummyCount++;
    }
    console.log(`  topic ${topicId}: total=${snap.size} (public=${publicCount}, followers=${followersCount}, dummy=${dummyCount})`);
  }

  process.exit(0);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
