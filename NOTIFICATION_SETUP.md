# 通知機能セットアップガイド

通知機能の実装が完了しました。このガイドでは、Firebase Cloud FunctionsとFirestoreの設定をデプロイする手順を説明します。

## 📋 完了した実装

### Phase 1-3: アプリ実装 ✅
- ✅ NotificationModel（公式通知フィールド含む）
- ✅ NotificationService（CRUD、FCMトークン管理）
- ✅ FCMHandlerService（FCM初期化、メッセージ処理、トピック購読）
- ✅ PostService、CommentService、UserServiceへの通知統合
- ✅ NotificationBadge（未読バッジ表示）
- ✅ NotificationListScreen（公式通知UI含む）
- ✅ HomeScreenへの通知アイコン追加

### Phase 4: プラットフォーム設定 ✅
- ✅ iOS設定（AppDelegate.swift、Info.plist）
- ✅ Android設定（AndroidManifest.xml、colors.xml）
- ✅ Web設定（firebase-messaging-sw.js、index.html）
- ✅ main.dartのFCM初期化

### Phase 5: Cloud Functions ✅
- ✅ sendPushNotification関数（通知送信、無効トークン削除）
- ✅ sendOfficialNotification関数（管理者→全ユーザー）

### Phase 6: Firestore設定 ✅
- ✅ firestore.indexes.json（通知クエリ用インデックス）
- ✅ firestore.rules（セキュリティルール）

### Phase 7: 公式通知機能 ✅
- ✅ 管理者用送信スクリプト（scripts/send_official_notification.js）

---

## 🚀 デプロイ手順

### 1. Firebase CLIのインストール

```bash
npm install -g firebase-tools
firebase login
```

### 2. Firebaseプロジェクトの初期化（初回のみ）

```bash
cd /Users/gotoutarou/fifteen
firebase init
```

選択する項目:
- ✅ Functions: Configure a Cloud Functions directory and its files
- ✅ Firestore: Configure security rules and indexes files

設定:
- Functions language: JavaScript
- Functions directory: functions
- Install dependencies: Yes
- Firestore rules file: firestore.rules
- Firestore indexes file: firestore.indexes.json

### 3. Web用Firebase設定の更新

`web/firebase-messaging-sw.js` の Firebase 設定を実際の値に置き換えてください：

```javascript
firebase.initializeApp({
  apiKey: "YOUR_API_KEY",              // ← 実際のAPIキー
  authDomain: "YOUR_AUTH_DOMAIN",       // ← 実際のAuthDomain
  projectId: "YOUR_PROJECT_ID",         // ← 実際のプロジェクトID
  storageBucket: "YOUR_STORAGE_BUCKET", // ← 実際のStorageBucket
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID", // ← 実際のMessagingSenderID
  appId: "YOUR_APP_ID"                  // ← 実際のAppID
});
```

Firebase Console > Project Settings > General から取得できます。

### 4. Cloud Functionsのデプロイ

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

デプロイ後、以下の関数が作成されます：
- `sendPushNotification` - Firestore トリガー
- `sendOfficialNotification` - HTTPS 呼び出し可能関数

### 5. Firestoreインデックスとルールのデプロイ

```bash
firebase deploy --only firestore:indexes,firestore:rules
```

---

## 🔧 管理者設定（公式通知用）

### 1. 管理者ユーザーの追加

Firebase Console > Firestore Database にアクセスし、`admin_users` コレクションを作成：

1. コレクション名: `admin_users`
2. ドキュメントID: **管理者のUID**（Firebase Authenticationから取得）
3. フィールド:
   ```
   isAdmin: true
   email: "admin@example.com"
   createdAt: (Timestamp) 現在日時
   ```

### 2. サービスアカウントキーの取得

公式通知送信スクリプトを使用する場合:

1. Firebase Console > Project Settings > Service Accounts
2. "Generate New Private Key" をクリック
3. ダウンロードしたJSONファイルを `scripts/serviceAccountKey.json` として保存
4. ⚠️ **このファイルは絶対にGitにコミットしないこと！**（.gitignoreに追加済み）

### 3. スクリプトの実行

```bash
cd scripts
npm install
node send_official_notification.js
```

スクリプトを編集して、title、body、imageUrl、actionUrlをカスタマイズできます。

---

## ✅ テスト手順

### 1. アプリのビルドと実行

```bash
cd /Users/gotoutarou/fifteen
flutter pub get
flutter run
```

### 2. 通知機能のテスト

