# Scripts

このディレクトリには、開発に役立つスクリプトが含まれています。

## Apple Music Developer Token Generator

Apple Music APIを使用するために必要なDeveloper Tokenを生成するPythonスクリプトです。

### 必要なもの

1. **Apple Developer Program**への加入
2. **Python 3.7+**
3. **PyJWT**ライブラリ: `pip install PyJWT`

### セットアップ手順

#### 1. MusicKit Keyの作成

1. [Apple Developer Account](https://developer.apple.com/account)にログイン
2. **Certificates, Identifiers & Profiles**に移動
3. 左メニューの**Keys**をクリック
4. **+ボタン**をクリックして新しいKeyを作成
5. Key名を入力（例: "MusicKit Key"）
6. **MusicKit**チェックボックスを有効化
7. **Continue** → **Register**をクリック
8. **.p8ファイル**をダウンロード（**このファイルは二度とダウンロードできません！**）
9. **Key ID**をメモ（10文字の英数字）

#### 2. Team IDの確認

1. Apple Developer Accountのページ右上に表示されています
2. または、**Membership**ページで確認できます
3. 10文字の英数字です

#### 3. Token生成

```bash
# PyJWTのインストール
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

#### 4. Tokenの設定

生成されたTokenを`.env`ファイルに追加します：

```bash
APPLE_MUSIC_DEVELOPER_TOKEN=eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IlhZWjEyMzQ1NjcifQ...
```

### オプション

- `--expiry-months`: Tokenの有効期限（デフォルト: 6ヶ月、最大: 6ヶ月）

```bash
python scripts/generate_apple_music_token.py \
    --team-id YOUR_TEAM_ID \
    --key-id YOUR_KEY_ID \
    --private-key-path /path/to/AuthKey_KEYID.p8 \
    --expiry-months 3
```

### 注意事項

⚠️ **セキュリティ**
- `.p8ファイル`は安全な場所に保管してください
- 生成されたTokenは`.env`ファイルに保存してください（`.gitignore`に含まれています）
- Tokenを公開リポジトリにコミットしないでください

📅 **有効期限**
- Developer Tokenは最大6ヶ月間有効です
- 期限切れ前に新しいTokenを生成してください
- 同じKey IDとTeam IDで何度でも生成できます

### トラブルシューティング

#### `ModuleNotFoundError: No module named 'jwt'`

```bash
pip install PyJWT
```

#### `❌ Error: Private key file not found`

`.p8ファイル`のパスが正しいか確認してください。

#### `❌ Error: Team ID must be 10 characters`

Team IDは正確に10文字である必要があります。Apple Developer Accountで確認してください。

### 参考資料

- [Apple Music API - Getting Keys and Creating Tokens](https://developer.apple.com/documentation/applemusicapi/getting_keys_and_creating_tokens)
- [MusicKit Documentation](https://developer.apple.com/documentation/musickit)
