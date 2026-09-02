/**
 * APNs（Apple Push Notification service）へ HTTP/2 で直接送るクライアント。
 *
 * Live Activity の更新 / push-to-start は FCM 経由では送れず、APNs の
 * `apns-push-type: liveactivity` を自分で叩く必要があるためここに実装する。
 *
 * 必要な環境変数（functions/.env）:
 *   APNS_TEAM_ID     … Apple Developer の Team ID（10文字）
 *   APNS_KEY_ID      … APNs 認証キー(.p8)の Key ID（10文字）
 *   APNS_PRIVATE_KEY … .p8 の中身（PEM。改行は \n エスケープ可）
 *   APNS_BUNDLE_ID   … 省略時 com.fifteens.sns
 *   APNS_ENV         … 'production'(既定) | 'sandbox'（開発ビルド用）
 */

const http2 = require('http2');
const crypto = require('crypto');

const DEFAULT_BUNDLE_ID = 'com.fifteens.sns';
/** Live Activity 用の topic は必ず `<bundleId>.push-type.liveactivity`。 */
const LIVE_ACTIVITY_TOPIC_SUFFIX = '.push-type.liveactivity';
/** Live Activity の attributes 型名。Swift の型名と完全一致させること。 */
const ATTRIBUTES_TYPE = 'MusicMemoryActivityAttributes';

/** JWT は Apple の仕様上 1 時間まで使い回せる（20分ごとに作り直す）。 */
let cachedJwt = null;
let cachedJwtAt = 0;

function bundleId() {
  return process.env.APNS_BUNDLE_ID || DEFAULT_BUNDLE_ID;
}

const PROD_HOST = 'https://api.push.apple.com';
const SANDBOX_HOST = 'https://api.sandbox.push.apple.com';

/** APNS_ENV で指定された既定のホスト。 */
function apnsHost() {
  return process.env.APNS_ENV === 'sandbox' ? SANDBOX_HOST : PROD_HOST;
}

/** APNs の認証情報が揃っているか。未設定なら送信系は静かに no-op にする。 */
function isConfigured() {
  return Boolean(
    process.env.APNS_TEAM_ID &&
      process.env.APNS_KEY_ID &&
      process.env.APNS_PRIVATE_KEY
  );
}

/** ES256 で APNs プロバイダ JWT を作る（Apple Music トークンと同じ手順）。 */
function providerToken() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwtAt < 20 * 60) return cachedJwt;

  const teamId = process.env.APNS_TEAM_ID;
  const keyId = process.env.APNS_KEY_ID;
  const pem = process.env.APNS_PRIVATE_KEY.replace(/\\n/g, '\n');

  const b64url = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const signingInput =
    `${b64url({ alg: 'ES256', kid: keyId })}.${b64url({ iss: teamId, iat: now })}`;
  const signature = crypto
    .sign('sha256', Buffer.from(signingInput), {
      key: pem,
      dsaEncoding: 'ieee-p1363', // JOSE 形式（r||s, 64byte）
    })
    .toString('base64url');

  cachedJwt = `${signingInput}.${signature}`;
  cachedJwtAt = now;
  return cachedJwt;
}

/**
 * APNs に 1 通送る。
 * @returns {Promise<{ok: boolean, status: number, reason?: string}>}
 */
