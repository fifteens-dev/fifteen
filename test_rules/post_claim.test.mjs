/**
 * 「1 サイクル 1 投稿」をルールで止められているかの検証。
 *
 * クライアントを書き換えれば 2 投稿目を送れてしまうので、ここが最後の砦。
 * 止めすぎて誰も投稿できなくなる方が害が大きいので、通すべき場合も
 * 同じだけ確かめる。
 *
 *   実行: cd test_rules && npx firebase emulators:exec --only firestore \
 *           --project fifteens-39cfe "node post_claim.test.mjs"
 */
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, writeBatch } from 'firebase/firestore';
import { readFileSync } from 'node:fs';

const CYCLE = '2026-10-11';
let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    await fn();
    console.log(`  OK   ${name}`);
    passed++;
  } catch (e) {
    console.log(`  NG   ${name}`);
    console.log(`       ${String(e).split('\n')[0]}`);
    failed++;
  }
}

const env = await initializeTestEnvironment({
  projectId: 'fifteens-39cfe',
  firestore: {
    rules: readFileSync('../firestore.rules', 'utf8'),
    host: '127.0.0.1',
    port: 8080,
  },
});

/** ルールを通さずに下ごしらえする。 */
async function seed(cycleKey, { admin = [] } = {}) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'music_memory_state/current'),
      cycleKey === null ? {} : { lastNotifiedDate: cycleKey });
    for (const uid of admin) {
      await setDoc(doc(db, `users/${uid}`), { isAdmin: true });
    }
  });
}

/** 投稿 + 引換券を 1 つのバッチで書く（アプリと同じ形）。 */
function postWithClaim(db, uid, postId, cycleKey, extra = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, `posts/${postId}`),
    { userId: uid, isMoodPost: true, ...extra });
  batch.set(doc(db, `post_claims/${uid}_${cycleKey}`),
    { userId: uid, postId });
  return batch.commit();
}

const alice = () => env.authenticatedContext('alice').firestore();
const admin = () => env.authenticatedContext('boss').firestore();

console.log('\n1 サイクル 1 投稿（Firestore ルール）\n');

await seed(CYCLE);
await check('1 回目の投稿は通る', () =>
  assertSucceeds(postWithClaim(alice(), 'alice', 'p1', CYCLE)));

await check('同じサイクルの 2 回目は止まる', () =>
  assertFails(postWithClaim(alice(), 'alice', 'p2', CYCLE)));

await check('引換券を取らずに投稿だけ送っても止まる', () =>
  assertFails(setDoc(doc(alice(), 'posts/p3'),
    { userId: 'alice', isMoodPost: true })));

await check('取った券は書き換えられない', () =>
  assertFails(setDoc(doc(alice(), `post_claims/alice_${CYCLE}`),
    { userId: 'alice', postId: 'p9' })));

await check('他人の券は取れない', () =>
  assertFails(setDoc(doc(alice(), `post_claims/bob_${CYCLE}`),
    { userId: 'bob', postId: 'p9' })));

await check('サイクルの鍵が違う券では投稿を通せない', () =>
  assertFails(postWithClaim(alice(), 'alice', 'p4', '2026-01-01')));

await seed(CYCLE);
await check('別の人は同じサイクルでも投稿できる', async () => {
  await assertSucceeds(postWithClaim(alice(), 'alice', 'p5', CYCLE));
  const bob = env.authenticatedContext('bob').firestore();
  await assertSucceeds(postWithClaim(bob, 'bob', 'p6', CYCLE));
});

await check('サイクルが変われば、また投稿できる', () =>
  assertSucceeds(postWithClaim(alice(), 'alice', 'p7', CYCLE)
    .then(() => env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'music_memory_state/current'),
        { lastNotifiedDate: '2026-10-12' });
    }))
    .then(() => postWithClaim(alice(), 'alice', 'p8', '2026-10-12'))));

await seed(CYCLE);
await check('Music Memory 以外の投稿（Vibe）は制限しない', async () => {
  const db = alice();
  await assertSucceeds(setDoc(doc(db, 'posts/v1'),
    { userId: 'alice', isMoodPost: false }));
  await assertSucceeds(setDoc(doc(db, 'posts/v2'),
    { userId: 'alice', isMoodPost: false }));
});

await seed(CYCLE, { admin: ['boss'] });
await check('管理者は券なしで何度でも投稿できる', async () => {
  const db = admin();
  await assertSucceeds(setDoc(doc(db, 'posts/a1'),
    { userId: 'boss', isMoodPost: true }));
  await assertSucceeds(setDoc(doc(db, 'posts/a2'),
    { userId: 'boss', isMoodPost: true }));
});

await seed(null);
await check('通知がまだ一度も発火していなければ制限しない', async () => {
  const db = alice();
  await assertSucceeds(setDoc(doc(db, 'posts/n1'),
    { userId: 'alice', isMoodPost: true }));
  await assertSucceeds(setDoc(doc(db, 'posts/n2'),
    { userId: 'alice', isMoodPost: true }));
});

await seed(CYCLE);
await check('他人になりすました投稿は止まる', () =>
  assertFails(postWithClaim(alice(), 'bob', 'x1', CYCLE)));

await env.cleanup();
console.log(`\n  通過 ${passed} / 失敗 ${failed}\n`);
process.exit(failed === 0 ? 0 : 1);
