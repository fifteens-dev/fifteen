/**
 * Spotify の再生履歴 API がどこまで遡れるかを実際に叩いて確かめる
 *
 * `GET /v1/me/player/recently-played` は Apple Music と違って offset が使えず、
 * before / after のカーソル方式。どこまで取れるかは実測しないと分からないので、
 * 上限と遡り可否をまとめて確認する。
 *
 * .env の SPOTIFY_REFRESH_TOKEN を使う（アプリの認証とは別に取ったもの）。
 * 別アカウントで試したいときは scripts/spotify_oauth.js で取り直す
 * （Development Mode 中は Spotify ダッシュボードの許可リストに
 *  そのアカウントを追加しておく必要がある）。
 *
 * 実行:
 *   cd scripts && node spotify_recent_test.js
 */
const fs = require('fs');
const path = require('path');

const env = {};
for (const line of fs
  .readFileSync(path.join(__dirname, '..', '.env'), 'utf8')
  .split('\n')) {
  const m = line.match(/^([^#=]+)=(.*)$/);
  if (m) env[m[1].trim()] = m[2].trim();
}

const ENDPOINT = 'https://api.spotify.com/v1/me/player/recently-played';

async function accessToken() {
  const basic = Buffer.from(
    `${env.SPOTIFY_CLIENT_ID}:${env.SPOTIFY_CLIENT_SECRET}`
  ).toString('base64');
  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: {
      Authorization: 'Basic ' + basic,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: env.SPOTIFY_REFRESH_TOKEN,
    }),
  });
  const data = await res.json();
  if (!data.access_token) {
    throw new Error(`トークン更新に失敗: ${data.error} ${data.error_description || ''}`);
  }
  return data;
}

async function main() {
  const token = await accessToken();
  console.log('スコープ:', token.scope || '(なし)');

  const get = async (url) => {
    const r = await fetch(url, {
      headers: { Authorization: 'Bearer ' + token.access_token },
    });
    return {
      status: r.status,
      body: r.status === 200 ? await r.json() : await r.text(),
    };
  };

  console.log('\n── limit の上限 ──');
  for (const n of [50, 51]) {
    const r = await get(`${ENDPOINT}?limit=${n}`);
    console.log(
      `limit=${n} -> HTTP ${r.status}` +
        (r.status === 200
          ? ` / ${r.body.items.length} 件`
          : ` / ${String(r.body).replace(/\s+/g, ' ').slice(0, 100)}`)
    );
  }

  console.log('\n── next を辿ってどこまで遡れるか ──');
  const all = [];
  let url = `${ENDPOINT}?limit=50`;
  for (let page = 1; page <= 5 && url; page++) {
    const r = await get(url);
    if (r.status !== 200) {
      console.log(`ページ${page}: HTTP ${r.status}`);
      break;
    }
    const items = r.body.items;
    console.log(
      `ページ${page}: ${items.length} 件` +
        (items.length
          ? `  ${items.at(-1).played_at} 〜 ${items[0].played_at}`
          : '')
    );
    all.push(...items);
    if (items.length === 0) break;
    url = r.body.next;
  }

  if (all.length) {
    const ids = all.map((i) => i.track.id);
    const hours =
      (new Date(all[0].played_at) - new Date(all.at(-1).played_at)) / 3600000;
    console.log(
      `\n合計 ${ids.length} 件 / 曲の種類 ${new Set(ids).size} / カバー約 ${hours.toFixed(1)} 時間`
    );
    console.log(
      ids.length > new Set(ids).size
        ? '→ 同じ曲が複数回入っている（再生順）'
        : '→ 重複なし'
    );
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
