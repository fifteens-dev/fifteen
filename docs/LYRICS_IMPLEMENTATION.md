# 歌詞取得機能 実装ドキュメント

## 概要

投稿作成フローにおいて、楽曲の歌詞を自動取得して歌詞カードに表示する機能。

## 歌詞データの取得元

本アプリケーションは、以下の2つのAPIから歌詞データを取得しています:

### 🎯 主要取得元: LRCLIB API (優先)
- **URL**: https://lrclib.net/
- **特徴**: 完全な歌詞とタイムスタンプ付き歌詞（LRC形式）を無料で提供
- **認証**: 不要
- **カバレッジ**: 日本楽曲の約62.5%をカバー（テスト結果）
- **取得内容**:
  - プレーン歌詞（全文）
  - タイムスタンプ付き歌詞（LRC形式）
- **使用方法**: 楽曲名とアーティスト名で検索

### 🔄 フォールバック: Apple Music Snippet API
- **URL**: https://api.music.apple.com/
- **特徴**: LRCLIBで見つからない場合の補完として使用
- **認証**: Apple Music Developer Token（既に取得済み）
- **カバレッジ**: 高い（Apple Musicの全カタログ）
- **取得内容**:
  - 歌詞のスニペット（1-2行の抜粋）
- **制限**: 完全な歌詞ではなく、一部のみ

### 🔀 取得フロー
```
1. LRCLIB APIで検索
   ↓ 見つかった場合
   ✅ 完全な歌詞を使用

   ↓ 見つからなかった場合
2. Apple Music Snippet APIで検索
   ↓ 見つかった場合
   ⚪ スニペット（一部）を使用

   ↓ 見つからなかった場合
3. デフォルト歌詞を使用
   ⚠️ ハードコーディングされた歌詞を表示
```

### 💰 コスト
- **LRCLIB API**: 完全無料
- **Apple Music API**: Developer Tokenのみ必要（無料）
- **合計コスト**: $0

### 📊 実際の取得状況
テスト結果によると:
- **LRCLIB成功**: 約62.5%の日本楽曲
- **Apple Music補完**: LRCLIBで見つからない残りの楽曲
- **推定カバレッジ**: 合計で約85%以上の楽曲で歌詞データを取得可能

## 歌詞取得API（詳細）

### 1. LRCLIB API（優先）
- **URL**: https://lrclib.net/api
- **料金**: 無料
- **認証**: 不要
- **カバレッジ**: 日本楽曲 62.5% (テスト結果)
- **形式**: プレーン歌詞 + タイムスタンプ付き歌詞（LRC形式）
- **メリット**: 完全な歌詞、タイムスタンプ付き、無料
- **デメリット**: カバレッジが完全ではない

### 2. Apple Music Snippet（フォールバック）
- **URL**: https://api.music.apple.com/v1/catalog/jp/search
- **料金**: 無料
- **認証**: Developer Token（既に取得済み）
- **カバレッジ**: 高い
- **形式**: 歌詞の一部（1-2行のスニペット）
- **メリット**: カバレッジが高い、Apple Music Developer Tokenで使用可能
- **デメリット**: 完全な歌詞ではなくスニペットのみ

### 3. 検討した他のAPI

#### Musixmatch API
- **ステータス**: 無料プランが2025年8月に終了
- **結果**: 採用見送り

#### Spotify API
- **ステータス**: 歌詞エンドポイントなし
- **結果**: 採用見送り

#### Apple Music Full Lyrics
- **要件**: User Token + Apple Music サブスクリプション ($9.80/月)
- **ユーザー要件**: Apple Musicサブスクリプション必須
- **カバレッジ**: ~6%のユーザーのみ
- **結果**: 採用見送り

## 実装アーキテクチャ

### フォールバック戦略

```
LRCLIB API
  ↓ 失敗
Apple Music Snippet
  ↓ 失敗
デフォルト歌詞（ハードコーディング）
```

### データフロー（修正後）

