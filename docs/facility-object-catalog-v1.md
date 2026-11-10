# 施設共通：写り込み注意オブジェクト・カタログ v1

| 項目 | 内容 |
| --- | --- |
| 更新日 | 2026-11-09 |
| 状態 | **カタログ定義。検出モデル実装・学習・生成AIによる画像量産は未実施。** |
| 目的 | 頻繁に写り、個人情報・業務情報・リテラシー上の問題になりやすい物を、共通選択リストと学習データ生成の入力として固定する |
| 関連設計 | [施設指定物の検知 A+B 提案](facility-object-detection-ab-proposal.md) |
| 言語 | UI表示は日本語／英語。`catalogId` は機械可読の安定キー |

この文書は実装AI・学習パイプラインAIがそのまま読めるように書く。推測と確定事実を混ぜない。

---

## 1. 使い方（エージェント向け）

1. 検出・学習・生成の対象クラスは、原則 **§3 の `catalogId` だけ** を使う。自由文ラベルで増やさない。
2. 生成AIで学習画像を作るときは **§5 のマルチビュー1枚方式** に従う。
3. 施設ごとの一点物は本カタログに入れず、A+B提案の **案B（埋め込み照合）** へ回す。
4. 利用者の投稿写真はクラウドAIへ送らない。生成・学習に使うのは **架空／許諾済みの合成データのみ**。
5. 検出結果は「禁止」の断定に使わない。確認候補の提示に限る。

---

## 2. 優先度と採用方針

| priority | 意味 | 学習・検出への入れ方 |
| --- | --- | --- |
| `P0` | 頻出かつ被害・炎上・漏洩事例が多い。最初の共通モデルに入れる | 必須クラス |
| `P1` | 頻出だが見た目のばらつきが大きい／既存機能と役割が近い | 第2弾。またはOCR・既存機器検出と併用 |
| `P2` | 重要だが検出より案内・手動確認向き、または一点物寄り | カタログ選択は可能でも学習は後回し／案B |

既存実装との関係：

- `laptop` / `cell phone` / `tv` は現行 EfficientDet 経路を維持する。本カタログの `phone_screen` / `laptop_screen` は「画面が読める状態」の注意を強めるための別クラスとして定義する（将来統合可）。
- 文字が読める対象は OCR／登録ワードと根拠を併記してよい。物体クラスの代替にはしない。

---

## 3. カタログ本体（機械可読）

各エントリのフィールド：

| フィールド | 必須 | 説明 |
| --- | --- | --- |
| `catalogId` | yes | 安定ID（snake_case） |
| `labelJa` / `labelEn` | yes | UI表示名 |
| `priority` | yes | `P0` / `P1` / `P2` |
| `riskTags` | yes | リスク種別 |
| `whyFrequent` | yes | 頻繁に写る理由 |
| `whySensitive` | yes | 写してはいけない／写したくない理由 |
| `detectHint` | yes | 検出・学習時の見た目のヒント |
| `views` | yes | マルチビュー生成で必須にする角度キー |
| `synonymJa` | no | 検索・プロンプト用の別名 |
| `excludeFromV1Train` | no | `true` なら v1 学習セットから除外 |
| `notes` | no | 実装上の注意 |

`riskTags` の許容値：`pii`（個人情報） / `workplace`（業務・顧客情報） / `identity`（身分・所属） / `location`（居所・行動推測） / `credential`（鍵・認証） / `literacy`（マナー・施設ルール・年齢制限など） / `third_party`（第三者）

### 3.1 P0（最初に学習・検出する）

