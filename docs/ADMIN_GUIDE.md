# 管理者の概要

このドキュメントでは、Fifteenアプリの管理者機能について説明します。

## 目次

1. [管理者とは](#管理者とは)
2. [管理者になる方法](#管理者になる方法)
3. [管理者機能](#管理者機能)
4. [管理者パネルへのアクセス](#管理者パネルへのアクセス)

---

## 管理者とは

管理者は、通常のユーザーには許可されていない特別な機能にアクセスできるユーザーです。現在、管理者には以下の権限があります：

- 全ユーザーへの一斉通知の送信
- Vibeお題の作成・編集・削除

---

## 管理者になる方法

管理者権限は、Firebase Cloud Firestoreで直接設定する必要があります。

### 手順

1. **Firebase Console にアクセス**
   - https://console.firebase.google.com にログイン
   - Fifteenプロジェクトを選択

2. **Firestore Database を開く**
   - 左側のメニューから「Firestore Database」をクリック

3. **users コレクションを開く**
   - `users` コレクションをクリック
   - 管理者にしたいユーザーのドキュメント（ユーザーID）を選択

4. **isAdmin フィールドを追加**
   - 「フィールドを追加」ボタンをクリック
   - 以下の情報を入力：
     - **フィールド名**: `isAdmin`
     - **タイプ**: `boolean`
     - **値**: `true`
   - 保存をクリック

### データ構造

```
Firestore
└── users (コレクション)
    └── {userId} (ドキュメント)
        ├── username: "ユーザー名"
        ├── name: "表示名"
        ├── isAdmin: true  ← このフィールド
        ├── profileImageUrl: "..."
        └── ...
```

### 注意事項

- `isAdmin` フィールドが存在しないか `false` の場合、そのユーザーは管理者ではありません
- 管理者権限の付与は慎重に行ってください
- 本番環境では、セキュリティルールで管理者操作を保護することを推奨します

---

## 管理者機能

### 1. 一斉通知

全ユーザーに対してプッシュ通知を送信できます。

#### 機能詳細

| 項目 | 説明 |
|------|------|
| タイトル | 通知のタイトル（必須） |
| 本文 | 通知の本文（必須） |
| 通知タイプ | お知らせ / Vibe関連 / アップデート / イベント |

#### 送信フロー

1. タイトルと本文を入力
2. 通知タイプを選択
3. 「通知を送信」ボタンをタップ
4. 確認ダイアログで内容を確認
5. 「送信」をタップ

#### データ保存先

- 一斉通知履歴: `broadcast_notifications` コレクション
- 各ユーザーへの通知: `users/{userId}/notifications` サブコレクション

### 2. Vibeお題管理

毎日のVibeお題を作成・管理できます。

#### 機能詳細

| 操作 | 説明 |
|------|------|
| 作成 | 新しいお題を追加（タイトル、実施日を指定） |
| 編集 | 既存のお題のタイトルや日付を変更 |
| 削除 | お題を削除（確認ダイアログあり） |

#### お題の状態（ステータス）

| ステータス | 説明 |
|-----------|------|
| voting | 投票受付中（翌日以降のお題候補） |
| active | アクティブ（今日のお題） |
| archived | アーカイブ済み（過去のお題） |

#### お題作成フロー

1. 「新規Vibeお題」セクションでタイトルを入力
2. 実施日を選択（デフォルトは翌日）
3. 「お題を作成」ボタンをタップ

#### データ保存先

- Vibeお題: `vibe_topics` コレクション

---

### 3. 集計（時間軸は「15s Day」）

集計タブの**日次指標はすべて暦日（0:00 区切り）ではなく「15s Day」**で数える。

> **15s Day** = その日の Music Memory 通知が来てから、次の通知が来るまで。
> 例: 9/2 の 15s Day = 9/2 の通知(19:00) 〜 9/3 の通知。

対象は DL数 / DAU / 投稿者数 / 投稿完了数 / D1・D7 継続率、および詳細画面の
折れ線グラフ。MAU も「その月に属する 15s Day」で月をまたぐ
（8/31 19:00 開始のサイクルは 8 月扱い）。累計値と音楽サービス別は時間軸に依らない。

#### 境界の履歴

境界は `music_memory_cycles/{YYYY-MM-DD}` に `notifiedAt` として蓄積される
（通知発火時に Functions が書き込む）。過去分は
`backfillMusicMemoryCycles`（管理者 callable）で `notifications` の
music_memory 通知から復元できる。集計タブに履歴が 8 件未満のときは
「過去の境界を復元」ボタンが出る。

- D1 は 2 件、D7 は 8 件の境界が必要
- 境界が無い期間はグラフに点が出ない（0 ではなく欠測として扱う）

#### 起動計測

`app_open_events/{uid}_{cycleKey}` が 1 ユーザー 1 サイクル 1 件。
集計時は日付キーではなく `createdAt` がどの窓に入るかで判定するため、
暦日キーだった旧データとも混在して正しく数えられる（ただし通知前後に
2 回開いたケースは旧データでは 1 件にまとまるため、過去分は僅かに少なめに出る）。

### 4. 音楽サービスの連携スタンプ

利用中の音楽サービスは `users` に「スタンプ」として刻まれる。

刻むタイミングは 2 つ:

1. **連携操作時** — Apple Music / Spotify の連携・解除で必ず刻む（恒久）
2. **アプリ起動時** — そのユーザーを**まだ一度も刻んでいないときだけ**。
   一度刻めば端末に記録が残り、以降の起動では Firestore に一切アクセスしない。
   スタンプ対応前からいる既存ユーザーを埋めるための処理なので、行き渡れば
   自然に消える（切り替え作業も再リリースも不要）。

| フィールド | 内容 |
|---|---|
| `musicService` | 現在の連携先（`appleMusic` / `spotify` / `none`） |
| `musicServiceUpdatedAt` | 最後に確認した時刻 |
| `musicServiceFirst` / `musicServiceFirstAt` | 最初に記録した連携先とその時刻 |
| `musicServicePrevious` | 直前の連携先（乗り換えたときだけ入る） |
| `musicServiceChangedAt` | 直近の乗り換え時刻 |
| `musicServiceSwitchCount` | 乗り換え回数 |
| `musicServiceHistory` | `{service, at}` の履歴 |

集計タブの「音楽サービス別」はこのスタンプ**だけ**を根拠に分類する。
「未取得」はスタンプ対応前のバージョンのままのユーザーで、アップデート後に
一度アプリを開けば分類される。乗り換えたユーザーは「サービス乗り換え」の
一覧に `前 → 今は ◯◯` の形で出る。

#### 投稿から連携先は判定できない

`users.musicServiceInferred` に投稿のアートワーク配信元
（Apple = `mzstatic.com` / Spotify = `i.scdn.co`）を記録しているが、
これは**連携先とは一致しない**ので分類には使わない。理由:

- 未連携ユーザーの**検索**は Spotify にフォールバックする
  （`MusicServiceManager.searchTracks` の `none` 分岐）
- **おすすめ**は連携先に関わらず全員 Apple Music のチャートを引く
  （`getRecommendedTracks`）

そのため集計タブでは「参考: 投稿の楽曲取得元」として別枠に、
注意書き付きで表示している。

## 管理者パネルへのアクセス

### アクセス方法

1. アプリにログイン（管理者権限を持つアカウントで）
2. 画面右上の設定アイコンをタップ
3. 設定画面をスクロール
4. 「管理者」セクションの「管理者パネル」をタップ

### 画面構成

管理者パネルは2つのタブで構成されています：

```
┌─────────────────────────────────────┐
│          管理者パネル                │
├─────────────────┬───────────────────┤
│    一斉通知     │     Vibeお題      │
├─────────────────┴───────────────────┤
│                                     │
│         （選択したタブの内容）        │
│                                     │
└─────────────────────────────────────┘
```

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `lib/services/admin_service.dart` | 管理者サービス（権限チェック、通知送信、お題管理） |
| `lib/screens/admin/admin_screen.dart` | 管理者パネル画面 |
| `lib/screens/admin/broadcast_notification_tab.dart` | 一斉通知タブ |
| `lib/screens/admin/vibe_topic_management_tab.dart` | Vibeお題管理タブ |
| `lib/models/user_model.dart` | ユーザーモデル（isAdminフィールド） |
| `lib/models/vibe_topic_model.dart` | Vibeお題モデル |

---

## セキュリティに関する注意

### 推奨されるFirestoreセキュリティルール

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // 管理者かどうかをチェックする関数
    function isAdmin() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
    }

    // 一斉通知コレクション（管理者のみ書き込み可能）
    match /broadcast_notifications/{notificationId} {
      allow read: if request.auth != null;
      allow write: if isAdmin();
    }

    // Vibeお題コレクション（管理者のみ書き込み可能）
    match /vibe_topics/{topicId} {
      allow read: if request.auth != null;
      allow write: if isAdmin();
    }
  }
}
```

---

## トラブルシューティング

### 管理者パネルが表示されない

1. Firebase Consoleで `isAdmin: true` が正しく設定されているか確認
2. アプリを完全に終了して再起動
3. ログアウトして再ログイン

### 通知が送信できない

1. 管理者権限があるか確認
2. インターネット接続を確認
3. Firebaseのセキュリティルールを確認

### お題が作成できない

1. タイトルが入力されているか確認
2. 日付が今日以降か確認
3. Firebaseのセキュリティルールを確認
