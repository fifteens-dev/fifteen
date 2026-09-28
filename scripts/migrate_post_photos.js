/**
 * 既存投稿の写真を post_photos へ移す
 *
 * カード裏面が写真からプロフィールに変わったとき、既存投稿の photoUrl は
 * どこにも出なくなった。写真は「自分のカレンダーからのみ閲覧可能」という
 * 扱いになったので、非公開コレクション post_photos へ移して復帰させる。
 *
 * posts.photoUrl は消さない。まだ写真を直接読んでいる画面（Vibe ストーリー等）
 * があり、消すとそちらが壊れる。二重に持つ形になるが、post_photos 側だけが
 * 「カレンダーに出す写真」の正となる。
 *
 * 実行:
 *   cd scripts && node migrate_post_photos.js          # 確認のみ（何も書かない）
 *   cd scripts && node migrate_post_photos.js --apply  # 実際に書き込む
 */
const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const apply = process.argv.includes('--apply');

async function main() {
  const snap = await db.collection('posts').get();
  console.log(`投稿総数: ${snap.size}`);

  const targets = [];
  let skippedNoPhoto = 0;
  let skippedVibe = 0;

  for (const doc of snap.docs) {
    const d = doc.data();
    const url = d.photoUrl;
    if (typeof url !== 'string' || url === '') {
      skippedNoPhoto++;
      continue;
    }
    // Vibe ストーリーは写真そのものが投稿の中身なので、非公開にすると壊れる。
    if (d.isVibe === true) {
      skippedVibe++;
      continue;
    }
    if (!d.userId) continue;
    targets.push({ postId: doc.id, userId: d.userId, url, createdAt: d.createdAt });
  }

  console.log(`写真なし    : ${skippedNoPhoto}`);
  console.log(`Vibe（除外）: ${skippedVibe}`);
  console.log(`移行対象    : ${targets.length}`);

  // 既に移行済みのものは飛ばす（何度流しても安全にする）。
  const existing = new Set();
  const existingSnap = await db.collection('post_photos').get();
  existingSnap.forEach((d) => existing.add(d.id));
  const pending = targets.filter((t) => !existing.has(t.postId));
  console.log(`移行済み    : ${targets.length - pending.length}`);
  console.log(`今回書き込む: ${pending.length}`);

  if (!apply) {
    console.log('\n--apply を付けると書き込みます。');
    pending.slice(0, 5).forEach((t) =>
      console.log(`  ${t.postId} (${t.userId})`)
    );
    if (pending.length > 5) console.log(`  … 他 ${pending.length - 5} 件`);
    return;
  }

  // batch は 500 件まで。
  let written = 0;
  for (let i = 0; i < pending.length; i += 400) {
    const chunk = pending.slice(i, i + 400);
    const batch = db.batch();
    for (const t of chunk) {
      batch.set(db.collection('post_photos').doc(t.postId), {
        userId: t.userId,
        photoUrl: t.url,
        // 移行ぶんは投稿時刻をそのまま使う（写真を足した時刻は分からない）。
        createdAt: t.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
        migrated: true,
      });
    }
    await batch.commit();
    written += chunk.length;
    console.log(`  ${written}/${pending.length}`);
  }
  console.log('\n✅ 完了');
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
