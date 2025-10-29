# 開発セッション履歴

## セッション: 2025-10-29 - Firebase認証フロー実装

### 概要
電話番号認証を使用した完全な認証フローを実装しました。Web版でUIを確認し、Mac miniでの実機テストへ移行します。

---

## 主な会話の流れ

### 1. Storageの扱いについて
**ユーザー**: storageを後回しにして、認証フローを完成させましょう。

**実施内容**:
- Firebase Storageは課金アカウントが必要なため後回しに決定
- 認証フローの実装を優先
- プロフィール画像アップロード機能は保留

### 2. Firebase認証フローの実装

**実装したサービス**:
- `AuthService`: 電話番号認証、SMS送信、コード検証
- `UserService`: Firestoreユーザーデータ管理
- `InviteCodeService`: 招待コード検証
- `UserModel`: データモデル

**実装した画面**:
- PhoneAuthScreen: 電話番号入力
- VerificationCodeScreen: SMS認証コード入力
- InviteCodeScreen: 招待コード検証
- NameInputScreen: 名前入力
- UsernameCreationScreen: ユーザー名作成
- ProfileSetupScreen: プロフィール設定（簡略版）

### 3. テスト用招待コードの作成

**ユーザー**: テスト用招待コードを作成しましょう

**実施内容**:
- `SetupTestData`ユーティリティを作成
- `DevToolsScreen`を追加（開発者ツール画面）
- テスト用招待コード: `TEST123`, `WELCOME`, `HELLO15S`
- デバッグモードで自動的に開発者ツール画面を表示

### 4. アプリの実行とテスト

**ユーザー**: タブを切ってしまったのでもう一度実行できますか

**実施内容**:
- Chromeでアプリを再実行
- 開発者ツール画面が表示される
- テスト用招待コードの作成機能を確認

### 5. Web版での電話番号認証の問題

**ユーザー**: 電話番号を正しく入力したのにエラーになります。

**問題**:
- Web版（localhost）では電話番号認証が制限される
- Firebase Consoleでテスト用電話番号を設定する必要がある

**解決策の提示**:
1. Firebase Consoleに登録済みのテスト用電話番号を使用
   - `080-5418-1684` または `080-7969-0520`
   - 確認コード: `123456`
2. Android/iOSエミュレータで実際の電話番号を使ってテスト

### 6. テスト環境の選択

**ユーザー**: Androidエミュレーターを使ってテストする方針でいきましょう。

**確認事項**:
- flutter devicesで確認 → Androidエミュレータなし
- flutter emulatorsで確認 → エミュレータ未作成
- Android Studio未インストール

**ユーザー**: androidエミュレータでテストする場合と、xcodeでテストする場合で、macbookのストレージをどちらの方が多く利用しますか？

**比較結果**:
- Android Studio: 約15-25GB
- Xcode: 約40-50GB
- → Android Studioの方がストレージ消費が少ない

**最終決定**:
**ユーザー**: mac miniでテストします。gitに会話内容や、進捗を保存してください。

---

## 技術的な決定事項

### 1. Firebase設定
- **Authentication**: 電話番号認証を有効化
- **Firestore**: Standard エディション
- **Storage**: 保留（課金アカウント必要）
- **テスト用電話番号**: `+81 80-5418-1684`, `+81 80-7969-0520`

### 2. 開発環境
- **プライマリ**: MacBook Air（コーディング、Web版テスト）
- **テスト**: Mac mini（Android/iOSエミュレータ）

### 3. 認証フロー
1. 電話番号入力 → SMS送信
2. 認証コード入力 → ユーザーアカウント作成
3. 招待コード検証
4. 名前入力 → Firestoreに保存
5. ユーザー名作成（重複チェック）
6. プロフィール設定完了

### 4. データ構造

**Firestoreコレクション**:
```
/users/{userId}
  - uid, phoneNumber, name, username
  - profileImageUrl (未実装)
  - createdAt, updatedAt

/invite_codes/{code}
  - code, isUsed, usedBy, usedAt
  - createdAt
```

---

## 発生した問題と解決策

### 問題1: Web版での電話番号認証エラー
**原因**: localhostでは電話番号認証が制限される
**解決**: Android/iOSエミュレータでテストに切り替え

### 問題2: Androidエミュレータ未設定
**原因**: Android Studio未インストール
**解決**: Mac miniで実行することに決定

---

## コミット履歴

### Commit 1: Implement Firebase Authentication flow
- Firebase Authentication service
- User service for Firestore
- Invite code service
- Screen updates with authentication logic

### Commit 2: Add developer tools for test data setup
- SetupTestData utility
- DevToolsScreen
- Test invite codes creation

---

## 次のステップ（Mac miniで実行）

1. **リポジトリの取得**
   ```bash
   git pull origin main
   ```

2. **依存関係のインストール**
   ```bash
   flutter pub get
   ```

3. **アプリの実行**
   - Android: `flutter run` （エミュレータ起動後）
   - iOS: `flutter run` （シミュレータ起動後）

4. **テストフロー**
   - 開発者ツールでテストデータ作成
   - 認証フローのテスト
   - テスト用電話番号: `080-5418-1684`
   - 確認コード: `123456`
   - 招待コード: `TEST123`

---

## 保留中のタスク

1. Firebase Storageの設定（課金アカウント登録後）
2. プロフィール画像アップロード機能
3. ホーム画面（タイムライン）の実装
4. 投稿機能の実装

---

## 参考情報

- **GitHub**: https://github.com/fifteens-dev/fifteen
- **Firebase Console**: https://console.firebase.google.com/project/fifteens-39cfe
- **Firebase Setup Guide**: FIREBASE_SETUP.md
- **Progress Report**: PROGRESS.md
