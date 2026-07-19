# サブスクリプション管理システムの実装

動画配信サービスにおける定期購読の開始・更新・解約を管理する API を Ruby on Rails で実装してください

実務に耐えうる設計・実装（拡張性・分析可能性・冪等性・スケーラビリティ等）を意識し、README に設計の概要や工夫したポイントを記載してください（日本語もしくは英語）

不明点は適切に定義して構いません

- ユーザは Apple のアプリ内課金でサブスクリプションを購入する
- 決済完了後、アプリ側から Rails API に決済情報を送信し、サブスクリプションを仮開始する
- その後、Apple からの Webhook 通知（開始・更新・解約）を受信して、サブスクリプションの状態を更新する。署名検証は省略して良い
- 解約時でも現在の有効期限までは利用可能とする

評価の観点：要件定義力・設計力・拡張性・説明力

## クライアント -> サーバ (決済完了直後)

```json
{
  "user_id": "string",
  "transaction_id": "string",
  "product_id": "string"
}
```

- user_id: 本来は Cookie 等から取得する値だが、今回わかりやすくするためパラメータとして渡す形にする。検証不要
- transaction_id: サブスクリプションを一意に識別する ID。同じサブスクリプションなら自動更新されても同じ値
- product_id: サブスクリプションプランの ID。例：com.samansa.subscription.monthly

この時点では仮開始。Apple Webhook 到着で本開始。仮開始中は視聴不可。

## Apple -> サーバ （Webhook）

```json
{
  "notification_uuid": "string",
  "type": "PURCHASE" "RENEW" "CANCEL",
  "transaction_id": "string",
  "product_id": "string",
  "amount": "3.9",
  "currency": "USD",
  "purchase_date": "2025-10-01T12:00:00Z",
  "expires_date": "2025-11-01T12:00:00Z",
}
```

- notification_uuid: 通知ごとに一意の値
- type: 通知の種類。PURCHASE は新規購入、RENEW は自動更新、CANCEL は解約
- transaction_id: サブスクリプションを一意に識別する ID。同じサブスクリプションなら自動更新されても同じ値
- product_id: サブスクリプションプランの ID。例：com.samansa.subscription.monthly
- amount / currency: 課金金額と通貨
- purchase_date: 現在のサブスクリプション期間の開始日時
- expires_date: 次回更新またはサブスクリプション終了日時

---

# 設計ドキュメント（実装者による追記）

## セットアップ

```bash
bundle install
bin/rails db:prepare
bin/rails test    # テスト実行
bin/rails server  # 起動
```

Ruby 4.0 / Rails 8.1 / SQLite（開発・テスト用。本番は PostgreSQL 等を想定）

## API 一覧

| メソッド | パス | 用途 |
| --- | --- | --- |
| POST | `/api/v1/subscriptions` | クライアントからの決済完了報告（仮開始） |
| POST | `/webhooks/apple` | Apple からの通知（PURCHASE / RENEW / CANCEL） |
| GET | `/api/v1/users/:user_id/subscriptions` | ユーザのサブスクリプション状態と視聴可否の照会 |

照会 API は課題要件には無いが、アプリ側が「視聴可否（`entitled`）」を判定するために追加した。

## データモデル

```
subscriptions                     subscription_events
--------------------------        --------------------------------
user_id          (null可)   1 --- * subscription_id
transaction_id   (unique)         source        client / apple_webhook
product_id                        event_type    purchase_reported / purchase / renew / cancel
status           provisional      notification_uuid (unique, webhookのみ)
                 / active         amount, currency
                 / canceled       purchase_date, expires_date
current_period_started_at         payload (受信した生データ)
expires_at
canceled_at
```

- **subscriptions**: 現在の状態を表すスナップショット。`transaction_id` がサブスクリプションの自然キー。
- **subscription_events**: 受信したすべてのイベントの追記型ログ（イベントソーシング的な補助テーブル）。
  - **分析可能性**: 金額・通貨・期間をイベント単位で保持するため、売上集計や解約率などの分析は本テーブルを起点に行える。生ペイロードも `payload` に保存しており、後から項目を追加抽出できる。
  - **監査・復旧**: 状態テーブルにバグがあってもイベントから再構築できる。

## 状態遷移

```
                クライアント報告
   （なし）────────────────────▶ provisional（仮開始・視聴不可）
      │                              │
      │ Webhook PURCHASE 先着        │ Webhook PURCHASE（本開始）
      ▼                              ▼
  provisional（user未紐付け）───▶ active（視聴可）◀─── RENEW（期限延長・解約取消も含む）
                                     │
                                     │ CANCEL
                                     ▼
                                 canceled（expires_at までは視聴可）
```

