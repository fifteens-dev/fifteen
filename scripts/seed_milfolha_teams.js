/**
 * Milfolha 8チーム シードスクリプト（班アカウント作成）
 *
 * 実行方法:
 *   cd scripts && node seed_milfolha_teams.js
 *
 * 処理内容（冪等）:
 * 1. users/{teamId} にチームアカウントを upsert（既存の followers/following は保持）
 * 2. milfolha_teams/{teamId} に班統計/プロフィールを upsert（memberCount は初回のみ 0 初期化）
 *
 * 8チーム: waterfalls_a 〜 waterfalls_h（表示名 A〜H）
 * チームID = 招待コード = チームアカウントUID = username（すべて同一文字列）
 */

const admin = require('firebase-admin');

const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const TEAMS = [
  { id: 'waterfalls_a', displayName: 'A' },
  { id: 'waterfalls_b', displayName: 'B' },
  { id: 'waterfalls_c', displayName: 'C' },
  { id: 'waterfalls_d', displayName: 'D' },
  { id: 'waterfalls_e', displayName: 'E' },
  { id: 'waterfalls_f', displayName: 'F' },
  { id: 'waterfalls_g', displayName: 'G' },
  { id: 'waterfalls_h', displayName: 'H' },
];

async function seed() {
  console.log(`Seeding ${TEAMS.length} Milfolha teams...`);

  for (const t of TEAMS) {
    const userRef = db.collection('users').doc(t.id);
    const teamRef = db.collection('milfolha_teams').doc(t.id);

    // ── 1. チームアカウント (users/{teamId}) ──
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      await userRef.set({
        uid: t.id,
        phoneNumber: '',
        name: `${t.displayName}チーム`,
        username: t.id,
        bio: `Milfolha ${t.displayName}チームの公式アカウント`,
        profileImageUrl: null,
        followers: [],
        following: [],
        savedPosts: [],
        savedPostsAt: {},
        savedTracksData: {},
        postsCount: 0,
        isAdmin: false,
        isTeamAccount: true,
        milfolhaTeamId: t.id,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      console.log(`  + created users/${t.id}`);
    } else {
      await userRef.update({
        isTeamAccount: true,
        milfolhaTeamId: t.id,
        username: t.id,
        updatedAt: FieldValue.serverTimestamp(),
      });
      console.log(`  ~ updated users/${t.id} (kept followers/following)`);
    }

    // ── 2. 班統計/プロフィール (milfolha_teams/{teamId}) ──
    const teamSnap = await teamRef.get();
    if (!teamSnap.exists) {
      await teamRef.set({
        teamId: t.id,
        name: t.displayName,
        profileImageUrl: null,
        description: null,
        memberCount: 0,
        createdAt: FieldValue.serverTimestamp(),
      });
      console.log(`  + created milfolha_teams/${t.id}`);
    } else {
      await teamRef.update({ name: t.displayName });
      console.log(`  ~ updated milfolha_teams/${t.id} (kept stats)`);
    }
  }

  console.log('Done.');
}

seed().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
