# Fifteen

FlutterとFirebaseを使用したクロスプラットフォーム（iOS/Android）SNSアプリケーション

## 必要な環境

### Flutter
- Flutter SDK（最新の安定版を推奨）
- Dart SDK（Flutterに含まれています）

### プラットフォーム固有のツール

#### iOS開発（macOSのみ）
- Xcode（最新版）
- CocoaPods

#### Android開発
- Android Studio または
- Android SDK
- Java JDK

## セットアップ手順

### 1. Flutter SDKのインストール

#### macOS（このデバイス）
```bash
# Homebrewを使用する場合（推奨）
brew install --cask flutter

# パスが通っているか確認
flutter --version
```

#### 別のデバイスでも同様の手順
各デバイスでFlutter SDKをインストールする必要があります。

### 2. Flutter環境の確認
```bash
flutter doctor
```

不足しているものがあれば、指示に従ってインストールしてください。

### 3. プロジェクトのセットアップ

このリポジトリをクローンした後:

```bash
# Fifteenディレクトリに移動
cd Fifteen

# まだFlutterプロジェクトが作成されていない場合
flutter create .

# 依存関係のインストール
flutter pub get

# iOS用（macOSのみ）
cd ios && pod install && cd ..
```

## 開発の開始

### 利用可能なデバイスを確認
```bash
flutter devices
```

### アプリの実行
```bash
# デフォルトデバイスで実行
flutter run

# 特定のデバイスで実行
flutter run -d <device_id>
```

## 複数デバイスでの開発

### Git リポジトリの同期

1. **GitHubやGitLabにリポジトリを作成**
   ```bash
   # リモートリポジトリを追加
   git remote add origin <リポジトリURL>
   ```

2. **変更をコミット＆プッシュ**
   ```bash
   git add .
   git commit -m "初期コミット"
   git push -u origin main
   ```

3. **別のデバイスでクローン**
   ```bash
   git clone <リポジトリURL>
   cd Fifteen
   flutter pub get
   ```

### 開発フロー
1. 作業開始前に `git pull` で最新の変更を取得
2. 機能開発
3. `git add .` と `git commit` で変更をコミット
4. `git push` でリモートにプッシュ
5. 別のデバイスで `git pull` して同期

## プロジェクト構造

詳細な開発ガイドラインとアーキテクチャについては、[CLAUDE.md](./CLAUDE.md)を参照してください。

## 主要な機能（予定）

- ユーザー登録・ログイン
- プロフィール管理
- 投稿作成・編集・削除
- タイムライン表示
- いいね・コメント機能
- フォロー・フォロワー機能
- 通知機能
- 画像・動画アップロード

## 技術スタック

- **フレームワーク**: Flutter
- **言語**: Dart
- **バックエンド**: Firebase
  - Authentication（認証）
  - Cloud Firestore（データベース）
  - Cloud Storage（ファイルストレージ）
  - Cloud Messaging（プッシュ通知）
- **状態管理**: Provider / Riverpod（検討中）

## ライセンス

TBD
