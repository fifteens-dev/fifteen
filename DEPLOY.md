# デプロイガイド

## GitHub Pagesへのデプロイ方法

### 方法1: 手動デプロイ（スクリプト使用）

.envファイルを削除せずに安全にデプロイできます。

```bash
./deploy-gh-pages.sh
```

このスクリプトは以下を実行します：
1. Flutter Webをビルド
2. gh-pages専用のworktreeを作成
3. ビルド成果物をコピー
4. GitHub Pagesにプッシュ
5. worktreeをクリーンアップ

**メリット：**
- mainブランチのファイルに一切触れない
- .envファイルが削除されない
- ワンコマンドで完了

### 方法2: GitHub Actions（自動デプロイ）

mainブランチにpushするだけで自動的にデプロイされます。

**セットアップ手順：**

1. GitHubリポジトリのSettings → Secrets and variables → Actions に移動

2. 以下のSecretsを追加：
   - `SPOTIFY_CLIENT_ID`: Spotify Client ID
   - `SPOTIFY_CLIENT_SECRET`: Spotify Client Secret
   - `SPOTIFY_REDIRECT_URI`: リダイレクトURI
   - `APPLE_MUSIC_DEVELOPER_TOKEN`: Apple Music Developer Token

3. mainブランチにpushすると自動的にデプロイ開始

**メリット：**
- 完全自動
- 手動操作不要
- 機密情報をGitHub Secretsで安全に管理

### デプロイURL

https://fifteens-dev.github.io/fifteen/

## トラブルシューティング

### .envファイルが見つからないエラー

手動デプロイの場合、ルートディレクトリに.envファイルが必要です。

```bash
cp .env.example .env
# .envファイルを編集して実際の認証情報を入力
```

### GitHub Actionsでデプロイが失敗

1. Secretsが正しく設定されているか確認
2. Actions → 失敗したworkflow → 詳細を確認
3. 必要に応じてSecrets値を更新

### GitHub Pagesが表示されない

1. リポジトリのSettings → Pages を確認
2. Source: "Deploy from a branch"
3. Branch: "gh-pages" / "(root)"
4. 数分待ってから再度アクセス
