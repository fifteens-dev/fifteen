# Firebase セットアップガイド

このガイドでは、15sアプリにFirebaseを統合する手順を説明します。

## 前提条件

- Googleアカウント
- Flutter SDK（インストール済み）
- Firebase関連パッケージ（すでに追加済み）

## 1. Firebaseプロジェクトの作成

### 1.1 Firebaseコンソールにアクセス

1. [Firebase Console](https://console.firebase.google.com/)にアクセス
2. Googleアカウントでログイン

### 1.2 新しいプロジェクトを作成

1. 「プロジェクトを追加」をクリック
2. プロジェクト名を入力（例：`fifteen`または`15s`）
3. プロジェクトIDを確認（自動生成されます）
4. Google Analyticsの有効化（推奨：有効）
5. Analyticsアカウントを選択または新規作成
6. 「プロジェクトを作成」をクリック

## 2. iOSアプリの設定

### 2.1 iOSアプリを追加

1. Firebaseプロジェクトのコンソールで「iOSアプリを追加」をクリック
2. **Apple バンドル ID**: `com.example.fifteen`
   - ⚠️ 本番環境では、独自のバンドルID（例：`com.fifteens.app`）に変更してください
3. アプリのニックネーム（任意）: `15s iOS`
4. App Store ID（任意）: 後で追加可能

### 2.2 GoogleService-Info.plistをダウンロード

1. 「GoogleService-Info.plistをダウンロード」をクリック
2. ダウンロードしたファイルを `ios/Runner/` ディレクトリに配置

```bash
# ダウンロードフォルダから移動
mv ~/Downloads/GoogleService-Info.plist ios/Runner/
```

### 2.3 Xcodeで設定

1. Xcodeでプロジェクトを開く:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. Runnerプロジェクトを選択
3. `GoogleService-Info.plist`をプロジェクトに追加（ドラッグ&ドロップ）
4. 「Copy items if needed」にチェック

## 3. Androidアプリの設定

### 3.1 Androidアプリを追加

1. Firebaseプロジェクトのコンソールで「Androidアプリを追加」をクリック
2. **Androidパッケージ名**: `com.example.fifteen`
   - ⚠️ 本番環境では、独自のパッケージ名（例：`com.fifteens.app`）に変更してください
3. アプリのニックネーム（任意）: `15s Android`
4. デバッグ用の署名証明書SHA-1（任意）: 後で追加可能

### 3.2 google-services.jsonをダウンロード

1. 「google-services.jsonをダウンロード」をクリック
2. ダウンロードしたファイルを `android/app/` ディレクトリに配置

```bash
# ダウンロードフォルダから移動
mv ~/Downloads/google-services.json android/app/
```

### 3.3 build.gradleを編集

**android/build.gradle**に以下を追加:
```gradle
buildscript {
    dependencies {
        // Firebase
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

**android/app/build.gradle**の最後に追加:
```gradle
apply plugin: 'com.google.gms.google-services'
```

## 4. Webアプリの設定

### 4.1 Webアプリを追加

1. Firebaseプロジェクトのコンソールで「Webアプリを追加」をクリック
2. アプリのニックネーム: `15s Web`
3. Firebase Hostingの設定（任意）

### 4.2 Firebase設定をコピー

1. Firebase設定オブジェクトが表示されます
2. この情報を `web/index.html` に追加する必要があります

## 5. Firebase Authenticationの有効化

### 5.1 認証方法を有効化

1. Firebaseコンソールで「Authentication」→「始める」をクリック
2. 「Sign-in method」タブを選択
3. **電話番号**を有効化:
   - 「電話」をクリック
   - 「有効にする」をトグル
   - テスト用電話番号を追加（オプション）
   - 「保存」をクリック

### 5.2 承認済みドメインを確認

1. 「Settings」タブを選択
2. 承認済みドメインに以下が含まれていることを確認:
   - `localhost`
   - 本番環境のドメイン（デプロイ時に追加）

## 6. Cloud Firestoreの設定

### 6.1 データベースを作成

1. Firebaseコンソールで「Firestore Database」→「データベースの作成」をクリック
2. ロケーションを選択: `asia-northeast1`（東京）または `asia-northeast2`（大阪）
3. セキュリティルールを選択:
   - 開発中: **テストモードで開始**
   - 本番環境: **本番モードで開始**（後でルールを設定）
4. 「有効にする」をクリック

### 6.2 セキュリティルールの設定（本番環境用）

開発が進んだら、以下のような適切なセキュリティルールを設定:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // ユーザープロフィール
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }

    // 投稿
    match /posts/{postId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth.uid == resource.data.userId;
    }
  }
}
```

## 7. Firebase Storageの設定

### 7.1 Storageを有効化

1. Firebaseコンソールで「Storage」→「始める」をクリック
2. セキュリティルールを確認
3. ロケーションを選択: Firestoreと同じロケーション
4. 「完了」をクリック

### 7.2 セキュリティルールの設定（本番環境用）

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // ユーザープロフィール画像
    match /profile_images/{userId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId
                   && request.resource.size < 5 * 1024 * 1024
                   && request.resource.contentType.matches('image/.*');
    }

    // 投稿画像
    match /post_images/{userId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId
                   && request.resource.size < 10 * 1024 * 1024
                   && request.resource.contentType.matches('image/.*');
    }
  }
}
```

## 8. Flutterアプリの初期化

Firebaseの設定ファイルが配置されたら、アプリでFirebaseを初期化します。

**lib/main.dart**を更新:

```dart
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebaseを初期化
  await Firebase.initializeApp();

  // ステータスバーの設定
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const FifteenApp());
}
```

## 9. 確認事項

### ✅ チェックリスト

- [ ] Firebaseプロジェクトが作成されている
- [ ] iOS用 `GoogleService-Info.plist` が `ios/Runner/` にある
- [ ] Android用 `google-services.json` が `android/app/` にある
- [ ] Androidの `build.gradle` が更新されている
- [ ] Firebase Authenticationで電話番号認証が有効化されている
- [ ] Cloud Firestoreが作成されている
- [ ] Firebase Storageが有効化されている
- [ ] `.gitignore` にFirebase設定ファイルが追加されている

### 重要な注意事項

⚠️ **セキュリティ**:
- `GoogleService-Info.plist` と `google-services.json` は `.gitignore` に追加されています
- これらのファイルは公開リポジトリにコミットしないでください
- 本番環境では適切なセキュリティルールを設定してください

## 10. トラブルシューティング

### エラー: "No Firebase App '[DEFAULT]' has been created"

**解決策**: `Firebase.initializeApp()` が呼ばれているか確認

### iOS: GoogleService-Info.plist が見つからない

**解決策**: Xcodeでファイルがターゲットに含まれているか確認

### Android: google-services.json が見つからない

**解決策**: ファイルが `android/app/` ディレクトリにあるか確認

## 次のステップ

Firebase設定が完了したら:
1. 電話番号認証の実装
2. ユーザープロフィールのFirestore保存
3. プロフィール画像のStorage保存

詳細は開発ドキュメントを参照してください。
