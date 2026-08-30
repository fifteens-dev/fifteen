/**
 * WATERFALLS: 孤児メンバーシップの検出 / 削除
 *
 * users/{uid} が存在しないのに milfolha_memberships/{uid} が残っていると、
 * メンバー一覧には出ないのに登録 +1pt だけランキングに載る
 * （＝「メンバー0人なのに1pt」）。それを検出して掃除する。
 *
 * 実行:
 *   cd scripts && node cleanup_orphan_milfolha_memberships.js          # 確認のみ（何も消さない）
 *   cd scripts && node cleanup_orphan_milfolha_memberships.js --apply  # 実際に削除
 *
 * --apply 時は milfolha_teams/{teamId}.memberCount も実メンバー数に貼り直す。
 */
const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const apply = process.argv.includes('--apply');

(async () => {
  const snap = await db.collection('milfolha_memberships').get();
  console.log(`milfolha_memberships: ${snap.size} 件`);

  const orphans = [];
  const aliveByTeam = {};

  for (const d of snap.docs) {
    const teamId = d.data().teamId;
    const u = await db.collection('users').doc(d.id).get();
    if (u.exists) {
      aliveByTeam[teamId] = (aliveByTeam[teamId] || 0) + 1;
    } else {
      orphans.push({ uid: d.id, teamId });
    }
  }

  console.log('\n== users ドキュメントが存在しない孤児メンバーシップ ==');
  if (orphans.length === 0) {
    console.log('  なし');
  } else {
    orphans.forEach((o) => console.log(`  ${o.uid}  (teamId=${o.teamId})`));
  }

  console.log('\n== 実在メンバー数 ==');
  console.log(aliveByTeam);

  if (!apply) {
    console.log('\n確認のみです。削除するには --apply を付けて再実行してください。');
    process.exit(0);
  }

  for (const o of orphans) {
    await db.collection('milfolha_memberships').doc(o.uid).delete();
    console.log(`削除: milfolha_memberships/${o.uid}`);
  }

  const teams = await db.collection('milfolha_teams').get();
  for (const t of teams.docs) {
    const actual = aliveByTeam[t.id] || 0;
    if (t.data().memberCount !== actual) {
      await t.ref.set({ memberCount: actual }, { merge: true });
      console.log(`memberCount 修正: ${t.id}  ${t.data().memberCount} -> ${actual}`);
    }
  }

  console.log('\n完了しました。');
  process.exit(0);
})();
