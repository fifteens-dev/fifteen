/**
 * WATERFALLS チームのメンバー表示バグ調査用（読み取りのみ・変更なし）
 *
 * 実行: cd scripts && node diagnose_milfolha_members.js waterfalls_a
 *
 * milfolha_memberships の teamId 一致ドキュメントを列挙し、
 * 各 uid に対応する users/{uid} が実在するか / uid フィールドを持つかを出す。
 * アプリ側 MilfolhaTeamMembersScreen は users ドキュメントが引けない uid を
 * 無言で捨てるため、ここで欠けている uid が「消えているメンバー」。
 */
const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const teamId = process.argv[2] || 'waterfalls_a';

(async () => {
  const snap = await db
    .collection('milfolha_memberships')
    .where('teamId', '==', teamId)
    .get();

  console.log(`\n== milfolha_memberships (teamId == ${teamId}) : ${snap.size} 件 ==`);
  let missing = 0;
  for (const d of snap.docs) {
    const u = await db.collection('users').doc(d.id).get();
    const data = u.exists ? u.data() : null;
    if (!u.exists) missing++;
    console.log(
      [
        `docId=${d.id}`,
        `membership.userId=${d.data().userId}`,
        `users doc=${u.exists ? 'あり' : '★なし★'}`,
        `uidフィールド=${data ? (data.uid || '★空★') : '-'}`,
        `username=${data ? data.username : '-'}`,
        `milfolhaTeamId=${data ? data.milfolhaTeamId : '-'}`,
      ].join(' | '),
    );
  }
  console.log(`\nusers ドキュメントが無い uid: ${missing} 件`);
  console.log(`（アプリの一覧に出るのは ${snap.size - missing} 件、`);
  console.log(` プロフィールの「メンバー」数字は ${snap.size} と表示される）`);

  const t = await db.collection('milfolha_teams').doc(teamId).get();
  console.log(`\nmilfolha_teams/${teamId}.memberCount = ${t.exists ? t.data().memberCount : '(ドキュメント無し)'}`);

  const all = await db.collection('milfolha_memberships').get();
  const byTeam = {};
  all.docs.forEach((d) => {
    const k = d.data().teamId;
    byTeam[k] = (byTeam[k] || 0) + 1;
  });
  console.log('\n全チームの参加者数:', byTeam);
  process.exit(0);
})();
