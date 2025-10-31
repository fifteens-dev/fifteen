# Claude Code 作業履歴 - 2025年10月30日

## 作業概要
Androidエミュレーターでのアプリ実行環境を構築し、Firebase認証フローのテスト準備を完了しました。

## 完了したタスク

### 1. ビルドエラーの解決
- **問題**: 前回のディスク容量不足により、ビルド成果物（APK）が破損
- **解決**:
  - `build/` ディレクトリを削除
  - `flutter clean` を実行
  - Gradleキャッシュ（`~/.gradle`）を完全削除して再ビルド

### 2. Gradle関連の問題解決
- **問題**: Gradle 8.9のKotlin DSLキャッシュが破損（metadata.binの読み込みエラー）
- **試行錯誤**:
  - Gradle 8.3へのダウングレード → Android Gradle Plugin 8.7.3がGradle 8.9以上を要求
  - 部分的なキャッシュ削除 → 効果なし
- **最終的な解決**: `~/.gradle` ディレクトリ全体を削除して再生成

### 3. Firebase初期化の修正
- **問題**: Android環境でFirebaseが二重初期化される（`[core/duplicate-app]` エラー）
- **原因**:
  - AndroidとiOSでは `google-services.json` / `GoogleService-Info.plist` により自動初期化される
  - Web環境のみ手動初期化が必要
- **解決**: `lib/main.dart` を修正

```dart
// Firebaseの初期化（Webのみ、AndroidとiOSは自動初期化される）
if (kIsWeb) {
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      // Web用の設定
    ),
  );
} else {
  await Firebase.initializeApp();
}
```

### 4. Android環境の最終構成

#### パッケージ名
- **最終決定**: `com.fifteens.app`
- **経緯**:
  - 初期: `com.example.fifteen`
  - 試行1: `Fifteens.s` → Javaの命名規則違反（大文字で始まるパッケージ名）により `ClassNotFoundException`
  - 最終: `com.fifteens.app` → 正常に動作

#### ファイル構成
```
android/app/
├── build.gradle
│   ├── namespace = "com.fifteens.app"
│   ├── applicationId = "com.fifteens.app"
│   ├── minSdk = 23 (Cloud Firestore要件)
│   ├── compileSdk = 34
│   ├── buildToolsVersion = "33.0.1"
│   ├── Java VERSION_17
│   └── Kotlin jvmTarget "17"
├── google-services.json (両方のパッケージ名をサポート)
│   ├── "Fifteens.s"
│   └── "com.fifteens.app"
└── src/main/kotlin/com/fifteens/app/
    └── MainActivity.kt
```

#### Gradle設定
- **Gradle**: 8.9
- **Android Gradle Plugin**: 8.7.3
- **Kotlin**: 2.0.0
- **Google Services Plugin**: 4.4.0

### 5. アプリの起動成功
- Androidエミュレーター（Medium Phone API 36.1）でアプリが正常に起動
- Firebase認証が正常に動作
- 既存のユーザーセッションが保持されている（uid: `zm5aPAyWfzVFZrUcLckdpBxx38h1`）
- 開発者ツール画面が正常に表示

## 遭遇した主な問題と解決策

### 問題1: Gradleキャッシュの破損
```
Error resolving plugin [id: 'dev.flutter.flutter-plugin-loader', version: '1.0.0']
Could not read workspace metadata from ~/.gradle/caches/8.9/kotlin-dsl/accessors/.../metadata.bin
```
**解決**: Gradleキャッシュ全体を削除
```bash
rm -rf ~/.gradle
flutter run -d emulator-5554
```

### 問題2: Firebase二重初期化
```
[ERROR:flutter/runtime/dart_vm_initializer.cc(41)] Unhandled Exception:
[core/duplicate-app] A Firebase App named "[DEFAULT]" already exists
```
**解決**: プラットフォーム別の初期化処理を実装（Web用とネイティブ用を分離）

### 問題3: ディスク容量不足
```
java.io.IOException: No space left on device
```
**解決**:
- Flutter ZIPファイル削除（1.5GB）
- 各種キャッシュのクリーンアップ
- 99%使用 → 69%使用に改善

## 技術的な学び

### Android開発の注意点
1. **パッケージ命名規則**: Javaの逆ドメイン命名規則に従う必要がある
   - NG: `Fifteens.s` （大文字で始まるパッケージ名）
   - OK: `com.fifteens.app` （小文字のみ）

2. **Firebase設定の違い**:
   - Web: 手動初期化が必須
   - Android/iOS: 設定ファイルによる自動初期化

3. **Gradleの依存関係**:
   - Android Gradle Plugin 8.7.3 → Gradle 8.9以上が必須
   - キャッシュ破損時は部分削除ではなく全削除が確実

### ビルドエラーのデバッグ手順
1. `flutter clean` でFlutter側をクリーン
2. `build/` ディレクトリの削除
3. Gradleキャッシュのクリーン（`~/.gradle/caches`）
4. 必要に応じて全Gradleキャッシュを削除（`~/.gradle`）

## 現在の状態

### 動作確認済み
- ✅ Androidエミュレーターでのアプリ起動
- ✅ Firebase初期化
- ✅ 既存ユーザーセッションの復元
- ✅ 開発者ツール画面の表示

### 完了した追加タスク（本日後半）
1. ✅ 招待コード検証機能の強化
   - 詳細なエラーメッセージの実装
   - 使用済みコード: 「この招待コードはすでに使用されています」
   - 期限切れ: 「この招待コードは有効期限切れです」
   - 存在しない: 「無効な招待コードです」

2. ✅ セキュリティ対策の実装
   - GitHubリポジトリをPrivateに変更
   - コラボレーター招待機能の設定
   - Firebase APIキーの保護