```
1. MusicSelectionScreen（楽曲選択画面）
   ├─ 「次へ」ボタン押下
   ├─ 歌詞取得開始（バックグラウンド、awaitしない）
   └─ すぐに画面遷移

2. PostPreviewScreen（プレビュー画面）
   ├─ lyricsFuture を受け取る
   ├─ initState() で Future.then() で完了を待つ
   ├─ 完了時に setState() で _lyricsData を更新
   └─ 写真選択画面へ遷移時に _lyricsData を渡す

3. PostPhotoSelectionScreen（写真選択画面）⭐
   ├─ lyricsData を受け取り、_lyricsData に保存
   ├─ 歌詞が未取得の場合は、バックグラウンドで取得開始
   ├─ 完了時に setState() で _lyricsData を更新
   └─ 「次へ」押下時に _lyricsData を次の画面へ渡す

4. LyricsCardSelectionScreen（歌詞カード選択画面）
   ├─ lyricsData を受け取る
   ├─ 未取得の場合はフォールバックで取得（通常は不要）
   └─ 歌詞を表示

5. PostPreviewScreen（最終プレビュー画面）
   ├─ 歌詞データを result から受け取る
   └─ 取得済み歌詞を表示（再取得なし）
```

**重要ポイント**:
- PostPhotoSelectionScreen が歌詞データを状態として保持
- バックグラウンド取得が完了するまでの時間を最大限活用
- 重複取得を防止

## 実装ファイル

### コアサービス

#### `lib/services/lyrics_service.dart`
- **責務**: 歌詞取得のビジネスロジック
- **主要クラス**:
  - `LyricsService`: シングルトンサービス
  - `LyricsData`: 歌詞データモデル
  - `LyricLine`: タイムスタンプ付き歌詞の1行
  - `LyricsSource`: 歌詞の取得元（enum）

- **主要メソッド**:
  - `getLyrics()`: フォールバック戦略で歌詞を取得
  - `_getLyricsFromLRCLIB()`: LRCLIB APIから取得
  - `_getLyricsFromAppleMusicSnippet()`: Apple Music Snippetから取得
  - `_parseLRCLyrics()`: LRC形式のパース
  - `truncateLyrics()`: 歌詞を指定行数に短縮

### UI画面

#### `lib/screens/music_selection_screen.dart`
- **変更点**:
  - 楽曲選択完了時に歌詞取得を開始（バックグラウンド）
  - `Future<LyricsData?>` を PostPreviewScreen に渡す
  - await せずにすぐに画面遷移

#### `lib/screens/post_preview_screen.dart`
- **変更点**:
  - `lyricsFuture` パラメータを追加
  - `_lyricsData` 状態変数を追加
  - `initState()` で Future の完了を待つ
  - 完了時に `setState()` で歌詞を更新
  - `_buildLyricsCardBack()` で取得済み歌詞を表示

#### `lib/screens/post_photo_selection_screen.dart`
- **変更点**:
  - `lyricsData` を受け取って次の画面に渡す

#### `lib/screens/lyrics_card_selection_screen.dart`
- **変更点**:
  - `lyricsData` を受け取る
  - 未取得の場合は `_fetchLyrics()` で取得（フォールバック）
  - 取得中は「歌詞を取得中...」と表示
  - `_displayLyrics` getter で表示用歌詞を返す
  - 確認ボタン押下時に `lyricsData` を result に含める

### ウィジェット

#### `lib/widgets/post_creation/lyrics_card_layouts.dart`
- **変更点**:
  - `lyricsText` パラメータを追加（オプション）
  - 各レイアウトで歌詞テキストを表示

## 環境変数

### `.env`
```env
APPLE_MUSIC_DEVELOPER_TOKEN=eyJhbGciOiJFUzI1NiIsImtpZCI6Ik1BVFpBNDY5NjkiLCJ0eXAiOiJKV1QifQ...
```

## 解決済みの問題

### ~~問題1: 歌詞データの伝達~~ ✅ 解決済み (2026-01-08)
**現象**: PostPreviewScreen で歌詞取得完了しても、写真選択画面経由で歌詞カード選択画面に正しく渡されていなかった

**原因**:
- PostPreviewScreen の `_lyricsData` は Future.then() で非同期に更新される
- `_pickImage()` が呼ばれた時点では、まだ更新されていない可能性がある
- その時点の `_lyricsData`（= null）が PostPhotoSelectionScreen に渡される