function sendTo(host, deviceToken, payload, { priority = 10, expiration = 0 } = {}) {
  return new Promise((resolve) => {
    let client;
    try {
      client = http2.connect(host);
    } catch (e) {
      resolve({ ok: false, status: 0, reason: `connect: ${e.message}` });
      return;
    }

    const body = Buffer.from(JSON.stringify(payload));
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${providerToken()}`,
      'apns-topic': `${bundleId()}${LIVE_ACTIVITY_TOPIC_SUFFIX}`,
      'apns-push-type': 'liveactivity',
      'apns-priority': String(priority),
      'apns-expiration': String(expiration),
      'content-type': 'application/json',
      'content-length': body.length,
    });

    let status = 0;
    let data = '';
    const finish = (result) => {
      try { client.close(); } catch (_) { /* noop */ }
      resolve(result);
    };

    req.setTimeout(10000, () => {
      req.close();
      finish({ ok: false, status: 0, reason: 'timeout' });
    });
    req.on('response', (headers) => { status = headers[':status']; });
    req.on('data', (chunk) => { data += chunk; });
    req.on('error', (e) => finish({ ok: false, status: 0, reason: e.message }));
    req.on('end', () => {
      if (status === 200) return finish({ ok: true, status });
      let reason = data;
      try { reason = JSON.parse(data).reason || data; } catch (_) { /* noop */ }
      finish({ ok: false, status, reason });
    });

    req.write(body);
    req.end();
  });
}

/**
 * APNs へ送る。`BadDeviceToken`（＝トークンの環境違い）なら、もう一方の環境へ
 * 1 回だけ投げ直す。
 *
 * Xcode から実機に入れた開発ビルドは sandbox、TestFlight / App Store 配信は
 * production のトークンを持つ。検証中は両方の端末が混在するため、
 * APNS_ENV の設定ミスや端末差でサイレントに失敗しないようフォールバックする。
 */
async function send(deviceToken, payload, opts = {}) {
  const primary = apnsHost();
  const res = await sendTo(primary, deviceToken, payload, opts);
  if (res.ok || res.reason !== 'BadDeviceToken') return res;

  const fallback = primary === PROD_HOST ? SANDBOX_HOST : PROD_HOST;
  const retry = await sendTo(fallback, deviceToken, payload, opts);
  if (retry.ok) {
    console.log(
      `apns: ${primary} が BadDeviceToken のため ${fallback} で成功。` +
        'APNS_ENV の見直しを検討してください。'
    );
  }
  return retry;
}

/**
 * 既に表示中の Live Activity を更新する（フェーズの差し替え）。
 * @param {string} updateToken Activity ごとの push token（16進文字列）
 * @param {{phase: string, deadlineEpoch: number, revision: number}} contentState
 * @param {{staleEpoch?: number, dismissEpoch?: number}} opts
 */
async function updateLiveActivity(updateToken, contentState, opts = {}) {
  if (!isConfigured()) return { ok: false, status: 0, reason: 'apns-not-configured' };
  const aps = {
    timestamp: Math.floor(Date.now() / 1000),
    event: 'update',
    'content-state': contentState,
  };
  if (opts.staleEpoch) aps['stale-date'] = Math.floor(opts.staleEpoch);
  if (opts.dismissEpoch) aps['dismissal-date'] = Math.floor(opts.dismissEpoch);
  return send(updateToken, { aps }, { expiration: Math.floor(opts.staleEpoch || 0) });
}

/**
 * push-to-start（iOS 17.2+）。通知と同時にロック画面へ Live Activity を出す。
 * @param {string} pushToStartToken users/{uid}.liveActivityPushToStartToken
 * @param {{cycleStartEpoch: number}} attributes
 * @param {{phase: string, deadlineEpoch: number, revision: number}} contentState
 */
async function startLiveActivity(pushToStartToken, attributes, contentState, opts = {}) {
  if (!isConfigured()) return { ok: false, status: 0, reason: 'apns-not-configured' };
  const aps = {
    timestamp: Math.floor(Date.now() / 1000),
    event: 'start',
    'attributes-type': ATTRIBUTES_TYPE,
    attributes,
    'content-state': contentState,
  };
  if (opts.staleEpoch) aps['stale-date'] = Math.floor(opts.staleEpoch);
  if (opts.alert) aps.alert = opts.alert;
  return send(pushToStartToken, { aps }, { expiration: Math.floor(opts.staleEpoch || 0) });
}

/** 表示中の Live Activity を終了させる。 */
async function endLiveActivity(updateToken, contentState, opts = {}) {
  if (!isConfigured()) return { ok: false, status: 0, reason: 'apns-not-configured' };
  const aps = {
    timestamp: Math.floor(Date.now() / 1000),
    event: 'end',
    'content-state': contentState,
  };
  if (opts.dismissEpoch) aps['dismissal-date'] = Math.floor(opts.dismissEpoch);
  return send(updateToken, { aps }, { priority: 5 });
}

module.exports = {
  isConfigured,
  updateLiveActivity,
  startLiveActivity,
  endLiveActivity,
  ATTRIBUTES_TYPE,
};
