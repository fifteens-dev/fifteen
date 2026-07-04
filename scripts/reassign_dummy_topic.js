/**
 * 既存の誤割り当てダミー投稿を「今日(JST)のVibeトピック」に付け替えるスクリプト
 *
 * 実行: cd scripts && node reassign_dummy_topic.js
 *
 * 処理:
 * 1. 今日(JST)のactiveな汎用Vibeトピックを取得
 * 2. dummy_config/users のUIDから過去3日以内のダミー投稿を取得
 * 3. その投稿の vibeTopicId/Title/vibeDate を今日のトピックに付け替える
 *    （ただし「すでに今日のトピックに紐付いている」投稿は変更しない）
 *
 * 安全策:
 * - 投稿者は10ダミーUIDのみを対象（人間投稿には触らない）
 * - createdAt が過去3日以内のものに限定
 * - dry-run モード（--dry）あり
 */

const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const DRY_RUN = process.argv.includes('--dry');

function jstDayStartFor(utcDate) {
  const jstOffsetMs = 9 * 60 * 60 * 1000;
  const jstTs = new Date(utcDate.getTime() + jstOffsetMs);
  const jstDayUtcMs = Date.UTC(
    jstTs.getUTCFullYear(), jstTs.getUTCMonth(), jstTs.getUTCDate()
  );
  return new Date(jstDayUtcMs - jstOffsetMs);
}

async function findTodayActiveVibeTopic() {
  const todayStart = jstDayStartFor(new Date());
  const todayEnd = new Date(todayStart.getTime() + 24 * 3600 * 1000);
  const snap = await db.collection('vibe_topics')
    .where('status', '==', 'active')
    .get();
  for (const doc of snap.docs) {
    const data = doc.data();
    const d = data.date?.toDate?.();
    if (!d) continue;
    if (d < todayStart || d >= todayEnd) continue;
    if (data.isAdlOnly === true) continue;
    return { id: doc.id, ...data, dateObj: d };
  }
  return null;
}

async function main() {
  console.log(`=== ダミー投稿の付け替え${DRY_RUN ? '（DRY-RUN）' : ''} ===\n`);

  // ── Step 1: 今日のトピック取得 ──────────────────────────────────
  const today = await findTodayActiveVibeTopic();
  if (!today) {
    console.error('❌ 今日(JST)のactive Vibeトピックが見つかりません');
    process.exit(1);
  }
  const todayStart = jstDayStartFor(new Date());
  console.log(`今日のトピック: "${today.title}" (${today.id})`);
  console.log(`  date(JST 0:00): ${todayStart.toISOString()} 相当`);

  // ── Step 2: ダミーUID取得 ──────────────────────────────────────
  const usersSnap = await db.doc('dummy_config/users').get();
  const dummyUids = usersSnap.data()?.userIds || [];
  console.log(`\nダミーユーザー: ${dummyUids.length}人`);

  // ── Step 3: 過去3日のダミー投稿を取得 ─────────────────────────
  // 複合インデックス回避のため userId in でだけ絞り、createdAt はメモリでフィルタ
  const cutoffTs = new Date(Date.now() - 3 * 24 * 3600 * 1000);
  const allPosts = [];
  for (let i = 0; i < dummyUids.length; i += 30) {
    const batch = dummyUids.slice(i, i + 30);
    const snap = await db.collection('posts')
      .where('userId', 'in', batch)
      .get();
    for (const doc of snap.docs) {
      const created = doc.data().createdAt?.toDate?.();
      if (created && created >= cutoffTs) {
        allPosts.push(doc);
      }
    }
  }
  console.log(`\n過去3日のダミー投稿: ${allPosts.length}件`);

  // ── Step 4: 付け替え対象を絞る ──────────────────────────────────
  const toUpdate = allPosts.filter(doc => {
    const d = doc.data();
    return d.vibeTopicId !== today.id;
  });
  console.log(`うち付け替え必要: ${toUpdate.length}件（既に今日のトピックの ${allPosts.length - toUpdate.length}件はスキップ）`);

  if (toUpdate.length === 0) {
    console.log('\n✅ 何もする必要がありません');
    process.exit(0);
  }

  // ── Step 5: 一覧表示 ──────────────────────────────────────────
  console.log('\n=== 付け替え対象（先頭10件） ===');
  for (const doc of toUpdate.slice(0, 10)) {
    const d = doc.data();
    const createdJst = new Date(d.createdAt.toDate().getTime() + 9 * 3600 * 1000);
    console.log(`  ${doc.id} (${d.username || d.userId}) createdAt=${createdJst.toISOString().slice(0, 16)} JST`);
    console.log(`    現在: topicId=${d.vibeTopicId} title="${d.vibeTopicTitle}"`);
  }
  if (toUpdate.length > 10) console.log(`  ... 他 ${toUpdate.length - 10}件`);

  if (DRY_RUN) {
    console.log('\n🔍 DRY-RUN なので書き込みはしません。--dry を外して本実行してください。');
    process.exit(0);
  }

  // ── Step 6: バッチ書き込み ──────────────────────────────────────
  console.log('\n書き込み中...');
  const newVibeDate = admin.firestore.Timestamp.fromDate(jstDayStartFor(new Date()));
  let batch = db.batch();
  let ops = 0;
  const promises = [];
  for (const doc of toUpdate) {
    batch.update(doc.ref, {
      vibeTopicId:    today.id,
      vibeTopicTitle: today.title,
      vibeDate:       newVibeDate,
      isVibe:         true,
    });
    ops++;
    if (ops >= 400) {
      promises.push(batch.commit());
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) promises.push(batch.commit());
  await Promise.all(promises);

  console.log(`\n✅ ${toUpdate.length}件を付け替えました`);
  console.log('   vibeTopicPostAggregation トリガーが反応して vibe_topics.postCount も更新されます');
  process.exit(0);
}

main().catch(e => { console.error('Error:', e); process.exit(1); });
