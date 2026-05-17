/**
 * ダミーユーザーセットアップスクリプト
 *
 * 実行方法:
 *   cd scripts && node setup_dummy_users.js
 *
 * 処理内容:
 * 1. プロフィール写真 (6枚) を Firebase Storage にアップロード
 * 2. 投稿用写真 (86枚) を Firebase Storage にアップロード
 * 3. iTunes Search API でトラック情報を取得 → Firestore に保存
 * 4. ダミーユーザー10人分の Firestore ドキュメントを作成
 * 5. dummy_config ドキュメントに URL リストを保存
 *
 * 注意: 既に実行済みのリソースはスキップされます（冪等）
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const https = require('https');

// ── Firebase 初期化 ─────────────────────────────────────────────────
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'fifteens-39cfe.firebasestorage.app',
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

// ── 定数 ──────────────────────────────────────────────────────────────
const PROFILE_PHOTOS_DIR = '/Users/gotoutarou/Downloads/ダミーユーザーのトプ画';
const POST_PHOTOS_DIR    = '/Users/gotoutarou/Downloads/ダミーユーザー投稿用';

// 6枚のプロフィール写真ファイル名 (昇順)
const PROFILE_PHOTO_FILES = [
  'LINE_ALBUM_ダミーユーザー10人分のトプ画_260517_1.jpg',
  'LINE_ALBUM_ダミーユーザー10人分のトプ画_260517_2.jpg',
  'LINE_ALBUM_ダミーユーザー10人分のトプ画_260517_3.jpg',
  'LINE_ALBUM_ダミーユーザー10人分のトプ画_260517_4.jpg',
  'LINE_ALBUM_ダミーユーザー10人分のトプ画_260517_5.jpg',
  'LINE_ALBUM_ダミーユーザー10人分のトプ画_260517_6.jpg',
];

// ダミーユーザー定義 (6名はトプ画あり、4名はデフォルトアイコン)
const DUMMY_USERS = [
  { id: 'dummy_user_01', name: '田中 あおい', username: 'aoi_tanaka',     university: '慶應義塾大学',   photoFileIndex: 0 },
  { id: 'dummy_user_02', name: '鈴木 ひな',   username: 'hina_suzuki',    university: '早稲田大学',     photoFileIndex: 1 },
  { id: 'dummy_user_03', name: '中村 さくら', username: 'sakura_nakamura',university: '東京大学',       photoFileIndex: 2 },
  { id: 'dummy_user_04', name: '山田 ゆい',   username: 'yui_yamada',     university: '明治大学',       photoFileIndex: 3 },
  { id: 'dummy_user_05', name: '高橋 みお',   username: 'mio_takahashi',  university: '立教大学',       photoFileIndex: 4 },
  { id: 'dummy_user_06', name: '伊藤 ことね', username: 'kotone_ito',     university: '青山学院大学',   photoFileIndex: 5 },
  { id: 'dummy_user_07', name: '渡辺 りな',   username: 'rina_watanabe',  university: '法政大学',       photoFileIndex: null },
  { id: 'dummy_user_08', name: '小林 なな',   username: 'nana_kobayashi', university: '上智大学',       photoFileIndex: null },
  { id: 'dummy_user_09', name: '加藤 はる',   username: 'haru_kato',      university: '東京理科大学',   photoFileIndex: null },
  { id: 'dummy_user_10', name: '松本 みく',   username: 'miku_matsumoto', university: '中央大学',       photoFileIndex: null },
];

// iTunes Search API で取得する楽曲リスト (term: 検索クエリ)
const TRACK_SEARCH_QUERIES = [
  'Pretender Official髭男dism',
  '夜に駆ける YOASOBI',
  'うっせぇわ Ado',
  'Lemon 米津玄師',
  '白日 King Gnu',
  '水平線 back number',
  'マリーゴールド Aimyon',
  '群青 YOASOBI',
  'Subtitle Official髭男dism',
  'ドライフラワー 優里',
  'Cry Baby Official髭男dism',
  'きらり 藤井風',
  'Habit SaurusS',
  'のびしろ Creepy Nuts',
  'KICK BACK 米津玄師',
  'ダンスホール Mrs GREEN APPLE',
  'NIGHT DANCER imase',
  'アイドル YOASOBI',
  '踊 Ado',
  'クリスマスソング back number',
  'ハルジオン YOASOBI',
  '三文小説 King Gnu',
  'Butter BTS',
  'Hype Boy NewJeans',
  'FANCY TWICE',
];

// ── ユーティリティ ────────────────────────────────────────────────────

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}

/**
 * iTunes Search API でトラック情報を取得
 * 1秒のウェイトを挟んでレートリミット対策
 */
async function searchTrack(query) {
  const encoded = encodeURIComponent(query);
  const url = `https://itunes.apple.com/search?term=${encoded}&country=jp&media=music&entity=song&limit=1`;
  try {
    const json = await fetchJson(url);
    if (json.resultCount > 0) {
      const r = json.results[0];
      return {
        trackId: String(r.trackId),
        trackName: r.trackName,
        artistName: r.artistName,
        albumImageUrl: r.artworkUrl100.replace('100x100bb', '500x500bb'),
        previewUrl: r.previewUrl || null,
      };
    }
  } catch (e) {
    console.warn(`  ⚠ iTunes API error for "${query}": ${e.message}`);
  }
  return null;
}

/**
 * Firebase Storage にファイルをアップロードして download URL を返す。
 * 既にアップロード済みのパスは skip する。
 */
