const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  const usersSnap = await db.doc('dummy_config/users').get();
  const dummyUids = usersSnap.data().userIds || [];

  // 1) 各ダミーユーザーの adlTeamId
  console.log('=== 10ダミーユーザーの adlTeamId ===');
  let dummiesInAdl = 0;
  for (const uid of dummyUids) {
    const u = await db.collection('users').doc(uid).get();
    const data = u.data() || {};
    const teamId = data.adlTeamId;
    console.log(`  ${uid} (${data.username || '?'}): adlTeamId=${teamId || 'null'}`);
    if (teamId) dummiesInAdl++;
  }
  console.log(`\n→ 班所属ダミー: ${dummiesInAdl}/${dummyUids.length}`);

  // 2) ダミー投稿で adlTeamId + countsForAdl=true のもの
  console.log('\n=== ダミー投稿(isDummyPost=true) で ADL 集計対象 ===');
  const snap = await db.collection('posts')
    .where('isDummyPost', '==', true)
    .get();
  console.log(`isDummyPost=true 投稿: ${snap.size}件`);
  const byTeam = {};
  let counted = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.adlTeamId && d.countsForAdl === true) {
      byTeam[d.adlTeamId] = (byTeam[d.adlTeamId] || 0) + 1;
      counted++;
    }
  }
  console.log(`うち ADL 集計対象（adlTeamIdあり + countsForAdl=true）: ${counted}件`);
  for (const [teamId, n] of Object.entries(byTeam)) {
    console.log(`  ${teamId}: ${n}件`);
  }

  // 3) 各班の現在の postCount（参考）
  console.log('\n=== adl_teams.postCount（現在の集計値）===');
  const teamsSnap = await db.collection('adl_teams').get();
  for (const doc of teamsSnap.docs) {
    const d = doc.data();
    console.log(`  ${doc.id}: postCount=${d.postCount || 0}, likeCount=${d.likeCount || 0}`);
  }

  // 4) Team ranking window 設定
  console.log('\n=== チーム賞期間（adl_config/current） ===');
  const cfg = await db.doc('adl_config/current').get();
  const c = cfg.data() || {};
  console.log(`  teamRankingStart: ${c.teamRankingStart?.toDate?.()?.toISOString() || 'なし'}`);
  console.log(`  teamRankingEnd:   ${c.teamRankingEnd?.toDate?.()?.toISOString() || 'なし'}`);

  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
