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

// Flutter PostTheme format: gradientStart/End/commentButtonColor/textColor/iconColor as ARGB int
const THEMES = [
  { gradientStart: 0x000A0A0A, gradientEnd: 0xFF0A0A0A, commentButtonColor: 0xFF1DB954, textColor: 0xFFFFFFFF, iconColor: 0xFFFFFFFF },
  { gradientStart: 0x001A1A2E, gradientEnd: 0xFF1A1A2E, commentButtonColor: 0xFF0F3460, textColor: 0xFFE0E0E0, iconColor: 0xFFFFFFFF },
  { gradientStart: 0x0016213E, gradientEnd: 0xFF16213E, commentButtonColor: 0xFF0F3460, textColor: 0xFFFFFFFF, iconColor: 0xFFFFFFFF },
  { gradientStart: 0x000F0F0F, gradientEnd: 0xFF0F0F0F, commentButtonColor: 0xFFFF6B6B, textColor: 0xFFFFFFFF, iconColor: 0xFFFFFFFF },
  { gradientStart: 0x001C1C1E, gradientEnd: 0xFF1C1C1E, commentButtonColor: 0xFF5856D6, textColor: 0xFFFFFFFF, iconColor: 0xFFFFFFFF },
  { gradientStart: 0x00000000, gradientEnd: 0xFF000000, commentButtonColor: 0xFFFF375F, textColor: 0xFFFFFFFF, iconColor: 0xFFFFFFFF },
];

function randomInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function pickRandom(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

// 0:xx JST: 7人、1:xx JST: 1人、2:xx JST: 1人、3:xx JST: 1人
function getPostHour(index) {
  return index < 7 ? 0 : index - 6;
}

async function fetchTop50Tracks(fallback) {
  try {
    const rssRes = await fetch('https://itunes.apple.com/jp/rss/topsongs/limit=50/json');
    const rssData = await rssRes.json();
    const entries = rssData.feed?.entry || [];
    const trackIds = entries.map(e => e.id?.attributes?.['im:id']).filter(Boolean).join(',');
    if (!trackIds) throw new Error('track IDs empty');

    const lookupRes = await fetch(`https://itunes.apple.com/lookup?id=${trackIds}&country=jp`);
    const lookupData = await lookupRes.json();
    const tracks = (lookupData.results || [])
      .filter(r => r.wrapperType === 'track')
      .map(r => ({
        trackId:       String(r.trackId),
        trackName:     r.trackName,
        artistName:    r.artistName,
        albumImageUrl: (r.artworkUrl100 || '').replace('100x100bb', '600x600bb'),
        previewUrl:    r.previewUrl || null,
      }));
    console.log(`iTunes TOP50取得成功 (${tracks.length}件)`);
    return tracks.length > 0 ? tracks : fallback;
  } catch (e) {
    console.log(`iTunes TOP50取得失敗、フォールバック使用: ${e.message}`);
    return fallback;
  }
}

async function main() {
  const now = new Date();
  const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const jstYear  = jstNow.getUTCFullYear();
  const jstMonth = jstNow.getUTCMonth();
  const jstDate  = jstNow.getUTCDate();
  const dateKey  = `${jstYear}-${String(jstMonth + 1).padStart(2,'0')}-${String(jstDate).padStart(2,'0')}`;

  console.log(`=== ダミー投稿作成 (${dateKey}) ===`);

  // 冪等チェック
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

  const userIds        = usersSnap.data().userIds || [];
  const postPhotoUrls  = photosSnap.data().postPhotoUrls || [];
  const fallbackTracks = tracksSnap.data().list || [];

  console.log(`ユーザー: ${userIds.length}人 / 写真: ${postPhotoUrls.length}枚`);

  // iTunes TOP50 取得
  const tracks = await fetchTop50Tracks(fallbackTracks);

  // アクティブなVibe topic を取得
  let activeTopic = null;
  try {
    const topicSnap = await db.collection('vibe_topics').where('status', '==', 'active').limit(1).get();
    if (!topicSnap.empty) {
      const doc = topicSnap.docs[0];
      activeTopic = { id: doc.id, ...doc.data() };
      console.log(`Vibe topic: "${activeTopic.title}"`);
    } else {
      console.log('アクティブなVibeトピックなし（通常投稿になります）');
    }
  } catch (e) {
    console.log(`Vibeトピック取得エラー: ${e.message}`);
  }

  // ユーザーをシャッフル
  const shuffledIds = [...userIds].sort(() => Math.random() - 0.5);

  const userDocs = await Promise.all(
    shuffledIds.map(uid => db.collection('users').doc(uid).get())
  );

  const batch = db.batch();
  let createdCount = 0;

  for (let i = 0; i < shuffledIds.length; i++) {
    const userId  = shuffledIds[i];
    const userDoc = userDocs[i];
    if (!userDoc.exists) { console.log(`  Skip ${userId}: ドキュメントなし`); continue; }

    const userData = userDoc.data();

    const postHour   = getPostHour(i);
    const postMinute = randomInt(0, 59);
    const postSecond = randomInt(0, 59);
    const postTimeJst = new Date(Date.UTC(jstYear, jstMonth, jstDate, postHour, postMinute, postSecond));
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
        trackId:       track.trackId,
        trackName:     track.trackName,
        artistName:    track.artistName,
        albumImageUrl: track.albumImageUrl,
        previewUrl:    track.previewUrl || null,
        trackUrl:      null,
        lyrics:        null,
        tempo:         null,
      },
      photoUrl,
      imageOffsetX: 0.0, imageOffsetY: 0.0, imageScale: 1.0,
      imageNaturalWidth: 0.0, imageNaturalHeight: 0.0,
      selectedLayoutIndex: layoutIndex,
      cardPositionX: 0.0, cardPositionY: 0.0, cardScale: 1.0, cardRotation: 0.0,
      theme: { gradientStart: theme.gradientStart, gradientEnd: theme.gradientEnd, commentButtonColor: theme.commentButtonColor, textColor: theme.textColor, iconColor: theme.iconColor },
      likeCount: 0, commentCount: 0,
      likedUserIds: [], likedByUserIconUrls: [],
      savedByUserIds: [], savedByUserIconUrls: [],
      isVibe:         activeTopic !== null,
      vibeTopicId:    activeTopic?.id    || null,
      vibeTopicTitle: activeTopic?.title || null,
      vibeDate:       activeTopic?.date  || null,
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
    console.log(`  ✓ ${userData.username}: ${track.trackName} (${postHour}:${String(postMinute).padStart(2,'0')} JST)`);
  }

  await batch.commit();
  console.log(`\n完了: ${createdCount}件の投稿を作成しました`);
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
