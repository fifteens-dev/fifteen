# 開発進捗レポート

最終更新: 2026-01-10

## 📋 現在の状態

### ✅ 完了した作業

1. **Firebase設定**
   - Firebase Authentication（電話番号認証）を有効化
   - Cloud Firestoreを有効化（Standard エディション）
   - Web、Android向けのFirebase設定完了
   - テスト用電話番号を設定: `+81 80-5418-1684`、`+81 80-7969-0520`（確認コード: `123456`）

2. **認証フロー実装**
   - `AuthService`: 電話番号認証、SMS送信、コード検証
   - `UserService`: Firestoreユーザーデータ管理、ユーザー名の重複チェック
   - `InviteCodeService`: 招待コード検証
   - `UserModel`: Firestoreのデータ構造

3. **画面実装**
   - PhoneAuthScreen: 電話番号入力 → SMS送信
   - VerificationCodeScreen: SMS認証コード入力 → ユーザーアカウント作成
   - InviteCodeScreen: 招待コード検証
   - NameInputScreen: 名前入力 → Firestoreに保存
   - UsernameCreationScreen: ユーザー名作成（重複チェック付き）
   - ProfileSetupScreen: 完了画面（画像アップロードは後回し）
   - DevToolsScreen: テストデータセットアップ用

4. **開発者ツール**
   - テスト用招待コード作成機能
   - 招待コード: `TEST123`, `WELCOME`, `HELLO15S`
   - デバッグモードで自動的に開発者ツール画面を表示

5. **通知機能実装（NEW! 2026-01-10）** ✨
   - **データモデル**: NotificationModel（いいね、コメント、フォロー、公式通知）
   - **サービス層**: NotificationService（CRUD、FCMトークン管理）、FCMHandlerService（FCM初期化、メッセージ処理）
   - **UI実装**: NotificationBadge（未読バッジ）、NotificationListScreen（通知一覧）、HomeScreenに通知アイコン
   - **プラットフォーム設定**: iOS（AppDelegate.swift、Info.plist）、Android（AndroidManifest.xml、colors.xml）、Web（firebase-messaging-sw.js）
   - **Cloud Functions**: sendPushNotification（通知送信）、sendOfficialNotification（公式通知）
   - **Firestore**: インデックス、セキュリティルール
   - **公式通知**: 管理者→全ユーザー通知機能、送信スクリプト
   - **詳細**: `NOTIFICATION_SETUP.md` を参照

### ⏸️ 保留中の作業

1. **Firebase Storage**
   - 課金アカウント登録が必要
   - プロフィール画像アップロード機能は未実装

2. **認証フローのテスト**
   - Web版では電話番号認証に制限あり
   - **次のステップ**: Mac miniでAndroidエミュレータまたはiOSシミュレータを使用してテスト

### 📱 ファイル構成

```
lib/
├── main.dart                          # エントリーポイント（デバッグ時は/dev-toolsから開始）
├── models/
│   └── user_model.dart                # Firestoreユーザーデータモデル
├── screens/
│   ├── phone_auth_screen.dart         # 電話番号入力
│   ├── verification_code_screen.dart  # SMS認証コード入力
│   ├── invite_code_screen.dart        # 招待コード入力
│   ├── name_input_screen.dart         # 名前入力
│   ├── username_creation_screen.dart  # ユーザー名作成
│   ├── profile_setup_screen.dart      # プロフィール設定（簡略版）
│   ├── terms_of_service_screen.dart   # 利用規約
│   ├── privacy_policy_screen.dart     # プライバシーポリシー
│   └── dev_tools_screen.dart          # 開発者ツール
├── services/
│   ├── auth_service.dart              # Firebase Authentication
│   ├── user_service.dart              # Firestoreユーザー管理
│   └── invite_code_service.dart       # 招待コード管理
├── utils/
│   └── setup_test_data.dart           # テストデータセットアップ
├── widgets/
│   ├── phone_input_field.dart         # 電話番号入力フィールド
│   ├── primary_button.dart            # プライマリボタン
│   └── common_input_field.dart        # 共通入力フィールド
└── constants/
    ├── app_colors.dart                # カラー定義
    ├── app_text_styles.dart           # テキストスタイル
    └── app_dimensions.dart            # サイズ定義
```

