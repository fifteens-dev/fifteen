# Apple Music統合 実装状況

## 実装日
2026-01-15

## 概要
Fifteenアプリのpple Music API統合を改善・完成させました。

## 実装済み機能

### 1. iOS Native実装（MusicKit）

#### AppDelegate.swift の改善
- ✅ iOS 15未満向けのフォールバックを追加
- ✅ `requestAuthorization()` - iOS版判定を追加、エラーメッセージを改善
- ✅ `getAuthorizationStatus()` - iOS版判定を追加
- ✅ `getUserToken()` - iOS版判定を追加、エラーハンドリングを改善

**変更内容:**
```swift
// Before: @available(iOS 15.0, *)のみで制限
private func requestMusicKitAuthorization(result: @escaping FlutterResult) {
  // iOS 15未満では実行時エラー
}

// After: ランタイムチェックを追加
private func requestMusicKitAuthorization(result: @escaping FlutterResult) {
  if #available(iOS 15.0, *) {
    // MusicKit処理
  } else {
    result(FlutterError(...)) // エラーを返す
  }
}
```

**メリット:**
- iOS 15未満のデバイスでもクラッシュしない
- 明確なエラーメッセージを表示

### 2. AppleMusicService の改善

#### getSavedTracks() の完全実装
- ✅ User Token認証を使用したライブラリ楽曲取得を実装
- ✅ Developer Token + User Tokenの両方を使用
- ✅ 認証失敗時の自動トークンクリア
- ✅ エラーハンドリングの強化

**実装内容:**
```dart
Future<List<TrackModel>> getSavedTracks({int limit = 50}) async {
  // User Tokenチェック
  if (_userToken == null) {
    _userToken = await _storage.read(key: _userTokenKey);
  }

  // Developer Tokenチェック
  if (_developerToken == null) {
    _developerToken = _envDeveloperToken.isNotEmpty
        ? _envDeveloperToken
        : await _storage.read(key: _developerTokenKey);
  }

  // Apple Music Library APIにアクセス
  final response = await http.get(
    Uri.parse('https://api.music.apple.com/v1/me/library/songs?limit=$limit'),
    headers: {
      'Authorization': 'Bearer $_developerToken',
      'Music-User-Token': _userToken!,
    },
  );

  // レスポンス処理...
}
```

**エンドポイント:**
- `GET /v1/me/library/songs` - ユーザーのライブラリから楽曲を取得

**エラーハンドリング:**
- 401: User Token期限切れ → 自動削除して再ログインを促す
- その他: 詳細なエラーログを出力

### 3. MusicKitService の改善

#### プラットフォーム判定の強化
- ✅ Web版サポート状態を正確に反映（現在は未実装のため`false`を返す）
- ✅ エラーメッセージの詳細化
- ✅ iOS版要件の明確化（iOS 15+）

**変更内容:**
```dart
// Before: Web版で true を返していた
bool get isSupported {
  if (kIsWeb) {
    return true; // 誤解を招く
  }
  return Platform.isIOS;
}

// After: 正確な状態を反映
bool get isSupported {
  if (kIsWeb) {
    print('⚠️ MusicKit JS support is not yet implemented for Web');
    return false; // Web版は未実装
  }
  return Platform.isIOS;
}
```

#### エラーメッセージの改善
- ✅ iOS版判定エラー時の詳細メッセージ
- ✅ User Token取得失敗時のヒント表示
- ✅ トークン長の確認ログ

```dart
// User Token取得時のログ例
✅ Got user token (length: 1234)
💡 Hint: Make sure you have called requestAuthorization() first
```

## 統合フロー

### 1. Developer Token認証（基本機能）
Developer Tokenのみで利用可能な機能:
- ✅ 楽曲検索 (`searchTracks`)
- ✅ プレイリスト取得 (`getPlaylistTracks`)
- ✅ トップチャート (`getTopCharts`)
- ✅ 歌詞取得 (`getLyrics`) - 一部楽曲のみ

### 2. User Token認証（個人データアクセス）
Developer Token + User Tokenで利用可能な機能:
- ✅ ユーザーライブラリ楽曲取得 (`getSavedTracks`)
- ✅ 完全な歌詞データアクセス
- ✅ プレイリスト作成・編集（将来実装可能）

**認証フロー:**
```
1. MusicKitService.requestAuthorization()
   ↓
2. ユーザーがApple Music連携を許可
   ↓
3. MusicKitService.getUserToken()
   ↓
4. User Tokenを取得・保存
   ↓
5. AppleMusicService.getSavedTracks()でライブラリにアクセス
```

## テスト方法

### Android/Web（Developer Tokenのみ）
```bash
# Androidエミュレータで起動
flutter emulators --launch Medium_Phone
flutter run -d emulator-5554

# テスト項目
1. 音楽サービス選択でApple Musicを選択
2. 楽曲検索を試す（Developer Tokenのみで動作）
3. トップチャートを表示
```

### iOS実機（User Token認証含む）
```bash
# iOS実機を接続
flutter devices

# iOS実機でビルド・実行
flutter run -d <iOS-device-id>

# テスト項目
1. 音楽サービス選択でApple Musicを選択
2. MusicKit認証ダイアログが表示されることを確認
3. 許可後、User Tokenが取得されることを確認
4. マイプレイリストタブで保存済み楽曲が表示されることを確認
```

**注意事項:**
- iOS 15.0以上のデバイスが必要
- Apple Music登録アカウントが必要（無料トライアルでも可）
- Developer Tokenが`.env`ファイルに設定されていること

## 制限事項と今後の拡張

### 現在の制限
- ⚠️ iOS 15未満では利用不可（iOS 15+が必要）
- ⚠️ Web版はMusicKit JS未実装
- ⚠️ Android版はMusicKit非対応（Developer Tokenのみ）

### 将来の拡張案
- [ ] Web版MusicKit JSの実装
- [ ] プレイリスト作成・編集機能
- [ ] おすすめ楽曲取得の改善
- [ ] 完全な歌詞データの統合（User Token使用）

## 関連ファイル

### iOS Native
- `ios/Runner/AppDelegate.swift` - MusicKit Method Channel実装

### Dart Services
- `lib/services/apple_music_service.dart` - Apple Music API統合
- `lib/services/musickit_service.dart` - MusicKit認証ラッパー
- `lib/services/music_service_manager.dart` - 音楽サービス統合管理

### UI Screens
- `lib/screens/music_connection_screen.dart` - オンボーディング時の接続画面
- `lib/screens/music_service_selection_screen.dart` - 設定画面での切り替え

### ドキュメント
- `docs/APPLE_MUSIC_SETUP.md` - セットアップガイド
- `test/apple_music_user_token_lyrics_test.md` - User Token調査結果
- `MUSIC_SERVICE_SETUP.md` - 音楽サービス全般のセットアップ

## 参考資料

### Apple公式ドキュメント
- [MusicKit Documentation](https://developer.apple.com/documentation/musickit)
- [Apple Music API](https://developer.apple.com/documentation/applemusicapi)
- [MusicUserTokenProvider](https://developer.apple.com/documentation/musickit/musicusertokenprovider)

### その他
- [Flutter Method Channel](https://docs.flutter.dev/platform-integration/platform-channels)
- [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)
