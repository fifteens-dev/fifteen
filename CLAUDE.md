# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fifteenは、FlutterとFirebaseを使用したクロスプラットフォーム（iOS/Android）のSNSアプリケーションです。

## Development Environment Setup

### Flutter Installation
Flutterがインストールされていない場合:
```bash
# macOSの場合
# 1. Flutter SDKをダウンロード
# 2. パスを通す
export PATH="$PATH:`pwd`/flutter/bin"

# インストール確認
flutter doctor
```

### Project Setup
```bash
# 依存関係のインストール
flutter pub get

# iOSの場合（macOSのみ）
cd ios && pod install && cd ..
```

## Common Commands

### Development
```bash
# 開発サーバーの起動（デバッグモード）
flutter run

# 特定のデバイスで実行
flutter devices  # 利用可能なデバイスを確認
flutter run -d <device_id>

# ホットリロード: 実行中に 'r' を押す
# ホットリスタート: 実行中に 'R' を押す
```

### Testing
```bash
# 全てのテストを実行
flutter test

# 特定のテストファイルを実行
flutter test test/widget_test.dart

# カバレッジ付きでテスト実行
flutter test --coverage
```

### Build
```bash
# Androidビルド（APK）
flutter build apk

# Androidビルド（App Bundle - Play Store用）
flutter build appbundle

# iOSビルド（macOSのみ）
flutter build ios

# リリースビルド
flutter build apk --release
flutter build ios --release
```

### Code Quality
```bash
# 静的解析
flutter analyze

# コードフォーマット
flutter format .

# 特定のファイルをフォーマット
flutter format lib/main.dart
```

### Dependencies
```bash
# 依存関係の追加
flutter pub add <package_name>

# 開発依存関係の追加
flutter pub add --dev <package_name>

# 依存関係の更新
flutter pub upgrade

# 未使用の依存関係をクリーンアップ
flutter pub get
```

## Architecture

### Directory Structure
```
lib/
├── main.dart              # アプリケーションのエントリーポイント
├── models/                # データモデル
├── screens/               # UI画面
├── widgets/               # 再利用可能なウィジェット
├── services/              # バックエンドサービス（Firebase等）
├── providers/             # 状態管理（Provider/Riverpod）
├── utils/                 # ユーティリティ関数
└── constants/             # 定数定義
```

### State Management
SNSアプリの複雑な状態管理には、Provider、Riverpod、またはBlocパターンの使用を推奨。

### Firebase Integration
SNSアプリの主要機能:
- **Firebase Authentication**: ユーザー認証
- **Cloud Firestore**: リアルタイムデータベース（投稿、コメント、ユーザープロフィール）
- **Firebase Storage**: 画像・動画のアップロード
- **Cloud Messaging**: プッシュ通知

## SNS Features to Implement

### Core Features
- ユーザー登録・ログイン
- プロフィール管理
- 投稿作成・編集・削除
- タイムライン表示
- いいね・コメント機能
- フォロー・フォロワー機能
- 通知機能
- 画像・動画アップロード

### Platform-Specific Considerations
- iOS: App Store審査ガイドライン遵守
- Android: Google Play審査ガイドライン遵守
- プラットフォーム固有のUI/UX調整

## Development Workflow

1. `flutter create`で既にプロジェクトが作成されていない場合は作成
2. 必要なパッケージを`pubspec.yaml`に追加
3. `flutter pub get`で依存関係をインストール
4. 機能開発は`lib/`ディレクトリ内で実施
5. `flutter test`でテストを実行
6. `flutter analyze`でコード品質をチェック
7. `flutter run`でデバイス/エミュレータで動作確認

## Key Dependencies (Recommended)

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^latest        # Firebase初期化
  firebase_auth: ^latest        # 認証
  cloud_firestore: ^latest      # データベース
  firebase_storage: ^latest     # ストレージ
  provider: ^latest             # 状態管理
  image_picker: ^latest         # 画像選択
  cached_network_image: ^latest # 画像キャッシング

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^latest        # Lintルール
```

## Notes

- Flutterのバージョンは`flutter --version`で確認
- Firebase設定ファイル（`google-services.json`、`GoogleService-Info.plist`）は`.gitignore`に追加
- 環境変数や機密情報は絶対にコミットしない