```yaml
- catalogId: cigarette
  labelJa: たばこ・喫煙関連
  labelEn: Tobacco / smoking-related
  priority: P0
  riskTags: [literacy]
  whyFrequent: 手元・テーブル・店頭に写りやすい
  whySensitive: 施設の撮影・喫煙ルール、未成年への配慮、マナー問題になりやすい
  detectHint: 紙巻きたばこ、箱、電子たばこ端末を含む。煙単体は対象外
  views: [front, side, oblique, back, partial]
  synonymJa: [タバコ, 煙草, タバコ箱, 電子タバコ]

- catalogId: whiteboard
  labelJa: ホワイトボード
  labelEn: Whiteboard
  priority: P0
  riskTags: [pii, workplace]
  whyFrequent: 会議室・教室・店舗バックヤードの背景に常にある
  whySensitive: 氏名、顧客名、数字、予定、Wi-Fi等が読める事例が多い（SNS転載事故の典型）
  detectHint: 壁掛け／スタンドの白い板。文字の有無は問わない（枠検出が主）
  views: [front, oblique, side, far, partial]
  synonymJa: [白板, ミーティングボード]

- catalogId: student_id
  labelJa: 学生証
  labelEn: Student ID card
  priority: P0
  riskTags: [pii, identity]
  whyFrequent: 机・鞄・手持ちで写る
  whySensitive: 氏名、学校、番号、顔写真が載ることが多い
  detectHint: カード型。大学・高校など様式差あり。表面の文字は学習ラベルに含めず物体として扱う
  views: [front, oblique, side, partial, in_hand]
  synonymJa: [学生カード, 生徒手帳]

- catalogId: employee_id
  labelJa: 社員証・入館証
  labelEn: Employee / access ID badge
  priority: P0
  riskTags: [pii, identity, credential]
  whyFrequent: 首下げ・クリップ・机上で写る。オフィス写真の定番写り込み
  whySensitive: 氏名、社員番号、顔、バーコード／QRから複製リスクがある
  detectHint: カード＋リール／ケースを含む。ICカード単体も含む
  views: [front, oblique, side, hanging, partial]
  synonymJa: [社員証, 入館証, IDカード, セキュリティカード]

- catalogId: name_badge
  labelJa: 名札
  labelEn: Name badge / name tag
  priority: P0
  riskTags: [pii, identity]
  whyFrequent: 店舗・イベント・バイト制服で常時装着
  whySensitive: 氏名や店舗が分かり、ストーキング・身バレの手がかりになる
  detectHint: 胸元・制服に付く小さめの札。社員証より簡易なものを含む
  views: [front, oblique, on_clothing, partial]
  synonymJa: [ネームプレート, ネームタグ]

- catalogId: sticky_note
  labelJa: 付箋
  labelEn: Sticky note
  priority: P0
  riskTags: [pii, workplace, credential]
  whyFrequent: モニタ枠・机・書類に貼られる
  whySensitive: パスワード、電話番号、氏名、ToDoが書かれやすい
  detectHint: 小さな紙片。色は黄・桃・青など多様。文字内容はクラスに含めない
  views: [front, oblique, on_monitor, clustered, partial]
  synonymJa: [ポストイット, ふせん, メモ紙]

- catalogId: shipping_label
  labelJa: 宅配伝票・宛名ラベル
  labelEn: Shipping / address label
  priority: P0
  riskTags: [pii, location]
  whyFrequent: 段ボール・袋・玄関先の荷物に必ず付く
  whySensitive: 住所、氏名、電話が読める
  detectHint: 伝票面・宛名面が主。段ボール全体よりラベル領域を優先
  views: [front, oblique, on_box, partial, crumpled]
  synonymJa: [伝票, 送り状, 宛名]

- catalogId: mail_envelope
  labelJa: 郵便物・封筒
  labelEn: Mail / envelope
  priority: P0
  riskTags: [pii, location]
  whyFrequent: 机・床・玄関に放置され背景に入りやすい
  whySensitive: 宛名から住所と氏名が分かる
  detectHint: 封筒、はがき、窓あき封筒。切手の有無は問わない
  views: [front, oblique, stacked, partial]
  synonymJa: [封筒, 手紙, はがき]

- catalogId: phone_screen
  labelJa: スマホ画面（表示中）
  labelEn: Phone with readable screen
  priority: P0
  riskTags: [pii, workplace]
  whyFrequent: 自撮り・テーブル写真の端に入りやすい
  whySensitive: 通知、チャット、メール、2FA、個人名が読める
  detectHint: 点灯したスマートフォン画面。消灯端末は優先度を下げる
  views: [front, oblique, side, in_hand, partial]
  synonymJa: [スマホ画面, スマートフォン]
  notes: 既存 cell phone 検出と重複しうる。v1では「点灯画面」を強調した別評価セットを持つ

- catalogId: laptop_screen
  labelJa: PC・ノートPC画面（表示中）
  labelEn: Laptop / monitor with readable screen
  priority: P0
  riskTags: [pii, workplace]
  whyFrequent: カフェ・職場・自宅デスク写真の背景定番
  whySensitive: 顧客リスト、メール、社内システムが写る事例が多い
  detectHint: 点灯したノートPC／外付けモニタ。キーボードだけの場合は弱優先
  views: [front, oblique, side, far, partial]
  synonymJa: [パソコン画面, ノートPC, ディスプレイ]
  notes: 既存 laptop 検出と併用。画面内容のOCRは別経路

- catalogId: qr_or_barcode
  labelJa: QR・バーコード
  labelEn: QR code / barcode
  priority: P0
  riskTags: [pii, credential, identity]
  whyFrequent: 社員証、伝票、チケット、掲示物に付く
  whySensitive: 読み取りでIDやURL、個人データが出ることがある
  detectHint: 二次元／一次元コード領域。小さめでも枠を付ける
  views: [front, oblique, partial, angled]
  synonymJa: [QRコード, バーコード]
```

