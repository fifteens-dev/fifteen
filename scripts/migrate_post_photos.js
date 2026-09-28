/**
 * 既存投稿の写真を「本人だけが見られる」置き場へ移す
 *
 * カード裏面が写真からプロフィールに変わったとき、既存投稿の photoUrl は
 * どこにも出なくなった。写真は「自分のカレンダーからのみ閲覧可能」という
 * 扱いになったので、非公開の置き場へ移して復帰させる。
 *
 * やること:
 *   1. Storage: post_images/... → private_photos/...  へコピー
 *      （post_images は誰でも読めるルールなので、そこに置いたままだと
 *        URL を知る人には見えてしまう）
 *   2. Firestore: post_photos/{postId} に新しい URL で作成
 *
 * posts.photoUrl と元ファイルは消さない。まだ写真を直接読んでいる画面
 * （Vibe ストーリー等）があり、消すとそちらが壊れる。片付けは表示側の
 * 移行が済んでから別途行う。
 *
 * 何度流しても安全（post_photos に既にあるものは飛ばす）。
 *
 * 実行:
 *   cd scripts && node migrate_post_photos.js          # 確認のみ
 *   cd scripts && node migrate_post_photos.js --apply  # 実際に移す
 */
const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'fifteens-39cfe.firebasestorage.app',
});
const db = admin.firestore();
const bucket = admin.storage().bucket();

const apply = process.argv.includes('--apply');

/** ダウンロード URL から Storage のパスを取り出す。 */
function storagePathFromUrl(url) {
  const m = /\/o\/([^?]+)/.exec(url);
  return m ? decodeURIComponent(m[1]) : null;
}

/** 非公開の置き場へコピーし、新しいダウンロード URL を返す。 */
async function copyToPrivate(srcPath, userId) {
  const file = bucket.file(srcPath);
  const [exists] = await file.exists();
  if (!exists) return null;

  const name = srcPath.split('/').pop();
  const destPath = `private_photos/${userId}/${name}`;
  const dest = bucket.file(destPath);

  const [already] = await dest.exists();
  if (!already) await file.copy(dest);

  // アプリが使うのと同じ形の URL にするため、ダウンロードトークンを付ける。
  const [meta] = await dest.getMetadata();
  let token = meta.metadata && meta.metadata.firebaseStorageDownloadTokens;
  if (!token) {
    token = require('crypto').randomUUID();
    await dest.setMetadata({
      metadata: { firebaseStorageDownloadTokens: token },
    });
  }
  return (
    'https://firebasestorage.googleapis.com/v0/b/' +
    bucket.name +
    '/o/' +
    encodeURIComponent(destPath) +
    '?alt=media&token=' +
    token
  );
}

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
    // Vibe ストーリーは写真そのものが投稿の中身。非公開にすると壊れる。
    if (d.isVibe === true) {
      skippedVibe++;
      continue;
    }
    if (!d.userId) continue;
    targets.push({ postId: doc.id, userId: d.userId, url, createdAt: d.createdAt });
  }

  const existing = new Set();
  (await db.collection('post_photos').get()).forEach((d) => existing.add(d.id));
  const pending = targets.filter((t) => !existing.has(t.postId));

  console.log(`写真なし    : ${skippedNoPhoto}`);
  console.log(`Vibe（除外）: ${skippedVibe}`);
  console.log(`移行対象    : ${targets.length}`);
  console.log(`移行済み    : ${targets.length - pending.length}`);
  console.log(`今回の対象  : ${pending.length}`);

  if (!apply) {
    console.log('\n--apply を付けると Storage のコピーと Firestore の書き込みを行います。');
    return;
  }

  let done = 0;
  let failed = 0;
  // Storage のコピーは 1 件ずつ時間がかかるので、少しずつ並列に流す。
  const concurrency = 8;
  for (let i = 0; i < pending.length; i += concurrency) {
    const chunk = pending.slice(i, i + concurrency);
    const results = await Promise.all(
      chunk.map(async (t) => {
        try {
          const src = storagePathFromUrl(t.url);
          if (!src) return { t, url: null };
          const url = await copyToPrivate(src, t.userId);
          return { t, url };
        } catch (e) {
          console.error(`  ${t.postId}: ${e.message}`);
          return { t, url: null };
        }
      })
    );

    const batch = db.batch();
    let inBatch = 0;
    for (const { t, url } of results) {
      if (!url) {
        failed++;
        continue;
      }
      batch.set(db.collection('post_photos').doc(t.postId), {
        userId: t.userId,
        photoUrl: url,
        // 写真を足した時刻は分からないので投稿時刻を使う。
        createdAt: t.createdAt ?? admin.firestore.FieldValue.serverTimestamp(),
        migrated: true,
      });
      inBatch++;
    }
    if (inBatch > 0) await batch.commit();
    done += inBatch;
    if (i % 80 === 0 || i + concurrency >= pending.length) {
      console.log(`  ${done + failed}/${pending.length}（成功 ${done} / 失敗 ${failed}）`);
    }
  }

  console.log(`\n✅ 完了: 成功 ${done} / 失敗 ${failed}`);
  if (failed > 0) {
    console.log('失敗ぶんは元ファイルが見つからないもの。もう一度流せば再試行する。');
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
