# Live Activity（ロック画面の「今日のMusic Memory」）セットアップ

iOS 限定。ロック画面 / 通知センター / Dynamic Island に貼り付く 3 パターンの
ウィジェットを出す。Android では全 API が no-op。

| フェーズ | 出る条件 | サブタイトル | 3行目 | 投稿ボタン | 今日の枠 |
|---|---|---|---|---|---|
| `waiting` | 通知済み・フォロー中の誰も未投稿 | まだ投稿していません | 25:00まで（白） | あり | ＋プレースホルダ |
| `friendsWaiting` | 通知済み・フォロー中の誰かが投稿済み | 友達があなたを待っています | 締切まで h:mm:ss（#DFA506・自動カウントダウン） | あり | ＋プレースホルダ |
| `posted` | 自分がこのサイクルで投稿済み | 投稿が完了しました🎉 | 友達の今日にリアクションしよう！ | なし | 自分の投稿のジャケット |

Figma: `5305:12537` / `5305:12623` / `5305:12685`

---

## 構成

```
ios/LiveActivityShared/MusicMemoryActivityAttributes.swift  … 本体・拡張の共有モデル
ios/FifteensWidget/                                          … Widget Extension ターゲット
  ├ FifteensWidgetBundle.swift
  ├ MusicMemoryLiveActivity.swift                            … SwiftUI（ロック画面 / Dynamic Island）
  ├ Info.plist / FifteensWidget.entitlements / Assets.xcassets
ios/Runner/LiveActivityChannel.swift                         … MethodChannel `com.fifteen.liveactivity`
lib/services/live_activity_service.dart                      … Flutter 側の制御
functions/apns.js                                            … APNs HTTP/2 直送
functions/index.js                                           … push-to-start / 状態遷移 / 期限切れ回収
```

### 状態と画像の分離

- **ContentState**（`phase` / `deadlineEpoch` / `revision`）だけを APNs push で差し替える。
  4KB 制限に余裕があり、サーバはアートワークを一切知らなくてよい。
- **曜日ストリップ**（過去4日＋今日のジャケット）は push で送らず、アプリが
  App Group `group.com.fifteens.sns` に書き出したものをウィジェットが描画時に読む。
  → アプリ起動時と投稿完了時に更新される。

`Date` ではなく **Unix エポック秒**を使っているのは、ActivityKit が push の
`content-state` を既定の `JSONDecoder`（Date は 2001-01-01 起点）でデコードし、
サーバ側の解釈とズレるため。

### 更新の経路

| きっかけ | 誰が | 経路 |
|---|---|---|
| 毎日の通知発火 | Cloud Functions | APNs push-to-start（iOS 17.2+）。未対応端末はアプリ起動時のローカル開始にフォールバック |
| アプリ起動 / フォアグラウンド復帰 | アプリ | `LiveActivityService.refresh()` |
| フォロー中の誰かが投稿 | Cloud Functions | `onPostCreated` → APNs update（`waiting` → `friendsWaiting`） |
| 自分が投稿完了 | アプリ ＋ サーバ（保険） | `LiveActivityService.markPosted()` / `onPostCreated` |
| 締切（25:00）到達 | アプリ ＋ `endStaleLiveActivities`（毎時5分） | 終了 |

---

## 必要な手動セットアップ

### 1. App ID / App Group / プロファイル（Automatic signing で自動）

本プロジェクトは Automatic signing（Team `XLSH9RURK4` / TeamName "Taro Goto"）。
Xcode で Runner・FifteensWidget の両ターゲットに Team を設定すれば、
拡張の App ID・App Group・プロビジョニングプロファイルはすべて自動生成される。
ポータルでの手作業は不要。

確認方法（両方に `group.com.fifteens.sns` が入っていれば完了）:

```bash
for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  security cms -D -i "$f" 2>/dev/null \
    | plutil -p - | grep -q 'com.fifteens.sns' && \
    security cms -D -i "$f" | plutil -p - \
      | grep -E '"Name"|application-identifier|application-groups' -A 1
done
```

> `+ Capability` の一覧に **App Groups が出てこないのは追加済みだから**。
> 検索で出る **Group Activities は SharePlay 用の別物**なので選ばないこと。

### 2. APNs 認証キー（.p8）をポータルで発行

Keys → 新規作成 → **Apple Push Notifications service (APNs)** を有効化。
ダウンロードした `.p8` と Key ID を保管する（**再ダウンロード不可**）。

FCM 用に発行済みのキーがあり `.p8` が手元にあれば、それを再利用してよい
（Firebase Console → プロジェクトの設定 → Cloud Messaging に Key ID が出る）。

### 3. Cloud Functions の環境変数

`functions/.env` に追記（`.gitignore` 済みであることを確認すること）:

