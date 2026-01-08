# 歌詞API比較表（2026年1月版）

## 📊 4つの選択肢の詳細比較

| 項目 | LRCLIB API | Musixmatch API | Apple Music Snippet | Apple Music Full Lyrics |
|:---|:---:|:---:|:---:|:---:|
| **料金** | 完全無料 | ❌ 無料プラン終了済み | 無料（Developer Token） | 無料（User Token必要） |
| **APIキー** | 不要 | 必要（有料） | Developer Token | Developer + User Token |
| **日本語カバー率** | 62.5%（実測） | 不明（90%+？） | ~90%（推定） | ほぼ100% |
| **タイムスタンプ** | ✅ あり（LRC形式） | ✅ あり | ❌ なし | ✅ あり（推定） |
| **歌詞の長さ** | 完全な歌詞 | 完全な歌詞 | 1-2行のみ | 完全な歌詞 |
| **レート制限** | 緩い | 2,000/日（旧） | Apple API制限内 | Apple API制限内 |
| **実装難易度** | ⭐ 簡単 | ⭐⭐ 中（有料化） | ⭐ 簡単 | ⭐⭐⭐ 難しい |
| **iOS実機必須** | ❌ 不要 | ❌ 不要 | ❌ 不要 | ✅ 必須 |
| **ユーザー認証** | 不要 | 不要 | 不要 | ✅ 必要 |
| **将来性** | ✅ 安定 | ⚠️ 有料化済み | ✅ 安定 | ✅ 公式API |

---

## 🎯 要件との適合性

### 要件1: できるだけ多くの日本楽曲の歌詞データを取得

#### 単独使用の場合
1. **Apple Music Full Lyrics**: ほぼ100%（最高）
2. **Apple Music Snippet**: ~90%（部分的）
3. **Musixmatch API**: 90%+（有料）
4. **LRCLIB API**: 62.5%（無料）

#### 組み合わせ使用（フォールバック戦略）
- **LRCLIB + Apple Snippet**: ~85% カバー率（完全無料）
- **LRCLIB + Apple Full**: ~95% カバー率（User Token認証必要）

### 要件2: iTunesプレビュー再生に合わせて歌詞をピックアップ

#### タイムスタンプ付き歌詞の提供
1. **LRCLIB API**: ✅ LRC形式で完全対応（62.5%の楽曲）
2. **Apple Music Full Lyrics**: ✅ 対応可能（実装要検証）
3. **Musixmatch API**: ✅ 対応（有料）
4. **Apple Music Snippet**: ❌ タイムスタンプなし

---

## 💰 コスト分析

### 完全無料の組み合わせ
```
LRCLIB API (メイン)
  ↓ 失敗時
Apple Music Snippet (フォールバック)
  ↓ 失敗時
デフォルトテキスト
```
- **初期コスト**: $0
- **運用コスト**: $0/月
- **カバー率**: ~85%
- **タイムスタンプ**: 62.5%の楽曲で利用可能

### Musixmatch有料プラン
```
Musixmatch API (メイン)
  ↓ 失敗時
LRCLIB API (フォールバック)
```
- **初期コスト**: 要問い合わせ
- **運用コスト**: 不明（$数十〜数百/月？）
- **カバー率**: ~95%（推定）
- **タイムスタンプ**: ほぼ100%

### Apple Music User Token認証
```
Apple Music Full Lyrics (メイン)
  ↓ 失敗時
LRCLIB API (フォールバック)
```
- **初期コスト**: $0
- **運用コスト**: $0/月
- **カバー率**: ~95%
- **タイムスタンプ**: ほぼ100%
- **制約**: iOSユーザーのみ、Apple Music登録必要

---

## 🔍 詳細分析

### LRCLIB API

#### メリット
- ✅ 完全無料、永続的
- ✅ APIキー不要
- ✅ タイムスタンプ付き歌詞（LRC形式）
- ✅ レート制限が緩い
- ✅ コミュニティ貢献型で常に改善
- ✅ 実装が非常に簡単

#### デメリット
- ❌ 日本語カバー率62.5%（中程度）
- ❌ データの正確性保証なし
- ❌ 最新曲の追加が遅い可能性

#### テスト結果（16曲中）
- ✅ YOASOBI: 4/4曲成功
- ✅ 米津玄師: 3/3曲成功
- ✅ Official髭男dism: 2/2曲成功
- ✅ Ado: 1曲成功
- ❌ あいみょん: 0/2曲
- ❌ その他: 接続エラー

### Musixmatch API

