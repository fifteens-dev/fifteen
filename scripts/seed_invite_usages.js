/**
 * ダミーユーザーが招待コードを使った判定にするスクリプト（個人賞テスト用）
 *
 * 実行: cd scripts && node seed_invite_usages.js
 *
 * 処理:
 * 1. invite_codes/UHBV4SQ と invite_codes/2SRD5NR から ownerUid を取得
 * 2. バルクダミーUIDを先頭250人 (UHBV4SQ用) と次350人 (2SRD5NR用) に分割
 * 3. invite_usages に各ペアの利用レコードを作成 (isLoadTestSeed: true でマーク)
 * 4. invite_codes/{code}.usedCount をインクリメント
 *
 * クリーンアップ: --cleanup フラグで isLoadTestSeed: true のレコードを全削除
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const ASSIGNMENTS = [
  { code: 'UHBV4SQ', count: 250 },
  { code: '2SRD5NR', count: 350 },
];

async function cleanup() {
  console.log('=== クリーンアップ: isLoadTestSeed の invite_usages を削除 ===');
  const snap = await db.collection('invite_usages')
    .where('isLoadTestSeed', '==', true)
    .get();
  if (snap.empty) {
    console.log('対象なし');
    process.exit(0);
  }

  // usedCount を減らす集計
  const decrementByCode = {};
  for (const doc of snap.docs) {
    const code = doc.data().code;
    if (code) decrementByCode[code] = (decrementByCode[code] || 0) + 1;
  }

  // 削除
  let deleted = 0;
  for (let i = 0; i < snap.docs.length; i += 450) {
    const chunk = snap.docs.slice(i, i + 450);
    const batch = db.batch();
    chunk.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    deleted += chunk.length;
  }
  console.log(`  → ${deleted}件の invite_usages を削除`);

  // usedCount を減らす
  for (const [code, count] of Object.entries(decrementByCode)) {
    await db.collection('invite_codes').doc(code).update({
      usedCount: admin.firestore.FieldValue.increment(-count),
    });
    console.log(`  → invite_codes/${code}.usedCount -${count}`);
  }
  process.exit(0);
}

async function seed() {
  console.log('=== 招待利用レコード作成（個人賞テスト用） ===\n');

  // ── Step 1: 招待コードの owner を確認 ────────────────────────────
  const ownerUids = {};
  for (const { code } of ASSIGNMENTS) {
    const snap = await db.collection('invite_codes').doc(code).get();
    if (!snap.exists) {
      console.error(`❌ invite_codes/${code} が存在しません`);
      process.exit(1);
    }
    const ownerUid = snap.data()?.ownerUid;
    if (!ownerUid) {
      console.error(`❌ invite_codes/${code} に ownerUid がありません`);
      process.exit(1);
    }
    ownerUids[code] = ownerUid;
    console.log(`  ${code} → owner=${ownerUid.substring(0, 8)}...`);
  }

  // ── Step 2: owner の ADL所属を警告（個人賞は ADL班所属者のみ対象） ───
  console.log('\nオーナーのADL所属チェック:');
  for (const [code, ownerUid] of Object.entries(ownerUids)) {
    const userSnap = await db.collection('users').doc(ownerUid).get();
    const teamId = userSnap.data()?.adlTeamId;
    if (!teamId) {
      console.log(`  ⚠️ ${code} の owner は adlTeamId 未設定 → 個人賞ランキングに表示されません`);
    } else {
      console.log(`  ✅ ${code} の owner は ${teamId} 所属`);
    }
  }

  // ── Step 3: バルクダミーUIDを取得・分割 ─────────────────────────
  const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
  if (!bulkSnap.exists) {
    console.error('❌ bulkDummyUsers がありません');
    process.exit(1);
  }
  const bulkUids = bulkSnap.data().userIds || [];
  const totalNeeded = ASSIGNMENTS.reduce((s, a) => s + a.count, 0);
  if (bulkUids.length < totalNeeded) {
    console.error(`❌ ダミーが不足: ${bulkUids.length}人 / 必要 ${totalNeeded}人`);
    process.exit(1);
  }
  console.log(`\nバルクダミー: ${bulkUids.length}人 (使用: ${totalNeeded}人)`);

  // 分割: 先頭250→UHBV4SQ, 次350→2SRD5NR
  let cursor = 0;
  const assignments = ASSIGNMENTS.map(({ code, count }) => {
    const users = bulkUids.slice(cursor, cursor + count);
    cursor += count;
    return { code, ownerUid: ownerUids[code], users };
  });

  // ── Step 4: invite_usages を作成 ──────────────────────────────
  console.log('\ninvite_usages を作成中...');
  const BATCH = 400;
  let batchPromises = [];
  let batch = db.batch();
  let ops = 0;
  let created = 0;

  for (const { code, ownerUid, users } of assignments) {
    for (const dummyUid of users) {
      const ref = db.collection('invite_usages').doc();
      batch.set(ref, {
        ownerUid,
        usedBy:        dummyUid,
        code,
        usedAt:        admin.firestore.FieldValue.serverTimestamp(),
        isLoadTestSeed: true,
      });
      ops++;
      created++;
      if (ops >= BATCH) {
        batchPromises.push(batch.commit());
        batch = db.batch();
        ops = 0;
      }
    }
  }
  if (ops > 0) batchPromises.push(batch.commit());
  await Promise.all(batchPromises);

  // ── Step 5: invite_codes の usedCount を更新 ───────────────────
  for (const { code, count } of ASSIGNMENTS) {
    await db.collection('invite_codes').doc(code).update({
      usedCount: admin.firestore.FieldValue.increment(count),
    });
  }

  console.log(`\n✅ 完了`);
  console.log(`  invite_usages: ${created}件作成`);
  for (const { code, count } of ASSIGNMENTS) {
    console.log(`    ${code}: ${count}件`);
  }
  console.log('\n💡 個人賞ランキングは管理パネル「個人賞 / 招待人数ランキング」で確認');
  console.log('💡 クリーンアップ: node seed_invite_usages.js --cleanup');
  process.exit(0);
}

async function main() {
  if (process.argv.includes('--cleanup')) {
    await cleanup();
  } else {
    await seed();
  }
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