## 🧪 Mac miniでのテスト手順

### 1. リポジトリのクローン（初回のみ）

```bash
cd ~/Documents
git clone https://github.com/fifteens-dev/fifteen.git
cd fifteen
```

### 2. 最新のコードを取得

```bash
git pull origin main
```

### 3. 依存関係のインストール

```bash
flutter pub get
```

### 4. デバイスの確認

```bash
flutter devices
```

### 5. アプリの実行

**Androidエミュレータの場合:**
```bash
# エミュレータを起動（Android Studioから、または）
flutter emulators --launch <emulator_id>

# アプリを実行
flutter run
```

**iOSシミュレータの場合:**
```bash
# シミュレータを起動
open -a Simulator

# アプリを実行
flutter run
```

### 6. テストフロー

1. **開発者ツール画面が表示される**（デバッグモード）
   - 「テストデータを作成」ボタンをクリック
   - Firestoreに招待コードが作成される

2. **認証フローのテスト**
   - 「電話番号認証画面へ」ボタンをクリック
   - テスト用電話番号を入力: `080-5418-1684` または `080-7969-0520`
   - 「認証メッセージを送信」をクリック
   - 確認コード入力画面で `123456` を入力
   - 招待コード入力: `TEST123`、`WELCOME`、または `HELLO15S`
   - 名前を入力
   - ユーザー名を作成（3〜20文字、英数字とアンダースコアのみ）
   - プロフィール設定完了

## 🔥 Firebase設定情報

### プロジェクト情報
- **プロジェクトID**: `fifteens-39cfe`
- **プロジェクト名**: Fifteens

### 有効化済みサービス
- ✅ Firebase Authentication（電話番号認証）
- ✅ Cloud Firestore（Standard エディション）
- ❌ Firebase Storage（未設定 - 課金アカウント必要）

### テスト用電話番号
Firebase Console → Authentication → Sign-in method → 電話番号 → テスト用の電話番号

- `+81 80-5418-1684` → 確認コード: `123456`
- `+81 80-7969-0520` → 確認コード: `123456`

### Firestoreコレクション構成

```
/users/{userId}
  - uid: string
  - phoneNumber: string
  - name: string (optional)
  - username: string (optional)
  - profileImageUrl: string (optional)
  - createdAt: timestamp
  - updatedAt: timestamp

/invite_codes/{code}
  - code: string
  - isUsed: boolean
  - usedBy: string (userId, optional)
  - usedAt: timestamp (optional)
  - createdAt: timestamp
```

## 🐛 既知の問題

1. **Web版の電話番号認証**
   - localhostでは電話番号認証が制限される
   - 解決策: Android/iOSデバイスでテスト

2. **プロフィール画像アップロード**
   - Firebase Storageが未設定
   - 解決策: 課金アカウント登録後に実装

## 📝 次の開発タスク

### 優先度: 高
- [ ] Android/iOSで認証フローの完全なテスト
- [ ] テスト結果に基づくバグ修正

### 優先度: 中
- [ ] Firebase Storageの設定（課金アカウント登録後）
- [ ] プロフィール画像アップロード機能の実装
- [ ] ホーム画面（タイムライン）の設計・実装

### 優先度: 低
- [ ] コードの最適化
- [ ] エラーハンドリングの改善
- [ ] ユニットテストの追加

## 🔗 リンク

- **GitHub Repository**: https://github.com/fifteens-dev/fifteen
- **Firebase Console**: https://console.firebase.google.com/project/fifteens-39cfe
- **Firebase Setup Guide**: `FIREBASE_SETUP.md`

## 💬 開発メモ

### 2025-10-29
- 電話番号認証フローの実装完了
- 開発者ツールの追加（テスト用招待コード作成）
- Web版でUIの確認完了
- Mac miniでの実機テストへ移行

### アーキテクチャの決定事項
- 状態管理: 現在はStatefulWidgetを使用（将来的にProvider/Riverpodへ移行を検討）
- データベース: Cloud Firestore
- 認証: Firebase Authentication（電話番号認証）
- ストレージ: Firebase Storage（未実装）

### デザイン
- ダークテーマベース
- カラー: 黒背景 (#000000)、白文字 (#FFFFFF)
- フォント: システムデフォルト
- Material Design 3を使用