#### メリット
- ✅ 高いカバー率（推定90%+）
- ✅ タイムスタンプ付き歌詞
- ✅ 高品質なデータ（公式ライセンス）
- ✅ 既にサービス実装済み（`lib/services/musixmatch_service.dart`）

#### デメリット
- ❌ **2025年8月に無料プラン終了**
- ❌ 有料プラン必須（料金不明）
- ❌ 商用利用は別途契約必要
- ❌ APIキー取得・管理が必要

#### 現状
- ⚠️ 無料プランは既に終了（2025年8月25日）
- ⚠️ 有料プランの料金体系は要問い合わせ
- ⚠️ プロジェクトの`.env`にAPIキー未設定

### Apple Music Snippet

#### メリット
- ✅ 完全無料（Developer Tokenのみ）
- ✅ 高いカバー率（~90%）
- ✅ 公式API
- ✅ 実装済み（`with=lyrics`パラメータ）

#### デメリット
- ❌ 歌詞の一部（1-2行）のみ
- ❌ タイムスタンプなし
- ❌ 歌詞カード表示には不十分

#### テスト結果
```json
{
  "snippets": [{
    "kind": "lyric",
    "text": "二人今、夜に駆け出していく"  // 1行のみ
  }]
}
```

### Apple Music Full Lyrics (User Token)

#### メリット
- ✅ ほぼ100%のカバー率
- ✅ 完全な歌詞
- ✅ タイムスタンプ付き（推定）
- ✅ 公式API
- ✅ 完全無料

#### デメリット
- ❌ User Token認証が必要
- ❌ iOS実機でのテスト必須
- ❌ ユーザーがApple Music登録必要
- ❌ 実装難易度が高い
- ❌ iOSのみ（Androidは未対応）

#### 実装状況
- ✅ MusicKitService実装済み（`lib/services/musickit_service.dart`）
- ✅ iOS Swift実装済み（`ios/Runner/AppDelegate.swift`）
- ⚠️ 実機テスト未実施

---

## 📈 推奨戦略：3段階フォールバック

### Phase 1（即座に実装可能）
```dart
1. LRCLIB API（タイムスタンプ付き）
   ↓ 404の場合
2. Apple Music Snippet（部分的な歌詞）
   ↓ 失敗した場合
3. デフォルトテキスト
```

**期待カバー率**: ~85%
**タイムスタンプ付き**: 62.5%
**実装時間**: 3-4時間
**コスト**: $0

### Phase 2（将来的な拡張）
iOS実機でUser Token認証をテストし、成功したら追加：

```dart
1. LRCLIB API（タイムスタンプ付き）
   ↓ 404の場合
2. Apple Music Full Lyrics（User Token）
   ↓ 失敗した場合
3. Apple Music Snippet（部分的）
   ↓ 失敗した場合
4. デフォルトテキスト
```

**期待カバー率**: ~95%
**タイムスタンプ付き**: ~95%
**追加実装時間**: 2-3時間
**コスト**: $0

---

## ⚠️ Musixmatch APIについて

### 現状
- 無料プランは2025年8月25日に終了
- 現在（2026年1月）は有料プランのみ

### 採用の判断基準
以下の条件が満たされる場合のみ検討：

1. ✅ 有料プランの料金が許容範囲内
2. ✅ 商用利用の契約が可能
3. ✅ 月額費用の予算が確保できる
4. ✅ カバー率90%+が必須要件

### 代替案
Musixmatchの代わりに：
- **即時**: LRCLIB API（無料、62.5%カバー）
- **将来**: Apple Music User Token（無料、95%+カバー）

---

## 🎯 最終推奨

### 最小コストで最大効果
1. **今すぐ実装**: LRCLIB + Apple Snippet（3-4時間）
2. **iOS実機入手後**: User Token認証を追加（+2-3時間）
3. **Musixmatch**: 予算があれば検討（料金次第）

### タイムライン
```
Week 1: LRCLIB + Snippet実装
  → カバー率85%、タイムスタンプ62.5%達成

Week 2-3: iOS実機でUser Token認証テスト
  → 成功すればカバー率95%に向上

Future: 必要に応じてMusixmatch検討
  → 有料プラン料金を確認後
```

---

## 📚 参考リンク

- [LRCLIB API](https://lrclib.net)
- [Musixmatch API Pricing](https://rapidapi.com/Paxsenix0/api/musixmatch-lyrics-songs/pricing)
- [Apple Music API Documentation](https://developer.apple.com/documentation/applemusicapi/)
- [MusicKit Documentation](https://developer.apple.com/documentation/musickit/)