async function uploadFile(localPath, storagePath, contentType = 'image/jpeg') {
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (exists) {
    const [meta] = await file.getMetadata();
    const url = meta.mediaLink;
    // getDownloadURL 代わりに makePublic + publicUrl を使用
    const publicUrl = `https://storage.googleapis.com/${bucket.name}/${storagePath}`;
    // signed URL を使わず直接 download URL を取得
    const [signedUrl] = await file.getSignedUrl({
      action: 'read',
      expires: '03-01-2100',
    });
    console.log(`  ↩ Skip (already exists): ${storagePath}`);
    return signedUrl;
  }

  const [, metadata] = await bucket.upload(localPath, {
    destination: storagePath,
    metadata: {
      contentType,
      cacheControl: 'public, max-age=2592000',
    },
  });

  const [signedUrl] = await bucket.file(storagePath).getSignedUrl({
    action: 'read',
    expires: '03-01-2100',
  });

  console.log(`  ✓ Uploaded: ${storagePath}`);
  return signedUrl;
}

// ── メイン処理 ────────────────────────────────────────────────────────

async function main() {
  console.log('=== ダミーユーザーセットアップ開始 ===\n');

  // ── Step 1: プロフィール写真アップロード ─────────────────────────
  console.log('【Step 1】プロフィール写真アップロード');
  const profilePhotoUrls = [];
  for (let i = 0; i < PROFILE_PHOTO_FILES.length; i++) {
    const fileName = PROFILE_PHOTO_FILES[i];
    const localPath = path.join(PROFILE_PHOTOS_DIR, fileName);
    const storagePath = `profile_images/dummy_user_0${i + 1}/profile.jpg`;
    const url = await uploadFile(localPath, storagePath);
    profilePhotoUrls.push(url);
  }
  console.log(`  プロフィール写真: ${profilePhotoUrls.length}枚\n`);

  // ── Step 2: 投稿用写真アップロード ───────────────────────────────
  console.log('【Step 2】投稿用写真アップロード');
  const postPhotoFiles = fs.readdirSync(POST_PHOTOS_DIR)
    .filter(f => f.endsWith('.jpg') || f.endsWith('.jpeg') || f.endsWith('.png'))
    .sort();

  const postPhotoUrls = [];
  for (const fileName of postPhotoFiles) {
    const localPath = path.join(POST_PHOTOS_DIR, fileName);
    const safeName = fileName.replace(/[^\x00-\x7F]/g, '_');
    const storagePath = `dummy_post_photos/${safeName}`;
    const url = await uploadFile(localPath, storagePath);
    postPhotoUrls.push(url);
  }
  console.log(`  投稿用写真: ${postPhotoUrls.length}枚\n`);

  // ── Step 3: iTunes API でトラック情報取得 ────────────────────────
  console.log('【Step 3】iTunes API からトラック情報取得');

  // 既存チェック
  const tracksDoc = await db.doc('dummy_config/tracks').get();
  let tracks = [];
  if (tracksDoc.exists && (tracksDoc.data().list || []).length > 0) {
    tracks = tracksDoc.data().list;
    console.log(`  ↩ Skip (already saved): ${tracks.length}件\n`);
  } else {
    for (const query of TRACK_SEARCH_QUERIES) {
      process.stdout.write(`  Searching: "${query}" ... `);
      const track = await searchTrack(query);
      if (track) {
        tracks.push(track);
        console.log(`✓ ${track.trackName} - ${track.artistName}`);
      } else {
        console.log('× not found');
      }
      await sleep(1100); // rate limit
    }

    await db.doc('dummy_config/tracks').set({
      list: tracks,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`  トラック: ${tracks.length}件 保存完了\n`);
  }

  // ── Step 4: dummy_config に URL リスト保存 ────────────────────────
  console.log('【Step 4】dummy_config/photos に URL 保存');
  await db.doc('dummy_config/photos').set({
    postPhotoUrls,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`  postPhotoUrls: ${postPhotoUrls.length}件\n`);

  // ── Step 5: ユーザードキュメント作成 ─────────────────────────────
  console.log('【Step 5】Firestore ユーザードキュメント作成');
  const userIds = [];
  for (let i = 0; i < DUMMY_USERS.length; i++) {
    const u = DUMMY_USERS[i];
    const docRef = db.collection('users').doc(u.id);
    const snapshot = await docRef.get();

    const profileImageUrl = u.photoFileIndex !== null
      ? profilePhotoUrls[u.photoFileIndex]
      : null;

    if (snapshot.exists) {
      // プロフィール写真 URL のみ更新
      await docRef.update({
        profileImageUrl,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`  ↻ Updated: ${u.id} (${u.username})`);
    } else {
      await docRef.set({
        uid: u.id,
        phoneNumber: `+8100000000${String(i + 1).padStart(2, '0')}`,
        name: u.name,
        username: u.username,
        profileImageUrl,
        bio: '',
        university: u.university,
        followers: [],
        following: [],
        savedPosts: [],
        postsCount: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        isAdmin: false,
        isDummy: true,
      });
      console.log(`  ✓ Created: ${u.id} (${u.username})`);
    }
    userIds.push(u.id);
  }

  // dummy_config/users にIDリストを保存
  await db.doc('dummy_config/users').set({
    userIds,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`\n  dummy_config/users 保存: ${userIds.length}人\n`);

  console.log('=== セットアップ完了 ===');
  console.log('次のステップ: functions/index.js の dailyDummyUserPosts が自動的に毎日投稿します。');
  process.exit(0);
}

main().catch(err => {
  console.error('エラー:', err);
  process.exit(1);
});
