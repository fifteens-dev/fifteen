/**
 * バルクダミー投稿の楽曲＆画像を実在の iTunes アルバムアートに統一するスクリプト
 *
 * 実行: cd scripts && node fix_dummy_photos.js
 *
 * 処理:
 * 1. dummy_config/tracks から Picsum を含むダミー楽曲(st001-st025)を除外
 * 2. iTunes 由来の本物楽曲のみで dummy_config/tracks を再構築
 * 3. 既存のバルクダミー投稿を全走査し、track の albumImageUrl が
 *    "picsum.photos" を含むなら本物の楽曲にランダムに置き換え
 * 4. photoUrl も新しい (本物の) albumImageUrl で上書き
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

function isBadUrl(url) {
  return !url || url.includes('picsum.photos');
}
function pickRandom(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

async function main() {
  console.log('=== バルクダミー投稿の楽曲・画像を本物に修正 ===\n');

  // ── Step 1: tracks をクリーンアップ ──────────────────────────────
  const tracksSnap = await db.doc('dummy_config/tracks').get();
  const allTracks = tracksSnap.data()?.list || [];
  const validTracks = allTracks.filter(t => !isBadUrl(t.albumImageUrl));
  console.log(`楽曲: 全${allTracks.length}件 → 本物${validTracks.length}件 (Picsum除外${allTracks.length - validTracks.length}件)`);

  if (validTracks.length === 0) {
    console.error('❌ 本物の楽曲が0件。iTunes取得済み楽曲がdummy_configにないと修正不可');
    process.exit(1);
  }

  // dummy_config/tracks を本物のみに更新
  await db.doc('dummy_config/tracks').set({
    list: validTracks,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`  → dummy_config/tracks を ${validTracks.length} 曲に再構築`);

  // ── Step 2: バルクダミー投稿を取得 ───────────────────────────────
  const bulkSnap = await db.doc('dummy_config/bulkDummyUsers').get();
  if (!bulkSnap.exists) {
    console.error('❌ bulkDummyUsers がありません');
    process.exit(1);
  }
  const bulkUids = bulkSnap.data().userIds || [];

  console.log('\n投稿を集計中...');
  const allPosts = [];
  for (let c = 0; c < bulkUids.length; c += 30) {
    const chunk = bulkUids.slice(c, c + 30);
    const snap = await db.collection('posts').where('userId', 'in', chunk).get();
    for (const doc of snap.docs) {
      allPosts.push({ ref: doc.ref, data: doc.data() });
    }
  }
  console.log(`バルクダミー投稿: ${allPosts.length}件`);
  if (allPosts.length === 0) {
    console.log('対象なし');
    process.exit(0);
  }

  // ── Step 3: 投稿を修正 ──────────────────────────────────────────
  console.log('\n投稿を修正中...');
  const BATCH = 400;
  const batchPromises = [];
  let batch = db.batch();
  let ops = 0;
  let replaced = 0;
  let photoFixed = 0;
  let skipped = 0;

  for (const { ref, data } of allPosts) {
    const currentAlbum = data.track?.albumImageUrl;
    const needsTrackReplace = isBadUrl(currentAlbum);

    if (needsTrackReplace) {
      // 楽曲ごと差し替え
      const newTrack = pickRandom(validTracks);
      batch.update(ref, {
        track: {
          trackId:       newTrack.trackId,
          trackName:     newTrack.trackName,
          artistName:    newTrack.artistName,
          albumImageUrl: newTrack.albumImageUrl,
          previewUrl:    newTrack.previewUrl || null,
          trackUrl:      null,
          lyrics:        null,
          tempo:         null,
        },
        photoUrl: newTrack.albumImageUrl,
      });
      replaced++;
      ops++;
    } else if (data.photoUrl !== currentAlbum) {
      // 楽曲はOK・photoUrl だけ揃える
      batch.update(ref, { photoUrl: currentAlbum });
      photoFixed++;
      ops++;
    } else {
      skipped++;
    }

    if (ops >= BATCH) {
      batchPromises.push(batch.commit());
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) batchPromises.push(batch.commit());
  await Promise.all(batchPromises);

  console.log(`\n✅ 完了`);
  console.log(`  楽曲ごと差し替え: ${replaced}件`);
  console.log(`  photoUrlのみ修正: ${photoFixed}件`);
  console.log(`  既に正しい: ${skipped}件`);
  console.log('\n実機でVibeページ／プロフィールを再読み込みするとアルバムアートが正しく表示されます');
  process.exit(0);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
