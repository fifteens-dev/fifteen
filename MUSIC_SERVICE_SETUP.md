# 音楽サービス連携設定ガイド

このドキュメントでは、SpotifyとApple Musicの連携機能を有効にするための設定手順を説明します。

## Spotify設定

### 1. Spotify Developer Dashboardでリダイレクト URIを追加

1. [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)にアクセス
2. アプリケーションを選択
3. "Settings"をクリック
4. "Redirect URIs"セクションまでスクロール
5. 以下のURIを追加：
   ```
   fifteenapp://callback
   ```
6. "Save"をクリック

### 2. スコープ

アプリケーションは以下のスコープを要求します：
- `user-read-private` - ユーザーの基本情報へのアクセス
- `user-read-email` - ユーザーのメールアドレスへのアクセス
- `playlist-read-private` - プライベートプレイリストへのアクセス
- `playlist-read-collaborative` - 共同プレイリストへのアクセス
- `user-library-read` - 保存した曲へのアクセス

### 3. 環境変数

`.env`ファイルに以下の認証情報が設定されていることを確認してください：
```
SPOTIFY_CLIENT_ID=your_client_id_here
SPOTIFY_CLIENT_SECRET=your_client_secret_here
```

## Apple Music設定

### 1. Apple Developer Program登録

Apple Music APIを使用するには、Apple Developer Program（年間$99）への登録が必要です。

### 2. MusicKit Identifierの作成

1. [Apple Developer Portal](https://developer.apple.com/account)にアクセス
2. "Certificates, Identifiers & Profiles"を選択
3. "Identifiers"をクリック
4. "+"ボタンをクリックして新しいIdentifierを作成
5. "MusicKit Identifiers"を選択
6. アプリの情報を入力して登録

### 3. Developer Tokenの生成

Apple Music APIには、JWT形式のDeveloper Tokenが必要です。

#### オプション1: オンラインツールを使用（開発環境のみ）
- [Apple Music Token Generator](https://music-developer-tools.apple.com/)を使用
- 生成されたトークンを`.env`ファイルに追加

#### オプション2: 秘密鍵から生成（本番環境推奨）
1. Apple Developer Portalで秘密鍵を生成
2. 秘密鍵ファイル(`.p8`)をダウンロード
3. バックエンドサーバーまたはローカルスクリプトでJWTトークンを生成

### 4. 環境変数

`.env`ファイルに以下を追加：
```
APPLE_MUSIC_DEVELOPER_TOKEN=your_developer_token_here
```

**注意**: Developer Tokenの有効期限は最大6ヶ月です。定期的に更新する必要があります。

## 使用方法

### 音楽サービスの選択

1. アプリを起動
2. プロフィール画面または設定画面から「音楽サービス連携」を選択
3. SpotifyまたはApple Musicを選択
4. 認証フローに従ってログイン

### 連携後の機能

連携後、以下の機能が利用可能になります：

#### Spotify連携時
- ✅ Recommendations APIによる高精度なおすすめ楽曲
- ✅ キュレーションされたプレイリストへのアクセス
- ✅ プレビュー音源の再生（30秒）
- ✅ ユーザーの保存した曲の取得

#### Apple Music連携時
- ✅ Apple Musicトップチャートへのアクセス
- ✅ キュレーションされたプレイリストへのアクセス
- ✅ プレビュー音源の再生（30秒）
- ✅ カタログ検索機能

### 連携解除

1. 音楽サービス連携画面を開く
2. 画面下部の「連携を解除」ボタンをタップ
3. 連携が解除され、Client Credentials Flow（基本検索）に戻ります

## トラブルシューティング

### Spotifyログインが失敗する

1. Spotify Developer DashboardでリダイレクトURIが正しく設定されているか確認
2. `.env`ファイルのClient IDとClient Secretが正しいか確認
3. アプリを再起動

### Apple Musicが動作しない

1. Developer Tokenが正しく設定されているか確認
2. Developer Tokenの有効期限が切れていないか確認
3. Apple Developer Programに登録されているか確認

### カスタムURLスキームが動作しない

#### iOS
- `ios/Runner/Info.plist`に`CFBundleURLTypes`が正しく追加されているか確認

#### Android
- `android/app/src/main/AndroidManifest.xml`にintent-filterが正しく追加されているか確認

## 開発者向け情報

### ファイル構成

```
lib/
├── models/
│   └── music_service_type.dart          # 音楽サービスの種類を定義
├── services/
│   ├── spotify_auth_service.dart        # Spotify OAuth認証
│   ├── apple_music_service.dart         # Apple Music API
│   ├── music_service_manager.dart       # 統一管理クラス
│   └── spotify_service.dart             # Spotify API（拡張済み）
└── screens/
    └── music_service_selection_screen.dart  # 音楽サービス選択UI
```

### 認証フロー

#### Spotify (Authorization Code Flow)
1. ユーザーがSpotifyログインを選択
2. `flutter_web_auth`でSpotifyの認証ページを開く
3. ユーザーがアプリを承認
4. 認証コードを取得
5. アクセストークンとリフレッシュトークンを取得
6. `flutter_secure_storage`でトークンを保存

#### Apple Music (Developer Token)
1. `.env`からDeveloper Tokenを読み込み
2. APIリクエストのヘッダーに`Bearer`トークンを追加
3. カタログAPIでデータを取得

### API優先順位

`MusicServiceManager`は以下の優先順位でAPIを使用します：

1. **ユーザーが選択したサービス**（認証済みの場合）
2. **Spotify Client Credentials Flow**（フォールバック）
3. **検索クエリ**（最終手段）

これにより、認証なしでも基本的な機能を使用できます。