### 3.2 P1（第2弾）

```yaml
- catalogId: paper_document
  labelJa: 書類・プリント
  labelEn: Paper document
  priority: P1
  riskTags: [pii, workplace]
  whyFrequent: 机上・手持ち・会議写真に常にある
  whySensitive: 名簿、契約、カルテ、成績など内容次第で高リスク
  detectHint: A4等の紙。白紙は低優先。束ねた書類も含む
  views: [front, oblique, stacked, in_hand, partial]
  synonymJa: [書類, 資料, プリントアウト]

- catalogId: calendar_schedule
  labelJa: カレンダー・予定表
  labelEn: Calendar / schedule board
  priority: P1
  riskTags: [pii, workplace, location]
  whyFrequent: 壁・机に常設
  whySensitive: 氏名入り予定、行動パターンが分かる
  detectHint: 壁掛けカレンダー、当番表、シフト表
  views: [front, oblique, far, partial]
  synonymJa: [予定表, シフト表, 当番表]

- catalogId: school_crest
  labelJa: 校章・エンブレム
  labelEn: School crest / emblem
  priority: P1
  riskTags: [identity, location]
  whyFrequent: 制服・鞄・旗・掲示に付く
  whySensitive: 学校特定や待ち伏せ被害の手がかりになる事例がある
  detectHint: 小さな紋章・ワッペン。ロゴ単体
  views: [front, oblique, on_clothing, partial]
  synonymJa: [校章, エンブレム, 学校バッジ]

- catalogId: uniform_logo
  labelJa: 制服・ロゴ入りウェア
  labelEn: Uniform / logo apparel
  priority: P1
  riskTags: [identity, location]
  whyFrequent: 人中心の写真で前面に出る
  whySensitive: 勤務先・学校が特定されやすい
  detectHint: 制服全体よりロゴ／名札エリアを優先してもよい
  views: [front, oblique, partial]
  synonymJa: [制服, 社名入りTシャツ]
  excludeFromV1Train: true
  notes: 人物検出・服飾ばらつきが大きい。v1学習から除外し、案内または後続モデルへ

- catalogId: door_keypad
  labelJa: ドア暗証パネル
  labelEn: Door keypad / access panel
  priority: P1
  riskTags: [credential, workplace]
  whyFrequent: 入口・会議室ドア横の「オフィス紹介」写真に写る
  whySensitive: 配置や使用痕跡から侵入の手がかりになる
  detectHint: テンキー付きパネル。スマホ型インターホンは別でも可
  views: [front, oblique, side, partial]
  synonymJa: [暗証番号, ドアロック, テンキー]

- catalogId: keys
  labelJa: 鍵・キーホルダー
  labelEn: Keys / keychain
  priority: P1
  riskTags: [credential, location]
  whyFrequent: 机・手・玄関写真に写る
  whySensitive: 鍵の形状・メーカーから複製や場所推測の材料になる場合がある
  detectHint: 鍵束。カードキーは employee_id 側を優先
  views: [front, oblique, in_hand, partial]
  synonymJa: [鍵, キー]

- catalogId: license_plate
  labelJa: 自動車ナンバー
  labelEn: Vehicle license plate
  priority: P1
  riskTags: [pii, location]
  whyFrequent: 駐車・ドライブ写真の端に入る
  whySensitive: 個人・車両の特定につながる
  detectHint: ナンバープレート領域
  views: [front, oblique, partial, distant]
  synonymJa: [ナンバープレート, 車のナンバー]

- catalogId: ticket_pass
  labelJa: 切符・チケット・搭乗券
  labelEn: Ticket / boarding pass
  priority: P1
  riskTags: [pii, location, identity]
  whyFrequent: 旅行・イベント写真で手持ちに写る
  whySensitive: 氏名、便名、座席、QRが載る
  detectHint: 紙・スマホ表示のチケット。QRがあれば qr_or_barcode とも併記可
  views: [front, oblique, in_hand, partial]
  synonymJa: [切符, 航空券, 入場券]
```