```
APNS_TEAM_ID=XXXXXXXXXX
APNS_KEY_ID=YYYYYYYYYY
APNS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
APNS_BUNDLE_ID=com.fifteens.sns
APNS_ENV=production
```


`.p8` を 1 行化して追記するときは **Python を使うこと**。`awk` / `sed` は `\n` を
実際の改行に展開してしまい、`.env` が壊れる。

```bash
python3 -c "
p8='/path/to/AuthKey_XXXXXXXXXX.p8'
k=open(p8).read().strip().replace(chr(13)+chr(10), chr(10)).replace(chr(10), '\\\\n')
print('APNS_TEAM_ID=XXXXXXXXXX')
print('APNS_KEY_ID=XXXXXXXXXX')
print('APNS_PRIVATE_KEY=\\\"'+k+'\\\"')
print('APNS_BUNDLE_ID=com.fifteens.sns')
print('APNS_ENV=sandbox')
" >> functions/.env
```

- `APNS_PRIVATE_KEY` は `.p8` の中身。改行は `\n` エスケープで **1 行**にする
  （実際の改行が混ざると署名時に `ERR_OSSL_UNSUPPORTED` で失敗する）。
- `APNS_ENV` は **端末に入っているビルドの署名に合わせる**。
  - Xcode から実機に入れた開発ビルド → `sandbox`
    （Development プロファイルの `aps-environment` は `development`）
  - TestFlight / App Store 配信 → `production`
  設定を間違えても、`BadDeviceToken` が返った場合は自動でもう一方の環境へ
  投げ直す（`functions/apns.js`）。検証中に両方の端末が混在しても動く。
- 未設定の場合、push 系はすべて静かに no-op になる（アプリのローカル動作のみ）。

デプロイ:

```bash
firebase deploy --only functions:musicMemoryDailyNotification,functions:onPostCreated,functions:endStaleLiveActivities
firebase deploy --only firestore:rules
```

### 4. Xcode ターゲット（既に自動追加済み）

`ios/scripts/*.rb` が `Runner.xcodeproj` に以下を反映済み。再作成が必要になった場合のみ実行する:

```bash
GEM_HOME="$(brew --prefix)/Cellar/cocoapods/<version>/libexec" \
  ruby ios/scripts/add_live_activity_target.rb
GEM_HOME=... ruby ios/scripts/add_live_activity_channel_file.rb
GEM_HOME=... ruby ios/scripts/link_widget_version.rb
```

- ターゲット `FifteensWidget`（`com.fifteens.sns.FifteensWidget` / iOS 16.2+）
- Runner の "Embed App Extensions" フェーズに追加
- 拡張のバージョンは `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` で
  本体と自動一致（App Store の検証要件）

---

## Firestore

| パス | 用途 |
|---|---|
| `users/{uid}.liveActivityPushToStartToken` | push-to-start 用トークン（iOS 17.2+） |
| `live_activities/{uid}` | `phase` / `cycleStart` / `deadline` / `revision` / `pushToken`（Activity ごとの更新トークン） |

`live_activities` は本人のみ読み書き可（管理者は読み取りのみ）。push を送る
Cloud Functions は Admin SDK なのでルールを経由しない。

---

## 動作確認

1. 実機（**シミュレータでは Live Activity の push が使えない**）にインストール
2. 設定 → 15s → 「ライブアクティビティ」がオンであること
3. 管理者パネルの一斉通知、または `music_memory_state/current.notifiedAt` を
   手で現在時刻に更新 → アプリを開く → ロック画面に `waiting` が出る
4. 別アカウント（自分がフォローしている側）で投稿 → `friendsWaiting` に変わる
   - 変わらない場合は `live_activities/{uid}.pushToken` が入っているか確認する。
     push-to-start で開始した直後はアプリを一度開くまでトークンが埋まらない。
5. 自分が投稿 → `posted` に変わり、今日の枠にジャケットが入る

### 認証だけを先に検証する

端末トークン無しで APNs の認証（Team ID / Key ID / .p8 / topic）だけ確かめられる。
ダミーの端末トークンに対して **`400 BadDeviceToken` が返れば認証は正しい**。
`403 InvalidProviderToken` なら Team ID / Key ID / 鍵の不一致、
`403 TopicDisallowed` なら `APNS_BUNDLE_ID` の誤り。

### 既知の制約

- **push-to-start は iOS 17.2 以降**。16.1〜17.1 の端末では、通知タップなどで
  アプリを開いたタイミングで Live Activity が開始される。
- push-to-start で開始された Activity の更新トークンは、アプリが一度起動する
  まで取得できない（iOS の仕様）。それまでは `friendsWaiting` への push が届かない。
- 「締切まで」の表示は SwiftUI の自動カウントダウンのため `5:14:32` 形式
  （Figma の `5:14` とは秒の有無が異なる）。push なしで毎秒更新される利点を優先した。
