# Apple Music歌詞取得に関する調査結果

## 調査日
2026-01-07

## 重要な発見

### 1. 歌詞データへのアクセス制限

Apple Music APIの歌詞エンドポイントは存在しますが、以下の制限があります：

```
エラーコード: 40012
エラーメッセージ: "Insufficient Permissions"
詳細: "'lyrics' entities require permissions that are not in the request"
```

### 2. Developer Tokenのみでは不十分

- Developer Token単独では歌詞の完全なテキストにアクセスできない
- `include=lyrics` パラメータを使用すると400エラーが返される
- `/songs/{id}/lyrics` エンドポイントも400エラーを返す

### 3. 取得できるもの

#### ✅ 歌詞スニペット（検索結果内）
```dart
// 検索APIで with=lyrics パラメータを使用
final url = 'https://api.music.apple.com/v1/catalog/jp/search'
    '?term=YOASOBI'
    '&types=songs'
    '&with=lyrics';

// レスポンス例
{
  "meta": {
    "snippets": [
      {
        "kind": "lyric",
        "text": "二人今、夜に駆け出していく"  // 歌詞の一部
      }
    ]
  }
}
```

#### ✅ 歌詞の有無フラグ
```dart
// Song APIレスポンス
{
  "attributes": {
    "hasLyrics": true,  // この楽曲には歌詞がある
    // ... other attributes
  }
}
```

### 4. 必要な追加実装

完全な歌詞を取得するには、以下のいずれかが必要：

#### オプション1: User Token認証（推奨）
```dart
// MusicKit経由でUser Tokenを取得
final status = await MusicKitService().requestAuthorization();
if (status == 'authorized') {
  final userToken = await MusicKitService().getUserToken();

  // User TokenとDeveloper Tokenの両方を使ってリクエスト
  final response = await http.get(
    Uri.parse('https://api.music.apple.com/v1/catalog/jp/songs/$trackId?include=lyrics'),
    headers: {
      'Authorization': 'Bearer $developerToken',
      'Music-User-Token': userToken,  // User Tokenを追加
    },
  );
}
```

#### オプション2: ISRCコードで外部サービス利用
```dart
// Apple Music APIから取得できる情報
final isrc = song['attributes']['isrc'];  // 例: "JPP301900716"

// ISRCコードを使って以下のサービスから歌詞を取得
// - Musixmatch API（有料）
// - LRCLIB（無料、オープンソース）
// - Spotify API（Spotifyの楽曲のみ）
```

## 次のステップ

### iOS実機でのテストが必要
User Token認証はiOSデバイス上でのみ完全に機能します：

1. iOSデバイスでアプリを起動
2. MusicKit認証をリクエスト
3. ユーザーがApple Music登録を許可
4. User Tokenを取得
5. Developer Token + User Tokenで歌詞APIにアクセス

### テスト手順
```bash
# 1. iOSデバイスを接続
flutter devices

# 2. アプリをビルド＆実行
flutter run -d <device-id>

# 3. MusicKit認証をトリガー（アプリ内で実装）
# 4. 歌詞取得をテスト
```

## 結論

### ✅ 実装可能
- **歌詞スニペット**: Developer Tokenのみで取得可能
- **hasLyricsフラグ**: Developer Tokenのみで取得可能

### ⚠️ 要追加実装
- **完全な歌詞**: User Token認証が必要
  - iOS実機でのテストが必須
  - ユーザーのApple Music登録が必要
  - MusicKitServiceの実装は完了済み

### ❌ 現時点で不可能
- Developer Tokenのみでの完全な歌詞取得

## 代替案：外部サービスの利用

もしUser Token認証が複雑すぎる場合：

1. **無料オプション**: LRCLIB API
   - https://lrclib.net/
   - ISRCコードで歌詞を検索
   - API制限あり

2. **有料オプション**: Musixmatch API
   - 既に実装済み（`lib/services/musixmatch_service.dart`）
   - 高精度な歌詞データ
   - 月額料金が必要

## 参考情報

- [MusicUserTokenProvider Documentation](https://developer.apple.com/documentation/musickit/musicusertokenprovider)
- [LyricFever GitHub](https://github.com/aviwad/LyricFever) - Apple Music歌詞を扱う実装例
- ISRCコード: 楽曲固有の国際標準識別コード（Apple Music APIレスポンスに含まれる）