### 3.3 P2（後回し／別手段）

```yaml
- catalogId: desk_scene
  labelJa: 職場デスク一式
  labelEn: Workplace desk scene
  priority: P2
  riskTags: [workplace, pii]
  whyFrequent: 「仕事風景」投稿の主題になりやすい
  whySensitive: 書類・画面・付箋・社員証が同時に写る複合リスク
  detectHint: 単一物体ではなくシーン。共通検出より複合ルール向き
  views: [front, oblique, overhead]
  excludeFromV1Train: true
  notes: 施設独自の机・備品差が大きい。案Bまたは複数P0の同時検出でカバー

- catalogId: nameplate_door
  labelJa: 表札・部屋番号
  labelEn: Door nameplate / room number
  priority: P2
  riskTags: [pii, location]
  whyFrequent: 玄関・マンション写真
  whySensitive: 住所特定
  detectHint: 表札プレート、部屋番号表示
  views: [front, oblique, partial]
  synonymJa: [表札, 部屋番号]

- catalogId: medicine_rx
  labelJa: 薬袋・処方箋まわり
  labelEn: Medicine bag / prescription materials
  priority: P2
  riskTags: [pii]
  whyFrequent: 自宅テーブルに出やすい
  whySensitive: 健康情報・氏名
  detectHint: 薬袋、処方箋控え
  views: [front, oblique, partial]
  excludeFromV1Train: true
  notes: 医療情報は扱いに慎重。施設カタログより個人設定ワード／手動確認を優先検討

- catalogId: cash_register
  labelJa: レジ・現金まわり
  labelEn: Cash register / cash handling area
  priority: P2
  riskTags: [workplace, literacy]
  whyFrequent: 店舗スタッフ投稿
  whySensitive: 防犯・就業規則・施設ルール
  detectHint: レジ本体、オープンな現金
  views: [front, oblique, partial]
  excludeFromV1Train: true

- catalogId: alcohol_display
  labelJa: 酒類の陳列・提供風景
  labelEn: Alcohol display / service scene
  priority: P2
  riskTags: [literacy]
  whyFrequent: 飲食店・売場写真
  whySensitive: 施設ルール・年齢制限の文脈
  detectHint: ボトル陳列、ジョッキ等。人物の年齢推定はしない
  views: [front, oblique, far]
  excludeFromV1Train: true
```

