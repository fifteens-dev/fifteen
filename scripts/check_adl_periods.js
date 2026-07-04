/**
 * adl_config/current の現在値を表示するスクリプト
 * 実行: cd scripts && node check_adl_periods.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

function jstStr(ts) {
  if (!ts) return 'なし';
  const d = ts.toDate ? ts.toDate() : ts;
  const jst = new Date(d.getTime() + 9 * 3600 * 1000);
  return jst.toISOString().replace('Z', '') + ' JST';
}

async function main() {
  const snap = await db.doc('adl_config/current').get();
  if (!snap.exists) {
    console.error('❌ adl_config/current が存在しません');
    process.exit(1);
  }
  const d = snap.data();

  console.log('=== adl_config/current ===\n');
  console.log(`isActive (ADLモード): ${d.isActive === true ? 'ON' : 'OFF'}`);
  console.log(`resultFinalized:       ${d.resultFinalized === true ? 'true（最終結果モード）' : 'false'}`);
  if (d.resultFinalizedAt) {
    console.log(`resultFinalizedAt:     ${jstStr(d.resultFinalizedAt)}`);
  }
  console.log();
  console.log('── チーム賞期間 ──');
  console.log(`  teamRankingStart:  ${jstStr(d.teamRankingStart)}`);
  console.log(`  teamRankingEnd:    ${jstStr(d.teamRankingEnd)}`);
  console.log();
  console.log('── 個人賞期間 ──');
  console.log(`  inviteRankingStart: ${jstStr(d.inviteRankingStart)}`);
  console.log(`  inviteRankingEnd:   ${jstStr(d.inviteRankingEnd)}`);
  console.log();

  // 期間内の invite_usages カウント（参考表示）
  const from = d.inviteRankingStart?.toDate?.();
  const to = d.inviteRankingEnd?.toDate?.();
  if (from && to) {
    const snap2 = await db.collection('invite_usages')
      .where('usedAt', '>=', admin.firestore.Timestamp.fromDate(from))
      .where('usedAt', '<', admin.firestore.Timestamp.fromDate(to))
      .count()
      .get();
    console.log(`── 期間内 invite_usages 件数 ──`);
    console.log(`  ${snap2.data().count}件\n`);

    // 全期間との比較
    const allSnap = await db.collection('invite_usages').count().get();
    console.log(`参考: invite_usages 全期間累計 = ${allSnap.data().count}件`);
  } else {
    console.log('⚠️  inviteRankingStart/End のどちらかが未設定。全期間累計が表示されてしまいます。');
  }

  process.exit(0);
}
main().catch(e => { console.error('Error:', e); process.exit(1); });
