/**
 * ダミーユーザー投稿を今日分だけ即時作成するスクリプト
 * 使い方: cd scripts && node run_dummy_posts_now.js
 */

const admin = require('firebase-admin');
// node-vibrant の内部モジュールを直接使用して Flutter の PaletteGenerator と同じアルゴリズムを再現
const NodeImage   = require('node-vibrant/lib/image/node').default;
const { MMCQ }    = require('node-vibrant/lib/quantizer');
const defaultFilter = require('node-vibrant/lib/filter/default').default;
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

// ── アルバムアートからPostThemeを抽出するヘルパー ─────────────────

function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s = 0;
  const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
      case g: h = ((b - r) / d + 2) / 6; break;
      case b: h = ((r - g) / d + 4) / 6; break;
    }
  }
  return [h, s, l];
}

function hslToRgb(h, s, l) {
  if (s === 0) { const v = Math.round(l * 255); return [v, v, v]; }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const hue2rgb = (t) => {
    if (t < 0) t += 1; if (t > 1) t -= 1;
    if (t < 1/6) return p + (q - p) * 6 * t;
    if (t < 1/2) return q;
    if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
    return p;
  };
  return [Math.round(hue2rgb(h + 1/3) * 255), Math.round(hue2rgb(h) * 255), Math.round(hue2rgb(h - 1/3) * 255)];
}

function toArgbInt(alpha, r, g, b) {
  return (alpha & 0xFF) * 16777216 + (r & 0xFF) * 65536 + (g & 0xFF) * 256 + (b & 0xFF);
}

const DEFAULT_THEME = {
  gradientStart:      0x001A1A2E,
  gradientEnd:        0xFF1A1A2E,
  commentButtonColor: 0xFF253A5E,
  textColor:          0xFFFFFFFF,
  iconColor:          0xFFFFFFFF,
};

async function extractThemeFromAlbumArt(albumArtUrl) {
  try {
    const res = await fetch(albumArtUrl);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());

    // Flutter の PaletteGenerator.fromImageProvider と同じパイプライン:
    //   1. 200×200 にリサイズ (Flutter: size: Size(200, 200))
    //   2. デフォルトフィルタ適用（透明・白に近いピクセルを除外）
    //   3. MMCQ で colorCount=20 に量子化 (Flutter: maximumColorCount: 20)
    //   4. population 最大のスウォッチ = dominantColor
    const img = new NodeImage();
    await img.load(buf);
    img.resize(200, 200, 1);

    const imageData = img.getImageData();
    const pixels = imageData.data;
    for (let i = 0; i < pixels.length / 4; i++) {
      const off = i * 4;
      if (!defaultFilter(pixels[off], pixels[off+1], pixels[off+2], pixels[off+3])) {
        pixels[off+3] = 0;
      }
    }

    const swatches = MMCQ(imageData.data, { colorCount: 20 });
    img.remove();
    if (!swatches.length) return DEFAULT_THEME;

    swatches.sort((a, b) => b.population - a.population);
    const [r, g, b] = swatches[0].getRgb();

    const [h, s, l] = rgbToHsl(r, g, b);
    const isDark = l < 0.5;
    const [cr, cg, cb] = hslToRgb(h, s, Math.min(l * 1.1, 1.0));
    return {
      gradientStart:      toArgbInt(0,   r,  g,  b),
      gradientEnd:        toArgbInt(255, r,  g,  b),
      commentButtonColor: toArgbInt(255, cr, cg, cb),
      textColor:  isDark ? 0xFFFFFFFF : 0xFF000000,
      iconColor:  isDark ? 0xFFFFFFFF : 0xFF000000,
    };
  } catch (e) {
    console.error('Theme extraction error:', e.message);
    return DEFAULT_THEME;
  }
}

// レイアウト別サイズ (363×645 px カード基準) — index 0 は使用しない
const LAYOUT_CARD_SIZES = [
  { w: 196, h: 150 }, // 0: standard (歌詞テキスト・使用しない)
  { w: 105, h: 147 }, // 1: largeAlbumArt
  { w: 172, h:  42 }, // 2: horizontalBar
  { w: 140, h: 152 }, // 3: albumArtOnly
  { w: 130, h:  61 }, // 4: musicPlayer
];

