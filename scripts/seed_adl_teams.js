/**
 * ADL 9班 シードスクリプト
 *
 * 実行方法:
 *   cd scripts && node seed_adl_teams.js [eventId]
 *
 * 引数:
 *   eventId  ... 紐付ける adl_events の ID（省略時は eventId フィールドを空文字で作成）
 *
 * 処理内容（冪等）:
 * 1. users/{teamId} に班アカウントを upsert（既存値は保持）
 * 2. adl_teams/{teamId} に班統計を upsert（likeCount/memberCount/followers は初回のみ初期化）
 *
 * 9班: adl_house, adl_break, adl_girls, adl_hiphop, adl_new,
 *      adl_free, adl_lock, adl_waack, adl_jazz
 *
 * 班ID = 招待コード = 班アカウントUID = username（すべて同一文字列）
 */

const admin = require('firebase-admin');
const path = require('path');

const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const TEAMS = [
  { id: 'adl_house',  displayName: 'House' },
  { id: 'adl_break',  displayName: 'Break' },
  { id: 'adl_girls',  displayName: 'Girls' },
  { id: 'adl_hiphop', displayName: 'HipHop' },
  { id: 'adl_new',    displayName: 'New' },
  { id: 'adl_free',   displayName: 'Free' },
  { id: 'adl_lock',   displayName: 'Lock' },
  { id: 'adl_waack',  displayName: 'Waack' },
  { id: 'adl_jazz',   displayName: 'Jazz' },
];

async function seed(eventId) {
  console.log(`Seeding ${TEAMS.length} ADL teams (eventId="${eventId || ''}")...`);

  for (const t of TEAMS) {
    const userRef = db.collection('users').doc(t.id);
    const teamRef = db.collection('adl_teams').doc(t.id);

    // ── 1. 班アカウント (users/{teamId}) ──
    // 既存ドキュメントがあれば followers/following/postsCount などは保持する。
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      await userRef.set({
        uid: t.id,
        phoneNumber: '',
        name: t.displayName,
        username: t.id,
        bio: `ADL ${t.displayName} 班の公式アカウント`,
        profileImageUrl: null,
        followers: [],
        following: [],
        savedPosts: [],
        savedPostsAt: {},
        savedTracksData: {},
        postsCount: 0,
        isAdmin: false,
        isTeamAccount: true,
        adlTeamId: t.id,
        adlTeamName: t.displayName,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      console.log(`  + created user/${t.id}`);
    } else {
      // 班アカウントとして識別するためのフラグだけは確実にセットする。
      await userRef.update({
        isTeamAccount: true,
        adlTeamId: t.id,
        adlTeamName: t.displayName,
        username: t.id,
        updatedAt: FieldValue.serverTimestamp(),
      });
      console.log(`  ~ updated user/${t.id} (kept followers/following)`);
    }

    // ── 2. 班統計 (adl_teams/{teamId}) ──
    const teamSnap = await teamRef.get();
    if (!teamSnap.exists) {
      await teamRef.set({
        teamId: t.id,
        eventId: eventId || '',
        name: t.displayName,
        inviteCode: t.id,
        // 招待コードは無期限（=固定）として、十分先の日時にする
        inviteCodeExpiresAt: admin.firestore.Timestamp.fromDate(
          new Date('2099-12-31T23:59:59Z'),
        ),
        likeCount: 0,
        memberCount: 0,
        teamAccountUid: t.id,
        createdAt: FieldValue.serverTimestamp(),
      });
      console.log(`  + created adl_teams/${t.id}`);
    } else {
      // 既存班の場合、eventId だけ更新する（likeCount/memberCount は維持）
      const update = {
        name: t.displayName,
        inviteCode: t.id,
        teamAccountUid: t.id,
      };
      if (eventId) update.eventId = eventId;
      await teamRef.update(update);
      console.log(`  ~ updated adl_teams/${t.id} (kept stats)`);
    }
  }

  console.log('Done.');
}

const eventId = process.argv[2] || '';
seed(eventId).then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
