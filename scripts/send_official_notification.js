/**
 * 公式通知送信スクリプト
 *
 * 管理者が全ユーザーに対して公式通知を送信するためのNode.jsスクリプト
 *
 * 必要な準備:
 * 1. Firebase Admin SDKのサービスアカウントキーをダウンロード
 *    Firebase Console > Project Settings > Service Accounts > Generate New Private Key
 * 2. ダウンロードしたJSONファイルを scripts/serviceAccountKey.json として保存
 * 3. admin_usersコレクションに管理者を追加（Firebase Console）
 *    例: { "isAdmin": true, "email": "admin@example.com" }
 *
 * 使い方:
 * 1. スクリプト内のtitle, body, imageUrl, actionUrlを編集
 * 2. npm installを実行（firebase-adminがない場合）
 * 3. node send_official_notification.js を実行
 */

const admin = require('firebase-admin');

// サービスアカウントキーを読み込み
// NOTE: このファイルは絶対に公開リポジトリにコミットしないこと！
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

/**
 * 公式通知を送信
 */
async function sendOfficialNotification() {
  try {
    // 通知内容を設定
    const notificationData = {
      title: '新機能のお知らせ',
      body: '通知機能が追加されました！いいね、コメント、フォローの通知を受け取れるようになりました。',
      imageUrl: '', // オプション: 画像URL
      actionUrl: '', // オプション: タップ時の遷移先
    };

    console.log('公式通知を送信中...');
    console.log('Title:', notificationData.title);
    console.log('Body:', notificationData.body);

    // Cloud Functionを呼び出し
    const functions = admin.functions();
    const sendNotification = functions.httpsCallable('sendOfficialNotification');

    const result = await sendNotification(notificationData);

    console.log('✅ 公式通知の送信に成功しました');
    console.log('結果:', result.data);

  } catch (error) {
    console.error('❌ 公式通知の送信に失敗しました:', error);

    if (error.code === 'permission-denied') {
      console.error('管理者権限がありません。admin_usersコレクションを確認してください。');
    }
  } finally {
    // アプリを終了
    process.exit();
  }
}

// スクリプトを実行
sendOfficialNotification();
