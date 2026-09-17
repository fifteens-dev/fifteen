/**
 * 友達成立アニメーション（FriendMatchService）のお祝い履歴をリセットする
 *
 * アプリは users/{uid}.friendMatchCelebrated に「祝い済みの相手」を残し、
 * 今の友達との差分でお祝いを出す。初回起動時に今の友達を全員ここへ書き込む
 * ため、既にアプリを開いたアカウントは差分が無く、二度と出ない状態になる。
 *
 * このスクリプトはその履歴を空にして、次にアプリを開いたときから
 * 1人目 → 2人目 → 3人目 の順に再生されるようにする。
 * （1回のアプリ起動につき 1 人分。連続では出さない仕様のため）
 *
 * 実行:
 *   cd scripts && node reset_friend_match.js <UID>           # 確認のみ
 *   cd scripts && node reset_friend_match.js <UID> --apply   # 実際に消す
 */
const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const uid = process.argv[2];
const apply = process.argv.includes('--apply');

if (!uid || uid.startsWith('--')) {
  console.error('UID を指定してください: node reset_friend_match.js <UID> [--apply]');
  process.exit(1);
}

async function main() {
  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    console.error(`users/${uid} が見つかりません`);
    process.exit(1);
  }

  const data = snap.data();
  const following = data.following || [];
  const followers = data.followers || [];
  const friends = following.filter((u) => followers.includes(u));
  const celebrated = data.friendMatchCelebrated;

  console.log(`ユーザー   : ${data.name || data.username || uid}`);
  console.log(`友達       : ${friends.length} 人`);
  console.log(
    `祝い済み   : ${celebrated === undefined ? '(未設定)' : `${celebrated.length} 人`}`
  );

  if (!apply) {
    console.log('\n--apply を付けると friendMatchCelebrated を空にします。');
    console.log('その後アプリを開くたびに、友達 1 人ずつお祝いが再生されます。');
    return;
  }

  // フィールドを消すと「初回」とみなされて今の友達で埋め直されてしまうため、
  // 空配列を入れる（アプリ側は List かどうかで初回判定している）。
  await ref.update({ friendMatchCelebrated: [] });
  console.log('\n✅ 履歴を空にしました。アプリを開くと 1 人目から再生されます。');
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
