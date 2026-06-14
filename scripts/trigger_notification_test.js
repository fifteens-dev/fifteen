/**
 * 通知テスト用スクリプト
 *
 * 実行: cd scripts && node trigger_notification_test.js
 *
 * 処理:
 *   全600バルクダミーから1件ずつ投稿を作成 (計600件)
 *   onPostCreated トリガーが600回起動し、各ダミーの followers に通知が飛ぶ。
 *
 * 前提:
 *   - setupTestFollows でテストアカウントが600ダミーをフォロー済み (双方向)
 *     → 各ダミーの followers にテストアカウントUIDが入っている
 *
 * 結果:
 *   テストアカウントに即時通知が約600件届く（FCMトークン経由）
 *   3時間後にまとめ通知が1件届く（2人目以降の集約）
 *
 * クリーンアップ:
 *   node trigger_notification_test.js --cleanup
 *   または node load_test.js --cleanup（isLoadTest:true なので同じフィルタで削除可）
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const _DEFAULT_THEME = {
  gradientStart:      0x001A1A2E,
  gradientEnd:        0xFF1A1A2E,
  commentButtonColor: 0xFF253A5E,
  textColor:          0xFFFFFFFF,
  iconColor:          0xFFFFFFFF,
};

function pickRandom(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function randomInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }

async function cleanup() {
  console.log('=== クリーンアップ: 通知テスト投稿を削除 ===');
  let deleted = 0;
  let snap = await db.collection('posts').where('isNotificationTest', '==', true).get();
  while (!snap.empty) {
    const batch = db.batch();
    snap.docs.slice(0, 450).forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    deleted += Math.min(snap.docs.length, 450);
    snap = await db.collection('posts').where('isNotificationTest', '==', true).get();
  }
  console.log(`  → ${deleted}件削除`);
  process.exit(0);
}

async function trigger() {
  console.log('=== 通知テスト: 600ダミーから一斉投稿 ===\n');

  // ── データ取得 ──────────────────────────────────────────
  const [bulkSnap, photosSnap, tracksSnap, topicSnap] = await Promise.all([
    db.doc('dummy_config/bulkDummyUsers').get(),
    db.doc('dummy_config/photos').get(),
    db.doc('dummy_config/tracks').get(),
    db.collection('vibe_topics').where('status', '==', 'active').limit(1).get(),
  ]);

  if (!bulkSnap.exists) { console.error('❌ bulkDummyUsers がありません'); process.exit(1); }
  const bulkUids = bulkSnap.data().userIds || [];
  const photos = photosSnap.data()?.postPhotoUrls || [];
  const tracks = tracksSnap.data()?.list || [];

  if (tracks.length === 0) { console.error('❌ tracks が空'); process.exit(1); }

  const activeTopic = topicSnap.empty ? null : { id: topicSnap.docs[0].id, ...topicSnap.docs[0].data() };
  console.log(`バルクダミー: ${bulkUids.length}人`);
  console.log(`楽曲: ${tracks.length}曲, 写真: ${photos.length}枚`);
  console.log(`Vibeトピック: ${activeTopic ? activeTopic.title : 'なし'}`);

  // ── ユーザー情報を一括取得 ─────────────────────────────
  console.log('\nユーザー情報取得中...');
  const userDocs = {};
  for (let i = 0; i < bulkUids.length; i += 100) {
    const chunk = bulkUids.slice(i, i + 100);
    const docs = await Promise.all(chunk.map(uid => db.collection('users').doc(uid).get()));
    docs.forEach(d => { if (d.exists) userDocs[d.id] = d.data(); });
  }
  console.log(`  → ${Object.keys(userDocs).length}人のデータ取得`);

  // フォロワー数を確認（通知が飛ぶ先がいるか）
  let withFollowers = 0;
  for (const data of Object.values(userDocs)) {
    if ((data.followers || []).length > 0) withFollowers++;
  }
  console.log(`  → フォロワーありユーザー: ${withFollowers}/${Object.keys(userDocs).length}`);
  if (withFollowers === 0) {
    console.error('\n⚠️ どのダミーもフォロワー0人です。setupTestFollows が未実行の可能性');
    console.error('   管理パネル → 「フォロー設定」ボタンを押してから再実行してください');
    process.exit(1);
  }

  // ── 投稿を作成（バッチ書き込みで一斉） ──────────────────
  console.log(`\n${bulkUids.length}件の投稿を作成中（onPostCreated トリガー起動）...`);
  const start = Date.now();
  const BATCH = 400;
  const batchPromises = [];
  let batch = db.batch();
  let ops = 0;
  let created = 0;

  for (const uid of bulkUids) {
    const userData = userDocs[uid];
    if (!userData) continue;

    const track = pickRandom(tracks);
    // 裏面用に photoUrl は本物の Storage 写真を割り当てる
    const photoUrl = pickRandom(photos);
    const layoutIndex = pickRandom([1, 2, 3]);

    const ref = db.collection('posts').doc();
    batch.set(ref, {
      userId:      uid,
      username:    userData.username || `dummy_${created}`,
      userIconUrl: userData.profileImageUrl || null,
      track: {
        trackId:       track.trackId,
        trackName:     track.trackName,
        artistName:    track.artistName,
        albumImageUrl: track.albumImageUrl,
        previewUrl:    track.previewUrl || null,
        trackUrl: null, lyrics: null, tempo: null,
      },
      photoUrl,
      imageOffsetX: 0.0, imageOffsetY: 0.0, imageScale: 1.0,
      imageNaturalWidth: 0.0, imageNaturalHeight: 0.0,
      selectedLayoutIndex: layoutIndex,
      cardPositionX: 129.0, cardPositionY: 249.0,
      cardScale: 1.0, cardRotation: 0.0,
      theme: _DEFAULT_THEME,
      likeCount: 0, commentCount: 0,
      likedUserIds: [], likedByUserIconUrls: [],
      savedByUserIds: [], savedByUserIconUrls: [],
      isVibe:           activeTopic !== null,
      vibeTopicId:      activeTopic?.id || null,
      vibeTopicTitle:   activeTopic?.title || null,
      vibeDate:         activeTopic?.date || null,
      emotionTag: null, lyricsText: null,
      audioStartMs: 0, audioDurationSec: 15,
      university: null,
      campusVibeParticipating: false, campusVibePost: false,
      adlTeamId: userData.adlTeamId || null,
      isDummyPost: false,
      isLoadTest: true,
      isNotificationTest: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    ops++;
    created++;

    if (ops >= BATCH) {
      batchPromises.push(batch.commit());
      batch = db.batch();
      ops = 0;
      process.stdout.write(`\r  ${created}/${bulkUids.length}`);
    }
  }
  if (ops > 0) batchPromises.push(batch.commit());
  await Promise.all(batchPromises);
  process.stdout.write(`\r  ${created}/${bulkUids.length}\n`);

  const elapsed = Math.round((Date.now() - start) / 1000);
  console.log(`\n✅ ${created}件作成 (${elapsed}秒)`);
  console.log('\n以下が並行して進行します:');
  console.log('  - onPostCreated トリガーが600回起動');
  console.log('  - 各ダミーの followers に即時通知が飛ぶ');
  console.log('  - 3時間後にまとめ通知 (2人目以降の集約)');
  console.log('\n💡 クリーンアップ: node trigger_notification_test.js --cleanup');
  process.exit(0);
}

async function main() {
  if (process.argv.includes('--cleanup')) {
    await cleanup();
  } else {
    await trigger();
  }
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