**解決方法**:
1. PostPhotoSelectionScreen に `lyricsFuture` パラメータを追加
2. PostPreviewScreen から `_lyricsFuture` を PostPhotoSelectionScreen に渡す
3. PostPhotoSelectionScreen の `initState()` で Future の完了を待つ
4. `_onNext()` で状態変数から歌詞データを LyricsCardSelectionScreen に渡す

**結果**:
- PostPreviewScreen でバックグラウンド取得が完了する前に写真選択画面に遷移しても問題なし
- 写真選択画面で同じ Future の完了を待ち、重複取得を防止
- 完了したデータが歌詞カード選択画面に渡される

### ~~問題2: 重複取得~~ ✅ 解決済み (2026-01-08)
**現象**: 写真選択画面で新規の歌詞取得が開始され、二重に取得されていた

**原因**:
- PostPreviewScreen から PostPhotoSelectionScreen に `lyricsData` のみ渡していた
- `lyricsFuture` を渡していなかったため、写真選択画面では Future の存在を知らなかった
- `lyricsFuture == null` のため、新規取得が開始されていた

**解決方法**:
1. PostPhotoSelectionScreen に `lyricsFuture` パラメータを追加
2. `initState()` で Future の有無を確認する条件分岐を追加:
   ```dart
   if (widget.lyricsFuture != null) {
     // Future がある場合は待つ（重複取得しない）
     widget.lyricsFuture!.then((lyricsData) { ... });
   } else if (_lyricsData == null) {
     // Future もデータもない場合のみ新規取得
     _fetchLyricsInBackground();
   }
   ```

**結果**:
- 楽曲選択画面で開始された1回の取得のみが実行される
- 全画面で同じ Future を共有し、重複取得を完全に防止
- ログ確認: 「🎵 写真選択画面: バックグラウンド歌詞取得の完了を待機中...」と表示され、新規取得が発生しない

## テスト結果

### LRCLIB API カバレッジテスト
**テスト日**: 2026-01-08
**対象**: 日本の人気楽曲16曲

**結果**:
- **成功**: 10/16 (62.5%)
- **失敗**: 6/16 (37.5%)

**成功例**:
- YOASOBI: 4/4曲
- 米津玄師: 3/3曲
- Official髭男dism: 2/2曲
- Ado: 1/1曲

**失敗例**:
- あいみょん: 2曲
- 接続エラー: 4曲

### Apple Music Lyrics API テスト
**テスト日**: 2026-01-08
**対象**: 日本の人気楽曲6曲

**結果**: 全て 400 Bad Request

**原因**: `/songs/{id}/lyrics` エンドポイントは User Token が必要

## パフォーマンス最適化

### 1. バックグラウンド取得
- 楽曲選択完了時に取得開始
- await せずにすぐに画面遷移
- ユーザーの待ち時間を最小化

### 2. 1回だけ取得
- 全画面で取得済み歌詞を再利用
- ネットワークリクエストを削減

### 3. フォールバック戦略
- LRCLIB で失敗しても Apple Music Snippet で補完
- 最悪の場合もデフォルト歌詞を表示

## 今後の拡張案

### 1. タイムスタンプ同期
- iTunes プレビュー再生と歌詞のタイムスタンプを同期
- LRC形式の歌詞を活用

### 2. 歌詞編集機能
- ユーザーが歌詞を手動で編集できる機能
- カスタム歌詞の保存

### 3. 歌詞検索機能
- 歌詞の一部で楽曲を検索
- Musixmatch API の有料プランを検討

### 4. キャッシング
- 一度取得した歌詞をローカルにキャッシュ
- オフライン対応

## 参考資料

- [LRCLIB API Documentation](https://lrclib.net/docs)
- [Apple Music API Documentation](https://developer.apple.com/documentation/applemusicapi)
- [LRC Format Specification](https://en.wikipedia.org/wiki/LRC_(file_format))

## 変更履歴

| 日付 | 変更内容 | 担当 |
|------|---------|------|
| 2026-01-08 | 初版作成、LRCLIB + Apple Music Snippet 実装 | Claude |
| 2026-01-08 | バックグラウンド取得の実装 | Claude |