#### いいね通知
1. ユーザーAでログイン
2. ユーザーBの投稿にいいね
3. ユーザーBに通知が届く
4. ホーム画面の通知アイコンにバッジが表示される

#### コメント通知
1. ユーザーAでログイン
2. ユーザーBの投稿にコメント
3. ユーザーBに通知が届く

#### フォロー通知
1. ユーザーAでログイン
2. ユーザーBをフォロー
3. ユーザーBに通知が届く

#### 公式通知
1. 管理者ユーザーを `admin_users` コレクションに追加
2. `scripts/send_official_notification.js` を実行
3. 全ユーザーに公式通知が届く
4. 通知一覧で青枠の公式通知が表示される

### 3. プッシュ通知のテスト

#### iOS/Android
1. 実機でアプリを起動
2. 通知権限を許可
3. アプリをバックグラウンドに移行
4. 別のユーザーでいいね/コメント/フォロー
5. プッシュ通知が表示される

#### Web
1. Chromeでアプリを開く
2. 通知権限を許可
3. Service Workerが登録される
4. 別のユーザーでいいね/コメント/フォロー
5. プッシュ通知が表示される

---

## 📊 Firestoreコレクション構造

### notifications
```javascript
{
  type: "like" | "comment" | "follow" | "official",
  recipientId: "user_id",
  senderId: "user_id" | "system",
  senderUsername: "username" | "運営チーム",
  senderIconUrl: "url",
  postId: "post_id", // optional
  albumArtUrl: "url", // optional
  trackName: "track_name", // optional
  commentText: "text", // optional
  title: "公式通知タイトル", // official only
  body: "公式通知本文", // official only
  imageUrl: "url", // official only
  actionUrl: "url", // official only
  isRead: false,
  createdAt: Timestamp,
  readAt: Timestamp | null
}
```

### user_fcm_tokens
```javascript
{
  userId: "user_id",
  tokens: [
    {
      token: "fcm_token",
      platform: "ios" | "android" | "web",
      createdAt: Timestamp,
      lastUsedAt: Timestamp
    }
  ],
  updatedAt: Timestamp
}
```

### push_notification_requests
```javascript
{
  recipientId: "user_id",
  notificationType: "like" | "comment" | "follow",
  senderUsername: "username",
  message: "notification_message",
  postId: "post_id", // optional
  createdAt: Timestamp,
  processed: false
}
```

### admin_users
```javascript
{
  "user_id": {
    isAdmin: true,
    email: "admin@example.com",
    createdAt: Timestamp
  }
}
```

---

## 🔍 トラブルシューティング

### 通知が届かない

1. **FCMトークンが保存されているか確認**
   - Firestore > user_fcm_tokens コレクションを確認
   - トークンが空の場合は、アプリを再起動

2. **通知設定が有効か確認**
   - Firestore > settings/{userId} の通知設定を確認
   - `likeCommentNotification` と `followNotification` が true か

3. **Cloud Functionsのログを確認**
   ```bash
   firebase functions:log
   ```

4. **無効なトークンが削除されているか**
   - sendPushNotification関数が自動的に無効トークンを削除

### プッシュ通知が表示されない（iOS）

1. Xcodeで通知権限が有効か確認
2. Info.plistにUIBackgroundModesが追加されているか確認
3. 実機でテスト（シミュレータではプッシュ通知が動作しない）

### プッシュ通知が表示されない（Android）

1. AndroidManifest.xmlに設定が追加されているか確認
2. colors.xmlが作成されているか確認
3. Google Play Servicesがインストールされているか確認

### Web Service Workerが登録されない

1. HTTPSで動作しているか確認（localhostは例外）
2. ブラウザのDevToolsでService Workerを確認
3. firebase-messaging-sw.jsのパスが正しいか確認

---

## 📝 次のステップ

### 今後の拡張機能（オプション）

1. **通知のバッチ処理**
   - 短時間に複数いいね → "〇〇と他5人があなたの投稿にいいねしました"

2. **通知の優先度設定**
   - 重要な通知を上位表示

3. **通知の期限切れ**
   - 古い通知を自動削除（90日以上）

4. **プッシュ通知のカスタマイズ**
   - 音、振動パターンの設定

5. **Flutter管理画面**
   - アプリ内で公式通知を送信できる管理画面

---

## 🎉 完了！

通知機能の実装とデプロイが完了しました。

質問や問題がある場合は、以下を確認してください：
- Firebase Console > Functions でログを確認
- Flutter アプリのデバッグログを確認
- Firestore のセキュリティルールを確認

Happy coding! 🚀