3. ✅ 認証フローのテスト完了
   - 電話番号認証のテスト成功
   - SMS認証コードの検証成功
   - 招待コードの検証成功
   - 全認証フローが正常に動作することを確認

### 既知の警告（動作には影響なし）
```
Your project is configured with Android NDK 23.1.7779620, but the following plugin(s)
depend on a different Android NDK version:
- cloud_firestore requires Android NDK 27.0.12077973
- firebase_auth requires Android NDK 27.0.12077973
- firebase_core requires Android NDK 27.0.12077973
- firebase_storage requires Android NDK 27.0.12077973
```
**対処**: 必要に応じて `android/app/build.gradle` に `ndkVersion = "27.0.12077973"` を追加

## ファイル変更履歴

### 変更されたファイル
1. `lib/main.dart` - Firebase初期化ロジックの修正
2. `android/app/build.gradle` - パッケージ名、SDK設定の更新
3. `android/app/google-services.json` - 新しい設定で置き換え
4. `android/app/src/main/kotlin/com/fifteens/app/MainActivity.kt` - 新しいパッケージ構造に移動
5. `android/gradle/wrapper/gradle-wrapper.properties` - Gradle 8.9に更新（一時的に8.3にダウングレードも試行）
6. `android/settings.gradle` - プラグインバージョン更新

### 削除されたファイル/ディレクトリ
- `android/app/src/main/kotlin/com/example/fifteen/` - 旧パッケージディレクトリ
- `build/` - ビルド成果物（破損のため削除）
- `~/.gradle/` - Gradleキャッシュ（破損のため削除）

## 開発環境情報

### 使用ツール
- Flutter SDK
- Android Studio
- Android Emulator: Medium Phone API 36.1 (Android 16)
- Gradle: 8.9
- JDK: 17

### プロジェクト構成
- プロジェクト名: Fifteen (15s)
- Package: com.fifteens.app
- Firebase Project: fifteens-39cfe

## 次回セッションの開始手順

1. **エミュレーターの起動**:
```bash
# Android Studioから起動、または
open -a /Applications/Android\ Studio.app
# Device Managerから "Medium Phone API 36.1" を起動
```

2. **アプリの実行**:
```bash
cd /Users/gotoutarou/fifteen
flutter run -d emulator-5554
```

3. **テストの開始**:
- 開発者ツール画面で招待コードを作成
- 「認証テストを開始」ボタンから認証フローをテスト

## メモ
- デバッグモードでは開発者ツール画面 (`/dev-tools`) が初期画面として表示される
- リリースビルドでは電話番号入力画面 (`/`) が初期画面になる
- エミュレーターは開発中は起動したままにしておくと効率的
- Hot Reload (r) / Hot Restart (R) で素早く変更を反映可能

---

## 次回セッションの計画

### 実装予定: ホーム画面（タイムライン）

#### 1. 基本レイアウト
- TikTok/Instagram Reels風の縦スワイプUI
- 全画面表示
- 動画プレーヤー（15秒動画）

#### 2. インタラクション要素
**右側のアクションボタン:**
- プロフィール画像
- いいねボタン（ハートアイコン + カウント）
- コメントボタン（吹き出しアイコン + カウント）
- シェアボタン

**下部の投稿情報:**
- ユーザー名
- キャプション
- 音楽情報（オプション）

#### 3. スワイプ機能
- 縦スワイプで次の投稿へ
- PageViewウィジェットを使用
- 自動動画再生

### 必要なパッケージ
```yaml
dependencies:
  video_player: ^2.8.0  # 動画再生
  chewie: ^1.7.0        # 動画プレーヤーUI（検討中）
```

### データモデル設計

**Post（投稿）モデル:**
```dart
class Post {
  final String id;
  final String userId;
  final String username;
  final String profileImageUrl;
  final String videoUrl;
  final String caption;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final String? musicTitle;
}
```

### 実装の流れ

1. **ホーム画面のベースUIを作成**
   - `lib/screens/home_screen.dart` を作成
   - PageViewウィジェットでスワイプ機能の基礎を実装

2. **動画プレーヤーの統合**
   - video_playerパッケージの導入
   - 自動再生・ループ再生の実装

3. **アクションボタンのUI作成**
   - いいね、コメント、シェアボタン
   - アニメーション効果

4. **投稿情報の表示**
   - ユーザー名、キャプション
   - オーバーレイUIの実装

5. **Firestoreとの連携**
   - モックデータで先行実装
   - 後にFirestoreから実データを取得

### 今後の開発ロードマップ

**フェーズ1: コアUI（次回〜）**
- ✅ 認証フロー（完了）
- 🔄 ホーム画面（タイムライン）← 次回
- ⬜ 投稿作成画面
- ⬜ プロフィール画面

**フェーズ2: インタラクション機能**
- ⬜ いいね機能
- ⬜ コメント機能
- ⬜ フォロー/フォロワー機能
- ⬜ シェア機能

**フェーズ3: 追加機能**
- ⬜ 検索・発見画面
- ⬜ 通知画面
- ⬜ 設定画面
- ⬜ DM（ダイレクトメッセージ）

**フェーズ4: パフォーマンス最適化**
- ⬜ 動画のプリロード
- ⬜ 画像キャッシング
- ⬜ ページネーション
- ⬜ オフライン対応

### 技術的な検討事項

1. **動画ストレージ**
   - Firebase Storageを使用
   - 動画圧縮の検討（15秒、最大ファイルサイズ）

2. **パフォーマンス**
   - 動画のプリロード戦略
   - メモリ管理

3. **UI/UX**
   - ダークモードのみ or ライト/ダークモード対応
   - アニメーション効果
   - ハプティックフィードバック
