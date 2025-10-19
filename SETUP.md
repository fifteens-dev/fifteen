# セットアップガイド

このドキュメントでは、両方のデバイスでFifteenプロジェクトを開発できるようにするための詳細な手順を説明します。

## 初回セットアップ（各デバイスで1回のみ）

### デバイス1（現在のMac - gotoutarou）

#### 1. Flutterのインストール
```bash
# Homebrewでインストール（推奨）
brew install --cask flutter

# インストール確認
flutter --version

# 環境チェック
flutter doctor
```

#### 2. 不足しているツールのインストール
`flutter doctor` の出力に従って、不足しているものをインストール:

**iOS開発の場合:**
```bash
# Xcodeをインストール（App Storeから）
# Xcode command line toolsをインストール
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch

# CocoaPodsをインストール
sudo gem install cocoapods
```

**Android開発の場合:**
- Android Studioをインストール
- Android SDKをセットアップ
- Android Emulatorをセットアップ

#### 3. Flutterプロジェクトの作成
```bash
cd /Users/gotoutarou/Fifteen

# Flutterプロジェクトを作成
flutter create .

# 依存関係をインストール
flutter pub get
```

#### 4. Gitリモートリポジトリのセットアップ

**GitHub、GitLab、またはBitbucketにリポジトリを作成してから:**

```bash
# リモートリポジトリを追加
git remote add origin <あなたのリポジトリURL>

# 全てをコミット
git add .
git commit -m "Initial commit: Flutter SNS app setup"

# プッシュ
git branch -M main
git push -u origin main
```

### デバイス2（別のデバイス）

#### 1. Flutterのインストール
デバイス1と同じ手順でFlutterをインストール

#### 2. プロジェクトのクローン
```bash
# リポジトリをクローン
git clone <あなたのリポジトリURL>

# プロジェクトディレクトリに移動
cd Fifteen

# 依存関係をインストール
flutter pub get

# iOS用（macOSの場合）
cd ios && pod install && cd ..
```

## 日常的な開発ワークフロー

### デバイス1で作業開始

```bash
cd /Users/gotoutarou/Fifteen

# 最新の変更を取得
git pull

# 開発開始
flutter run
```

### デバイス1で作業終了

```bash
# 変更をステージング
git add .

# コミット
git commit -m "機能追加: ○○○"

# プッシュ
git push
```

### デバイス2で作業開始

```bash
cd Fifteen

# デバイス1の変更を取得
git pull

# 依存関係が変更されている場合
flutter pub get

# 開発開始
flutter run
```

### デバイス2で作業終了

```bash
# 変更をステージング
git add .

# コミット
git commit -m "修正: ○○○"

# プッシュ
git push
```

## Firebaseのセットアップ

SNSアプリにはFirebaseが必要です。両方のデバイスで同じFirebaseプロジェクトを使用します。

### 1. Firebaseプロジェクトの作成

1. [Firebase Console](https://console.firebase.google.com/)にアクセス
2. 新しいプロジェクトを作成
3. プロジェクト名: `Fifteen` (または任意の名前)

### 2. FlutterアプリとFirebaseの連携

```bash
# Firebase CLIのインストール
npm install -g firebase-tools

# Firebaseにログイン
firebase login

# FlutterFire CLIのインストール
dart pub global activate flutterfire_cli

# パスを通す（必要に応じて）
export PATH="$PATH":"$HOME/.pub-cache/bin"

# Firebaseプロジェクトと連携
flutterfire configure
```

### 3. Firebase設定ファイルの扱い

**重要:** `firebase_options.dart`、`google-services.json`、`GoogleService-Info.plist`はGitで管理されません（`.gitignore`に含まれています）。

各デバイスで以下を実行:
```bash
flutterfire configure
```

これにより、各デバイスで必要な設定ファイルが自動生成されます。

## トラブルシューティング

### 依存関係の問題
```bash
# キャッシュをクリア
flutter clean
flutter pub get

# iOS用
cd ios && pod deintegrate && pod install && cd ..
```

### Gitコンフリクトが発生した場合
```bash
# 現在の変更を一時保存
git stash

# 最新を取得
git pull

# 保存した変更を適用
git stash pop

# コンフリクトを手動で解決してから
git add .
git commit -m "Merge: コンフリクト解決"
git push
```

### Flutter バージョンの違い
両方のデバイスで同じFlutterバージョンを使用することを推奨:

```bash
# 現在のバージョン確認
flutter --version

# 特定のバージョンに切り替え（FVMを使用する場合）
fvm install 3.16.0
fvm use 3.16.0
```

## ベストプラクティス

1. **こまめにコミット**: 機能単位で小さくコミット
2. **プル忘れ注意**: 作業開始前に必ず `git pull`
3. **わかりやすいコミットメッセージ**: 日本語でOK
4. **ビルド前にテスト**: `flutter test` でテストを実行
5. **フォーマット**: `flutter format .` でコードを整形

## 次のステップ

1. ✅ Gitリポジトリのセットアップ
2. ✅ `.gitignore`の作成
3. ⬜ Flutterプロジェクトの作成 (`flutter create .`)
4. ⬜ Firebaseプロジェクトの作成と連携
5. ⬜ 基本的なUIの実装開始

詳細な開発ガイドは[CLAUDE.md](./CLAUDE.md)を参照してください。