視聴可否は `Subscription#entitled?` に集約:
`(active または canceled) かつ expires_at が未来` 。
「解約時でも現在の有効期限までは利用可能」の要件はここで満たす。期限切れは状態を書き換えるバッチではなく時刻比較で判定するため、更新漏れによる不整合が起きない。

## 冪等性

| 経路 | 仕組み |
| --- | --- |
| クライアント報告 | `subscriptions.transaction_id` のユニーク制約。同じ報告の再送は既存レコードを 200 で返す |
| Apple Webhook | `subscription_events.notification_uuid` のユニーク制約。処理済み通知は何もせず 200（`already_processed`）を返す |

いずれも DB のユニーク制約を最終防衛線とし、アプリ層のチェックはその手前の早期リターンという位置付け。同時リクエストで `RecordNotUnique` が発生した場合は勝った方のレコードに対して一度だけ再実行する（`app/services/` 参照）。Apple は 200 を返すまで再送してくる前提なので、重複はエラーではなく正常応答にしている。

## 順序性（Out-of-order / 先着逆転への対応）

Webhook とクライアント報告の到着順は保証されないため、以下を考慮した。

- **PURCHASE がクライアント報告より先に届く**: ユーザ未紐付け（`user_id: NULL`）のままサブスクリプションを作成して本開始し、後から届いたクライアント報告で `user_id` を紐付ける（状態は上書きしない）。
- **古い PURCHASE / RENEW が遅れて届く**: `expires_date` が既知の期限より進む場合のみ適用し、期限の巻き戻りや解約済みサブスクリプションの復活を防ぐ。
- **CANCEL**: `expires_at` は変更せず状態のみ `canceled` にする（期限まで視聴可）。
- **CANCEL 後の RENEW**（解約取消→自動更新の継続）: `active` に戻し `canceled_at` をクリアする。

更新はすべて行ロック（`SELECT ... FOR UPDATE`）+ トランザクション内で行い、同一サブスクリプションへの並行更新でも整合性を保つ。

## 拡張性

- **通知タイプの追加**（REFUND, GRACE_PERIOD 等）: `ApplyAppleNotification` の `TYPE_TO_EVENT` にマッピングと `apply_*` メソッドを追加するだけでよい。未知のタイプは 422 で拒否し、黙って握りつぶさない。
- **他プラットフォーム対応**（Google Play 等）: イベントに `source` を持たせてあるため、`webhooks/google` エンドポイント + 対応サービスクラスの追加で対応できる。プラットフォーム固有の生ペイロードは `payload` カラムに吸収される。
- **プランのマスタ化**: 現状 `product_id` は文字列のまま保持。プラン別の価格・期間などが必要になれば `plans` テーブルを追加して参照に切り替える。
- **API バージョニング**: `/api/v1` を切ってあるため、後方互換を壊す変更は v2 として追加できる。

## スケーラビリティ

- 書き込みはユニーク制約ベースの冪等化なので、API サーバは水平スケール可能（インスタンス間の協調不要）。
- 行ロックの範囲は単一サブスクリプション行のみで、他ユーザの処理をブロックしない。
- Webhook 1 件の処理は 5 クエリ（冪等チェック 1・行ロック取得 1・書き込み 3）に抑えている。一意性はモデルの uniqueness バリデーション（毎回 SELECT を発行し、かつ競合に弱い）ではなく DB 制約 + `RecordNotUnique` ハンドリングで担保し、検証クエリを省いた。
- インデックスは全クエリパスを EXPLAIN で確認のうえ最小構成にしている（単独カラムの索引は複合インデックスの先頭カラムで代用し、書き込み時のインデックス更新コストを抑える）。
- 照会系（`entitled?`）は `(user_id, status)` / `expires_at` にインデックス済み。読み取り負荷が上がればリードレプリカやキャッシュ（期限までの TTL 付き）を足せる。
- Webhook 処理をさらに重くする場合（外部 API 照会等）は、受信時に `subscription_events` へ記録だけして 200 を返し、適用を非同期ジョブ化する構成に発展させられる（現状は同期でも十分軽い）。

## 主要ファイル

- `app/services/subscriptions/report_purchase.rb` — クライアント報告（仮開始・紐付け）
- `app/services/subscriptions/apply_apple_notification.rb` — Webhook 適用（状態遷移の本体）
- `app/models/subscription.rb` — 状態と `entitled?`（視聴可否）
- `test/` — モデル・API・Webhook の統合テスト（冪等性・順序逆転・解約後の視聴可否を含む 25 件）
