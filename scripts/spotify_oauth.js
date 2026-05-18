/**
 * Spotify OAuth認証スクリプト（一度だけ実行）
 * 使い方: cd scripts && node spotify_oauth.js
 */

const http = require('http');
const fs   = require('fs');
const path = require('path');

function loadEnv(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    const env = {};
    content.split('\n').forEach(line => {
      const m = line.match(/^([^#=]+)=(.*)$/);
      if (m) env[m[1].trim()] = m[2].trim();
    });
    return env;
  } catch { return {}; }
}

function updateEnvFile(filePath, key, value) {
  let content = '';
  try { content = fs.readFileSync(filePath, 'utf8'); } catch {}
  const lines = content.split('\n').filter(l => !l.startsWith(key + '='));
  lines.push(`${key}=${value}`);
  fs.writeFileSync(filePath, lines.filter(l => l !== '').join('\n') + '\n');
}

const rootEnvPath      = path.join(__dirname, '../.env');
const functionsEnvPath = path.join(__dirname, '../functions/.env');
const env = loadEnv(rootEnvPath);

const CLIENT_ID     = env.SPOTIFY_CLIENT_ID;
const CLIENT_SECRET = env.SPOTIFY_CLIENT_SECRET;
const REDIRECT_URI  = 'http://127.0.0.1:3000/callback';
const SCOPE         = 'playlist-read-private';

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error('.env に SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET が見つかりません');
  process.exit(1);
}

const authUrl = 'https://accounts.spotify.com/authorize?' + new URLSearchParams({
  client_id:     CLIENT_ID,
  response_type: 'code',
  redirect_uri:  REDIRECT_URI,
  scope:         SCOPE,
});

console.log('\n以下のURLをブラウザで開いてください:\n');
console.log(authUrl);
console.log('\n（macOSは自動的にブラウザを開きます）\n');

const { exec } = require('child_process');
exec(`open "${authUrl}"`);

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1:3000');
  if (url.pathname !== '/callback') return;

  const code  = url.searchParams.get('code');
  const error = url.searchParams.get('error');

  if (error || !code) {
    res.end('認証エラー: ' + (error || '不明'));
    console.error('認証エラー:', error);
    server.close();
    process.exit(1);
  }

  try {
    const tokenRes = await fetch('https://accounts.spotify.com/api/token', {
      method: 'POST',
      headers: {
        'Authorization': 'Basic ' + Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString('base64'),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type:   'authorization_code',
        code,
        redirect_uri: REDIRECT_URI,
      }),
    });
    const data = await tokenRes.json();

    if (!data.refresh_token) {
      res.end('トークン取得失敗: ' + JSON.stringify(data));
      console.error('トークン取得失敗:', data);
      server.close();
      process.exit(1);
    }

    updateEnvFile(rootEnvPath,      'SPOTIFY_REFRESH_TOKEN', data.refresh_token);
    updateEnvFile(functionsEnvPath, 'SPOTIFY_REFRESH_TOKEN', data.refresh_token);

    res.end('<h2>認証成功！ターミナルを確認してください。</h2>');
    console.log('\n✓ 認証成功！SPOTIFY_REFRESH_TOKEN を .env と functions/.env に保存しました。');
    console.log('このウィンドウを閉じて構いません。\n');
    server.close();
    process.exit(0);
  } catch (e) {
    res.end('エラー: ' + e.message);
    console.error(e);
    server.close();
    process.exit(1);
  }
});

server.listen(3000, '127.0.0.1', () => {
  console.log('localhost:3000 で待機中...');
});
