/**
 * 片方向フォローを相互フォローに変換する（「友達＝相互フォロー」への移行）
 *
 * 友達を「相互フォロー」で定義するようにしたため、片方向のまま残っている
 * 関係が友達一覧に出なくなる。それを一括で相互に揃える。
 * 併せて following / followers の不整合（片側にだけ入っている状態）も修復する。
 *
 * 実行:
 *   cd scripts && node mutualize_follows.js           # 確認のみ（何も書かない）
 *   cd scripts && node mutualize_follows.js --apply   # 実際に適用
 *
 * --apply の有無に関わらず、追加する edge を
 *   scripts/mutualize_follows_backup.json
 * に書き出す。ロールバックは以下で行える:
 *   cd scripts && node mutualize_follows.js --rollback
 * （バックアップに記録した edge を arrayRemove で取り除く）
 *
 * 存在しない相手を指す edge には触れない（相互化の対象外）。
 */
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const BACKUP = path.join(__dirname, 'mutualize_follows_backup.json');
const apply = process.argv.includes('--apply');
const rollback = process.argv.includes('--rollback');

/** uid ごとの追加分をまとめて書き込む（300 件ずつのバッチ）。 */
async function writeBatches(addFollowing, addFollowers, op) {
  const touched = new Set([...Object.keys(addFollowing), ...Object.keys(addFollowers)]);
  const uids = [...touched];
  let n = 0;
  for (let i = 0; i < uids.length; i += 300) {
    const batch = db.batch();
    for (const uid of uids.slice(i, i + 300)) {
      const updates = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
      if (addFollowing[uid]?.length) updates.following = op(...addFollowing[uid]);
      if (addFollowers[uid]?.length) updates.followers = op(...addFollowers[uid]);
      batch.set(db.collection('users').doc(uid), updates, { merge: true });
      n++;
    }
    await batch.commit();
  }
  return n;
}

async function doRollback() {
  if (!fs.existsSync(BACKUP)) {
    console.error(`バックアップがありません: ${BACKUP}`);
    process.exit(1);
  }
  const b = JSON.parse(fs.readFileSync(BACKUP, 'utf8'));
  const n = await writeBatches(
    b.addFollowing || {},
    b.addFollowers || {},
    admin.firestore.FieldValue.arrayRemove
  );
  console.log(`ロールバック完了: ${n} 人を元に戻しました（${b.at} の変更）`);
}

async function main() {
  if (rollback) return doRollback();

  const snap = await db.collection('users').get();
  const following = new Map();
  const followers = new Map();
  const exists = new Set();
  for (const d of snap.docs) {
    exists.add(d.id);
    const strings = (a) => new Set((a || []).filter((x) => typeof x === 'string'));
    following.set(d.id, strings(d.data().following));
    followers.set(d.id, strings(d.data().followers));
  }

  // 向きを無視した友達ペアを列挙する
  const undirected = new Set();
  let dangling = 0;
  for (const [a, set] of following) {
    for (const b of set) {
      if (a === b) continue;
      if (!exists.has(b)) { dangling++; continue; }
      undirected.add(a < b ? `${a}|${b}` : `${b}|${a}`);
    }
  }

  // 各ペアについて following / followers の 4 方向すべてを揃える
  const addFollowing = {};
  const addFollowers = {};
  const push = (m, k, v) => { (m[k] ||= []).push(v); };
  for (const key of undirected) {
    const [a, b] = key.split('|');
    if (!following.get(a).has(b)) push(addFollowing, a, b);
    if (!following.get(b).has(a)) push(addFollowing, b, a);
    if (!followers.get(a).has(b)) push(addFollowers, a, b);
    if (!followers.get(b).has(a)) push(addFollowers, b, a);
  }

  const count = (m) => Object.values(m).reduce((acc, v) => acc + v.length, 0);
  const touched = new Set([...Object.keys(addFollowing), ...Object.keys(addFollowers)]);

  fs.writeFileSync(
    BACKUP,
    JSON.stringify(
      {
        at: new Date().toISOString(),
        note: 'mutualize_follows.js が追加した edge。--rollback で arrayRemove して戻せる。',
        addFollowing,
        addFollowers,
      },
      null,
      2
    )
  );

  console.log(`ユーザー: ${exists.size} 人 / 友達ペア: ${undirected.size} 組`);
  console.log(`存在しない相手への edge: ${dangling} 件（対象外）`);
  console.log(`following 追加: ${count(addFollowing)} 件 / followers 追加: ${count(addFollowers)} 件`);
  console.log(`対象ユーザー: ${touched.size} 人`);
  console.log(`バックアップ: ${BACKUP}`);

  if (!apply) {
    console.log('\n--apply が無いため書き込みませんでした。');
    return;
  }
  const n = await writeBatches(addFollowing, addFollowers, admin.firestore.FieldValue.arrayUnion);
  console.log(`\n適用完了: ${n} 人を更新しました。`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => { console.error(e); process.exit(1); });
