# Apple Music API統合ガイド

このドキュメントでは、FifteenアプリにApple Music APIを統合する手順を説明します。

## 📋 目次

1. [前提条件](#前提条件)
2. [Developer Token生成](#developer-token生成)
3. [環境変数の設定](#環境変数の設定)
4. [MusicKit設定（iOS）](#musickit設定ios)
5. [使用方法](#使用方法)
6. [API機能](#api機能)
7. [トラブルシューティング](#トラブルシューティング)

---

## 前提条件

✅ **必要なもの:**
- Apple Developer Program アカウント（$99/年）
- macOS（トークン生成用）
- Python 3.7+ と PyJWT (`pip install PyJWT`)
- Xcode 13+（iOS開発の場合）

---

## Developer Token生成

### ステップ1: MusicKit Keyの作成

1. [Apple Developer Portal](https://developer.apple.com/account)にログイン
2. **Certificates, Identifiers & Profiles** に移動
3. 左メニューの **Keys** をクリック
4. **+ ボタン** で新しいKeyを作成
5. Key名を入力（例: "Fifteen MusicKit Key"）
6. **MusicKit** チェックボックスを有効化
7. **Continue** → **Register** をクリック
8. **.p8ファイル** をダウンロード
   - ⚠️ **重要**: このファイルは二度とダウンロードできません！安全に保管してください
9. **Key ID**（10文字）をメモ

### ステップ2: Team IDの確認

1. Apple Developer Accountページ右上に表示されています
2. または **Membership** ページで確認
3. 10文字の英数字をメモ

### ステップ3: Developer Tokenの生成

```bash
# PyJWTのインストール（初回のみ）
pip install PyJWT

# Tokenの生成
python scripts/generate_apple_music_token.py \
    --team-id YOUR_TEAM_ID \
    --key-id YOUR_KEY_ID \
    --private-key-path /path/to/AuthKey_KEYID.p8

# 例:
python scripts/generate_apple_music_token.py \
    --team-id ABCDE12345 \
    --key-id XYZ1234567 \
    --private-key-path ~/Downloads/AuthKey_XYZ1234567.p8
```

生成されたトークンをコピーしてください。

---

## 環境変数の設定

`.env`ファイルにDeveloper Tokenを追加します：

```bash
# .envファイルを作成（存在しない場合）
cp .env.example .env

# エディタで開いて、以下を追加:
APPLE_MUSIC_DEVELOPER_TOKEN=eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI...
```

⚠️ **セキュリティ注意:**
- `.env`ファイルは `.gitignore` に含まれています
- トークンを公開リポジトリにコミットしないでください
- トークンは6ヶ月間有効です（期限前に再生成してください）

---

## MusicKit設定（iOS）

### Info.plist設定

`ios/Runner/Info.plist`に以下が追加されています：

```xml
<key>NSAppleMusicUsageDescription</key>
<string>Apple Musicの楽曲を検索・再生するために使用します</string>
```

この説明文はユーザーに許可を求める際に表示されます。

### Capabilities設定（必要に応じて）

Xcodeで追加の設定が必要な場合があります：

1. Xcodeで `ios/Runner.xcworkspace` を開く
2. **Runner** プロジェクトを選択
3. **Signing & Capabilities** タブ
4. **+ Capability** をクリック
5. **App Services** → **MusicKit** を追加

---

## 使用方法

### 基本的な検索（Developer Tokenのみ）

```dart
import 'package:fifteen/services/apple_music_service.dart';

final appleMusic = AppleMusicService();

// 楽曲を検索
final tracks = await appleMusic.searchTracks('米津玄師');

// 歌詞を取得
final lyrics = await appleMusic.getLyrics(trackId);
```

### User Token認証（個人データアクセス）

```dart
// MusicKit認証をリクエスト
final success = await appleMusic.login();

if (success) {
  // ユーザーのライブラリから楽曲を取得
  final savedTracks = await appleMusic.getSavedTracks();
}
```

### MusicServiceManager経由（推奨）

```dart
import 'package:fifteen/services/music_service_manager.dart';

final musicManager = MusicServiceManager();

// Apple Musicを選択
await musicManager.setSelectedService(MusicServiceType.appleMusic);

// 楽曲を検索
final tracks = await musicManager.searchTracks('YOASOBI');

// 歌詞を取得
final lyrics = await musicManager.getLyrics(trackId);
```

---

## API機能

### 実装済み機能

✅ **楽曲検索** - `searchTracks(query)`
- Developer Tokenで利用可能
- 日本のカタログから検索

✅ **歌詞取得** - `getLyrics(trackId)`
- Developer Tokenで利用可能
- TTML形式の歌詞をプレーンテキストに変換

✅ **トップチャート** - `getTopCharts()`
- 日本のトップチャートを取得

✅ **プレイリスト取得** - `getPlaylistTracks(playlistId)`
- キュレーションプレイリストから楽曲を取得

✅ **MusicKit認証** - `login()`
- iOS用のUser Token認証
- ユーザーの個人データにアクセス可能

### 制限事項

⚠️ **Web版の制限:**
- MusicKit JS の実装が必要（現在未実装）
- Developer Tokenのみで基本機能は利用可能

⚠️ **Android版の制限:**
- MusicKitはiOS専用
- Developer Tokenのみで基本機能は利用可能

---

## トラブルシューティング

### 🔴 "Developer Tokenが設定されていません"

**原因**: `.env`ファイルにトークンが設定されていない

**解決策**:
```bash
# .envファイルを確認
cat .env | grep APPLE_MUSIC_DEVELOPER_TOKEN

# トークンが空の場合は再生成
python scripts/generate_apple_music_token.py --team-id ... --key-id ... --private-key-path ...
```

### 🔴 "Token validation failed" (401エラー)

**原因**: トークンが無効または期限切れ

**解決策**:
1. トークンの有効期限を確認（最大6ヶ月）
2. 新しいトークンを生成
3. `.env`ファイルを更新
4. アプリを再起動

### 🔴 "この楽曲には歌詞がありません" (404エラー)

**原因**: Apple Musicに歌詞データが登録されていない楽曲

**解決策**:
- これは正常な動作です
- すべての楽曲に歌詞があるわけではありません

### 🔴 iOS: "MusicKit authorization failed"

**原因**: Info.plistの設定またはユーザーの拒否

**解決策**:
1. Info.plistに`NSAppleMusicUsageDescription`が追加されているか確認
2. デバイスの設定 → プライバシー → Media & Apple Music でアプリの許可を確認
3. アプリを削除して再インストール

### 🔴 "ModuleNotFoundError: No module named 'jwt'"

**原因**: PyJWTがインストールされていない

**解決策**:
```bash
pip install PyJWT
```

---

## 参考資料

### Apple公式ドキュメント

- [Apple Music API Overview](https://developer.apple.com/documentation/applemusicapi)
- [Getting Keys and Creating Tokens](https://developer.apple.com/documentation/applemusicapi/getting_keys_and_creating_tokens)
- [Lyrics API](https://developer.apple.com/documentation/applemusicapi/get_a_catalog_song_s_lyrics)
- [MusicKit for iOS](https://developer.apple.com/documentation/musickit)

### 関連ファイル

- `lib/services/apple_music_service.dart` - Apple Music APIサービス
- `lib/services/musickit_service.dart` - MusicKit認証サービス
- `lib/services/music_service_manager.dart` - 統合音楽サービスマネージャー
- `scripts/generate_apple_music_token.py` - トークン生成スクリプト
- `ios/Runner/AppDelegate.swift` - iOS MusicKit実装

---

## よくある質問

### Q: Developer Tokenの有効期限は？

A: 最大6ヶ月です。期限前に新しいトークンを生成してください。

### Q: User Tokenとの違いは？

A:
- **Developer Token**: 公開データ（検索、チャート）にアクセス可能
- **User Token**: ユーザーの個人データ（ライブラリ、プレイリスト）にアクセス可能

### Q: Spotifyとの併用は可能？

A: はい。`MusicServiceManager`で切り替え可能です。

### Q: 商用利用は可能？

A: Apple Developer Program規約に従ってください。詳細は[Apple Developer Agreement](https://developer.apple.com/support/terms/)を参照。

---

## 次のステップ

1. ✅ Developer Tokenを生成
2. ✅ `.env`に設定
3. ⬜️ アプリをビルド・実行
4. ⬜️ 楽曲検索をテスト
5. ⬜️ 歌詞取得をテスト
6. ⬜️ iOS実機でMusicKit認証をテスト

---

**作成日**: 2026-01-06
**最終更新**: 2026-01-06
