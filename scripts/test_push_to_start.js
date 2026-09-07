/**
 * Live Activity の push-to-start を手動で 1 発送るテスト
 *
 * 「サーバは APNs に受理されているのに端末に出ない」を切り分けるためのもの。
 * 実行後にロック画面へ出れば、トークンも仕組みも生きている。出なければ
 * トークンが古い（アプリを閉じている間に更新された）か、アプリが強制終了されている。
 *
 * 実行:
 *   cd scripts && node test_push_to_start.js            # 対象一覧を表示するだけ
 *   cd scripts && node test_push_to_start.js --send     # 全員に送る
 *   cd scripts && node test_push_to_start.js --send --uid <UID>   # 1人だけに送る
 *
 * APNs の応答（200 / 400 BadDeviceToken など）をそのまま表示する。
 */
const path = require('path');
const admin = require('firebase-admin');
const serviceAccount = require('../functions/fifteens-39cfe-firebase-adminsdk-fbsvc-dc5aa33fe8.json');

// functions/.env の APNS_* を読み込む（apns.js が process.env を見るため）
const fs = require('fs');
const envPath = path.join(__dirname, '..', 'functions', '.env');
for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (!m) continue;
  let v = m[2];
  if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1);
  process.env[m[1]] = v;
}
const apns = require('../functions/apns');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const send = process.argv.includes('--send');
const uidIdx = process.argv.indexOf('--uid');
const onlyUid = uidIdx >= 0 ? process.argv[uidIdx + 1] : null;

/** 通知時刻に対する締切（JST 翌 01:00）。functions/index.js と同じ計算。 */
function deadlineFor(cycleStart) {
  const o = 9 * 60 * 60 * 1000;
  const j = new Date(cycleStart.getTime() + o);
  const dayStart = new Date(Date.UTC(j.getUTCFullYear(), j.getUTCMonth(), j.getUTCDate()) - o);
  return new Date(dayStart.getTime() + 25 * 60 * 60 * 1000);
}

const jst = (d) => (d ? new Date(d.getTime() + 9 * 3600 * 1000).toISOString().replace('T', ' ').slice(0, 19) : '-');

async function main() {
  console.log('APNS_ENV:', process.env.APNS_ENV, '/ configured:', apns.isConfigured());

  const snap = await db.collection('users').get();
  const targets = [];
  for (const d of snap.docs) {
    const token = d.data().liveActivityPushToStartToken;
    if (!token) continue;
    if (onlyUid && d.id !== onlyUid) continue;
    targets.push({
      uid: d.id,
      name: d.data().name || d.data().username || '(名前なし)',
      token,
      at: d.data().liveActivityTokenUpdatedAt?.toDate?.(),
    });
  }

  console.log(`\n対象: ${targets.length} 人`);
  targets.forEach((t) =>
    console.log(`  ${t.uid}  ${t.name}  トークン更新: ${jst(t.at)} JST`)
  );

  if (!send) {
    console.log('\n--send が無いため送信しませんでした。');
    return;
  }

  // 「今」を通知時刻とみなして開始する（本番と同じ形の content-state）。
  const now = new Date();
  const deadline = deadlineFor(now);
  const attributes = { cycleStartEpoch: Math.floor(now.getTime() / 1000) };
  const contentState = {
    phase: 'waiting',
    deadlineEpoch: Math.floor(deadline.getTime() / 1000),
    revision: Math.floor(Date.now() / 1000),
  };
  console.log(`\ncycleStart: ${jst(now)} JST / deadline: ${jst(deadline)} JST`);

  for (const t of targets) {
    const res = await apns.startLiveActivity(t.token, attributes, contentState, {
      staleEpoch: Math.floor(deadline.getTime() / 1000),
      // push-to-start は event:"start" のとき alert が必要と思われる。
      // --no-alert を付けると alert 無しで送り、必須かどうかを切り分けられる。
      alert: process.argv.includes('--no-alert')
        ? undefined
        : {
            title: '🎵 Music Memoryの時間です。',
            body: '25:00までに投稿すると、友達の今日が見られます。',
          },
    });
    console.log(
      `  ${t.name} (${t.uid.slice(0, 8)}…) → status=${res.status} ok=${res.ok}` +
        (res.reason ? ` reason=${res.reason}` : '')
    );
  }
  console.log('\nロック画面を確認してください。出なければトークンが古いか、アプリが強制終了されています。');
}

main()
  .then(() => process.exit(0))
  .catch((e) => { console.error(e); process.exit(1); });
