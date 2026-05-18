/**
 * ダミーユーザー投稿を今日分だけ即時作成するスクリプト
 * 使い方: cd scripts && node run_dummy_posts_now.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const THEMES = [
  { backgroundColor: '#0A0A0A', textColor: '#FFFFFF', accentColor: '#1DB954' },
  { backgroundColor: '#1A1A2E', textColor: '#E0E0E0', accentColor: '#0F3460' },
  { backgroundColor: '#16213E', textColor: '#FFFFFF', accentColor: '#0F3460' },
  { backgroundColor: '#0F0F0F', textColor: '#FFFFFF', accentColor: '#FF6B6B' },
  { backgroundColor: '#1C1C1E', textColor: '#FFFFFF', accentColor: '#5856D6' },
  { backgroundColor: '#000000', textColor: '#FFFFFF', accentColor: '#FF375F' },
];

function randomInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function pickRandom(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

async function main() {
  const now = new Date();
  const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const jstYear  = jstNow.getUTCFullYear();
  const jstMonth = jstNow.getUTCMonth();
  const jstDate  = jstNow.getUTCDate();
  const dateKey  = `${jstYear}-${String(jstMonth + 1).padStart(2,'0')}-${String(jstDate).padStart(2,'0')}`;

  console.log(`=== ダミー投稿作成 (${dateKey}) ===`);

  // 冪等チェック（lockがあれば上書き実行するか確認せずスキップ）
  const lockRef = db.doc(`daily_job_locks/dummyPosts_${dateKey}`);
  const lockSnap = await lockRef.get();
  if (lockSnap.exists) {
    console.log('本日分のロックが既に存在します。強制実行します（ロックを削除して再作成）');
    await lockRef.delete();
  }
  await lockRef.set({ createdAt: admin.firestore.FieldValue.serverTimestamp() });

  const [usersSnap, photosSnap, tracksSnap] = await Promise.all([
    db.doc('dummy_config/users').get(),
    db.doc('dummy_config/photos').get(),
    db.doc('dummy_config/tracks').get(),
  ]);

  const userIds       = usersSnap.data().userIds || [];
  const postPhotoUrls = photosSnap.data().postPhotoUrls || [];
  const tracks        = tracksSnap.data().list || [];

  console.log(`ユーザー: ${userIds.length}人 / 写真: ${postPhotoUrls.length}枚 / 曲: ${tracks.length}件`);

  const userDocs = await Promise.all(
    userIds.map(uid => db.collection('users').doc(uid).get())
  );

  const batch = db.batch();
  let createdCount = 0;

  for (let i = 0; i < userIds.length; i++) {
    const userId  = userIds[i];
    const userDoc = userDocs[i];
    if (!userDoc.exists) { console.log(`  Skip ${userId}: ドキュメントなし`); continue; }

    const userData = userDoc.data();
    const randomHour   = randomInt(8, 22);
    const randomMinute = randomInt(0, 59);
    const randomSecond = randomInt(0, 59);
    const postTimeJst = new Date(Date.UTC(jstYear, jstMonth, jstDate, randomHour, randomMinute, randomSecond));
    const postTimeUtc = new Date(postTimeJst.getTime() - 9 * 60 * 60 * 1000);
    const postTimestamp = admin.firestore.Timestamp.fromDate(postTimeUtc);

    const photoUrl    = pickRandom(postPhotoUrls);
    const track       = pickRandom(tracks);
    const theme       = pickRandom(THEMES);
    const layoutIndex = randomInt(0, 3);

    const postRef = db.collection('posts').doc();
    batch.set(postRef, {
      userId,
      username:    userData.username || '',
      userIconUrl: userData.profileImageUrl || null,
      track: {
        trackId: track.trackId, trackName: track.trackName,
        artistName: track.artistName, albumImageUrl: track.albumImageUrl,
        previewUrl: track.previewUrl || null, trackUrl: null, lyrics: null, tempo: null,
      },
      photoUrl,
      imageOffsetX: 0.0, imageOffsetY: 0.0, imageScale: 1.0,
      imageNaturalWidth: 0.0, imageNaturalHeight: 0.0,
      selectedLayoutIndex: layoutIndex,
      cardPositionX: 0.0, cardPositionY: 0.0, cardScale: 1.0, cardRotation: 0.0,
      theme: { backgroundColor: theme.backgroundColor, textColor: theme.textColor, accentColor: theme.accentColor },
      likeCount: 0, commentCount: 0,
      likedUserIds: [], likedByUserIconUrls: [],
      savedByUserIds: [], savedByUserIconUrls: [],
      isVibe: false, vibeTopicId: null, vibeTopicTitle: null, vibeDate: null,
      emotionTag: null, lyricsText: null, audioStartMs: 0, audioDurationSec: 15,
      university: userData.university || null,
      campusVibeParticipating: false, campusVibePost: false, adlTeamId: null,
      isDummyPost: true,
      createdAt: postTimestamp, updatedAt: postTimestamp,
    });

    batch.update(db.collection('users').doc(userId), {
      postsCount: admin.firestore.FieldValue.increment(1),
      updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
    });

    createdCount++;
    console.log(`  ✓ ${userData.username}: ${track.trackName} (${randomHour}:${String(randomMinute).padStart(2,'0')})`);
  }

  await batch.commit();
  console.log(`\n完了: ${createdCount}件の投稿を作成しました`);
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