---

## 4. v1 学習・検出の採用セット（要約）

実装や生成パイプラインが迷わないための固定リスト。

### 4.1 Train-v1（学習必須）

`cigarette`, `whiteboard`, `student_id`, `employee_id`, `name_badge`, `sticky_note`, `shipping_label`, `mail_envelope`, `phone_screen`, `laptop_screen`, `qr_or_barcode`

### 4.2 Train-v1.1（続く）

`paper_document`, `calendar_schedule`, `school_crest`, `door_keypad`, `keys`, `license_plate`, `ticket_pass`

### 4.3 学習除外（v1）

`uniform_logo`, `desk_scene`, `medicine_rx`, `cash_register`, `alcohol_display`  
→ 案内・手動・案B・複合検出で扱う。

---

## 5. 生成AIによる学習データ作成（将来実行用）

### 5.1 アイデア（確定方針）

生成AIを、検出モデル育成用の **学習データ工場** として使う。

特に検証したい方式：

> **1回の画像生成で、同一オブジェクトの複数角度を1枚に並べ、それぞれに正解枠（bounding box）を付ける。**

例：スマートフォンなら、正面・横・斜め・背面を同一キャンバスに配置し、各領域に `phone_screen`（または対象クラス）の枠を付ける。

ねらい：

- 実物を何度も撮影する負担を減らす
- 背景・明るさ・大きさ・隠れ方をプロンプトで制御する
- 1枚あたりの学習シグナル（角度多様性）を増やす

検証目標：合成データで学習 → **実写真**での検出が改善するか測る。合成だけで完了としない。

### 5.2 1枚マルチビュー画像の仕様

| 項目 | 初期仕様 |
| --- | --- |
| キャンバス | 横長または正方形（例：1024×1024 または 1536×1024）。学習パイプラインで固定 |
| 配置 | 2×2 または 1×4 のパネル。パネル境界は明確（薄い枠線可） |
| 1枚あたりのインスタンス数 | 同一 `catalogId` を 3〜6 個 |
| 必須ビュー | 各クラスの `views` から可能な限りカバー |
| ラベル単位 | パネルごと／物体ごとに1つの軸平行矩形（xyxy または YOLO正規化） |
| クラス名 | 必ず §3 の `catalogId` |
| 禁止 | 実在人物の顔の高精細生成を学習必須条件にしない。カード類は架空の氏名・番号にする |

アノテーションJSON例（学習ツールが読みやすい最小形）：

```json
{
  "image_id": "synth_phone_screen_000123",
  "catalogId": "phone_screen",
  "source": "genai_multiview_v1",
  "width": 1024,
  "height": 1024,
  "objects": [
    {
      "view": "front",
      "bbox_xyxy": [40, 40, 480, 480],
      "occlusion": "none",
      "lighting": "indoor_bright"
    },
    {
      "view": "oblique",
      "bbox_xyxy": [544, 40, 984, 480],
      "occlusion": "partial_hand",
      "lighting": "indoor_bright"
    }
  ]
}
```

### 5.3 生成プロンプトの共通スロット

生成AIへの指示は、次のスロットを埋めて作る（クラスごとに内容だけ差し替える）。

```text
[TASK]
Create one training image for object detection.
Put MULTIPLE views of the SAME object type in a single image, arranged in clear panels.
Do not blend panels into one object.

[OBJECT]
catalogId: {catalogId}
visual definition: {detectHint}
required views: {views}

[VARIATION]
background: {background}
lighting: {lighting}
scale: mix of large / medium / small instances
occlusion: {occlusion}
blur/noise: mild smartphone-photo realism is OK

[PRIVACY]
Use only fictional names, numbers, addresses, QR payloads.
No real person identity. No readable real PII.

[OUTPUT EXPECTATION]
The image must make it easy to draw a tight box around each instance.
Avoid tiny unreadable instances below ~16px on the short side of the object.
```