function getCenteredCardPos(layoutIndex) {
  const size = LAYOUT_CARD_SIZES[layoutIndex] || LAYOUT_CARD_SIZES[1];
  return { x: (363 - size.w) / 2, y: (645 - size.h) / 2 };
}

function randomInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function pickRandom(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

// 0:xx JST: 7人、1:xx JST: 1人、2:xx JST: 1人、3:xx JST: 1人
function getPostHour(index) {
  return index < 7 ? 0 : index - 6;
}

// Spotify の認証情報を ../.env から読み込む
// Apple Music API で日本 TOP チャートを取得（Flutter の getTopCharts と同じ）
function loadAppleMusicToken() {
  const fs = require('fs');
  const path = require('path');
  try {
    const content = fs.readFileSync(path.join(__dirname, '../.env'), 'utf8');
    const env = {};
    content.split('\n').forEach(line => {
      const m = line.match(/^([^#=]+)=(.*)$/);
      if (m) env[m[1].trim()] = m[2].trim();
    });
    return env.APPLE_MUSIC_DEVELOPER_TOKEN || '';
  } catch { return ''; }
}

async function fetchAppleMusicJapanTop50(fallback) {
  try {
    const developerToken = loadAppleMusicToken();
    if (!developerToken) throw new Error('APPLE_MUSIC_DEVELOPER_TOKEN未設定');

    const res = await fetch(
      'https://api.music.apple.com/v1/catalog/jp/charts?types=songs&limit=50&l=ja-JP',
      { headers: { 'Authorization': `Bearer ${developerToken}` } }
    );
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    const songs = data.results?.songs?.[0]?.data || [];
    const tracks = songs.map(d => {
      const attr = d.attributes;
      const artworkUrl = (attr.artwork?.url || '').replace('{w}', '640').replace('{h}', '640');
      const previewUrl = attr.previews?.[0]?.url || null;
      return {
        trackId:       d.id,
        trackName:     attr.name,
        artistName:    attr.artistName,
        albumImageUrl: artworkUrl,
        previewUrl,
      };
    });

    if (tracks.length === 0) throw new Error('トラック0件');
    console.log(`Apple Music Japan TOP50取得成功 (${tracks.length}件)`);
    return tracks;
  } catch (e) {
    console.log(`Apple Music TOP50取得失敗: ${e.message}`);
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

  // Spotify Japan TOP50 取得（失敗時はFirestoreのフォールバックを使用）
  const tracks = await fetchAppleMusicJapanTop50(fallbackTracks);

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

  // ランダムデータを事前に計算
  const selections = shuffledIds.map(() => ({
    photoUrl:    pickRandom(postPhotoUrls),
    track:       pickRandom(tracks),
    layoutIndex: pickRandom([1, 2, 3]), // 0(歌詞テキスト)は使用しない
  }));

  // アルバムアートから色を並列抽出
  const themes = await Promise.all(
    selections.map(sel => extractThemeFromAlbumArt(sel.track.albumImageUrl))
  );

  const batch = db.batch();
  let createdCount = 0;

  for (let i = 0; i < shuffledIds.length; i++) {
    const userId  = shuffledIds[i];
    const userDoc = userDocs[i];
    if (!userDoc.exists) { console.log(`  Skip ${userId}: ドキュメントなし`); continue; }

    const userData = userDoc.data();
    const { photoUrl, track, layoutIndex } = selections[i];
    const theme   = themes[i];
    const cardPos = getCenteredCardPos(layoutIndex);

    const postHour   = getPostHour(i);
    const postMinute = randomInt(0, 59);
    const postSecond = randomInt(0, 59);
    const postTimeJst = new Date(Date.UTC(jstYear, jstMonth, jstDate, postHour, postMinute, postSecond));
    const postTimeUtc = new Date(postTimeJst.getTime() - 9 * 60 * 60 * 1000);
    const postTimestamp = admin.firestore.Timestamp.fromDate(postTimeUtc);

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
      cardPositionX: cardPos.x, cardPositionY: cardPos.y, cardScale: 1.0, cardRotation: 0.0,
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