`background` 初期候補：`desk`, `cafe_table`, `office_wall`, `classroom`, `store_counter`, `doorway`, `neutral_seamless`  
`lighting` 初期候補：`bright`, `dim`, `backlit`, `warm_indoor`, `cool_fluorescent`  
`occlusion` 初期候補：`none`, `hand`, `other_object`, `edge_crop`, `reflection`

### 5.4 実行しやすい作業チェックリスト

実装・検証担当（人／AI）は、この順で進める。

1. **クラス固定**  
   Train-v1 の11クラス以外を混ぜない。
2. **マルチビュー生成**  
   クラスごとに N 枚（初期案：各クラス 50〜200 枚の合成画像。数は計測で調整）。
3. **枠付け**  
   生成と同時に枠を出す場合は必ず人がサンプル監査する。自動枠だけを正解扱いにしない。
4. **実写真セット**  
   架空／許諾済みの実写を別途用意（合成と混ぜて最終評価しない hold-out）。
5. **学習**  
   Edge向け物体検出（A+B提案の案A経路）へ投入。
6. **比較**  
   実写のみ学習 vs 合成+実写。指標は再現率・誤検出・小物体・斜め・暗所。
7. **アプリ接続**  
   改善が確認できてから TFLite をカタログモデルとして配信設計へ進む。

### 5.5 リスクと検証上の注意

| リスク | 対策 |
| --- | --- |
| 合成に過適合し実写で弱い | 必ず実写 hold-out で判定 |
| パネル境界を物体と誤学習 | 実写微調整セットを混ぜる／単一物体画像も一定割合入れる |
| 生成画像に実在風の個人情報が入る | 架空データ制約をプロンプトと監査の両方で固定 |
| 1枚多物体で枠が甘い | 枠の IoU 監査、小さすぎる箱を除外 |
| たばこ・身分証などの生成ポリシー制限 | モデル／サービスの利用規約を確認。不可なら実写・3D・既存データセットへ切替 |

---

## 6. UI／施設選択への載せ方（将来）

管理画面の「よくある物」チェックは、まず **§4.1 Train-v1** を出す。  
表示順の初期案：

1. ホワイトボード  
2. 名札  
3. 社員証・入館証  
4. 学生証  
5. 付箋  
6. 宅配伝票・宛名  
7. 郵便物  
8. スマホ画面  
9. PC画面  
10. QR・バーコード  
11. たばこ・喫煙関連  

施設独自物（この会場だけの展示物など）は選択リストに入れず、写真登録（案B）へ誘導する。

---

## 7. 変更ルール

- `catalogId` の改名は破壊的変更。別名が必要なら `synonymJa` か新ID追加。
- クラス追加は本ドキュメントの版を上げ、Train-v1 への即時追加はしない（計測後）。
- 本カタログは検出保証リストではない。確認候補の対象候補である。

---

## 8. 参考にした問題類型（調査メモ）

断定的な統計ではなく、注意喚起・報道・リテラシー教材で繰り返し挙げられる類型：

- ホワイトボード／PC画面／書類の業務情報写り込み（職場SNS・BeReal転載など）
- 名札・社員証・学生証の身分情報
- 付箋のパスワード・連絡先
- 宅配伝票・郵便物の住所氏名
- 校章・制服からの学校特定
- QR／バッジ写真からの複製リスク
- たばこ等の施設・マナー上の写し込み

詳細な検知アーキテクチャは [facility-object-detection-ab-proposal.md](facility-object-detection-ab-proposal.md) を正本とする。
