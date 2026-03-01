# RTX830 SNMP設定 学習ノート

**作成**: 2026-02-28
**対象機器**: Yamaha RTX830 Rev.15.02.33
**目的**: SNMP Exporter経由でのPrometheus監視統合

---

## 機器情報

| 項目 | 値 |
|------|-----|
| モデル | Yamaha RTX830 |
| ファームウェア | Rev.15.02.33 (2025-07-15) |
| メモリ | 256MB |
| LAN | 2ポート |
| LAN1 IP | 10.0.0.1/24（自宅LAN側） |
| WAN | IIJ IPoE (lan2) + PPPoE (pp 1) |

---

## SNMPの基本概念

```
【監視サーバー（10.0.0.220）】          【RTX830（10.0.0.1）】
         │                                      │
         │  「sysDescrを教えて」（ポーリング）  │
         │ ─────────────────────────────────> │
         │                                      │
         │  「Yamaha RTX830 Rev.15...」（応答） │
         │ <───────────────────────────────── │
```

- SNMP は**監視サーバーが機器に問い合わせる**プロトコル（Pull型）
- 機器側は**コミュニティ文字列**（合言葉）で受け付け相手を管理する
- コミュニティには `ro`（読み取り専用）と `rw`（読み書き）がある

---

## コマンド解説

### `snmp community monlab ro`

```
snmp        → SNMPの設定コマンド
community   → コミュニティ文字列（パスワードに近いもの）を定義する
monlab      → コミュニティ名（任意の名前）
ro          → read-only（読み取り専用）
               rw にすると設定変更もできてしまうため、監視用途は ro 一択
```

**意味**: 「`monlab` という合言葉を知っている相手からの
SNMP読み取り問い合わせを受け付ける」

---

### `snmp host 10.0.0.220 community monlab version 2`

```
snmp        → SNMPの設定コマンド
host        → 接続先ホストを指定
10.0.0.220  → 監視サーバーのIP
community   → 使用するコミュニティ文字列
monlab      → 上で定義した名前
version 2   → SNMPバージョン2c を使う
```

**⚠️ 注意**: Yamaha RTX系では `snmp host` は
**トラップ（異常通知）の送信先**設定である可能性が高い。
今回の用途（監視サーバーがルーターをポーリング）には不要かもしれない。
`snmp community monlab ro` だけで動作確認してから判断すること。

---

### `show snmp`

```
show   → 現在の設定を表示（変更なし・読み取り専用）
snmp   → SNMP関連の設定に絞る
```

設定投入の前後に実行して、変化を確認する。

---

### `snmpwalk -v2c -c monlab 10.0.0.1 sysDescr.0`

**実行場所**: RTX830ではなく WSL2側のターミナル

```
snmpwalk    → SNMPで機器に問い合わせるコマンド（テストツール）
-v2c        → SNMPバージョン2c を使う
-c monlab   → コミュニティ文字列（-c は community の略）
10.0.0.1    → 問い合わせ先（RTX830）
sysDescr.0  → 取得したい情報のOID
               MIB-II標準規格で定義された「機器の説明文」
               すべてのSNMP対応機器が持つ基本情報
```

**意味**: 「RTX830に `monlab` の合言葉で接続して、機器説明を取得してみる」
応答が返ってくれば SNMP が正しく動作していると確認できる。

---

## パフォーマンスへの影響

**結論：ほぼゼロ**

| 項目 | 実態 |
|------|------|
| CPU負荷 | SNMP応答は軽量処理。60秒間隔ポーリングは誤差レベル |
| 通信量 | UDPの小さなパケット（数百バイト）。回線に影響なし |
| ルーティング性能 | 影響なし。SNMPは管理プレーン、パケット転送は別処理 |

---

## セキュリティ分析

### リスクと軽減要因

| リスク | 内容 | 自宅LAN環境での評価 |
|--------|------|-------------------|
| 平文通信 | SNMPv2cはコミュニティ文字列を暗号化しない | LAN内のみ。WAN側は既存フィルターで遮断済み ✅ |
| 全LAN機器から問い合わせ可能 | IP制限なし | ro のため設定変更不可。コミュニティ名を推測困難にすれば許容範囲 ✅ |
| 情報開示 | ルーティングテーブル・ARP等が取れる | 自宅LAN内のリスクは低い ✅ |

### WAN側のフィルター確認（show configより確認済み）

```
ip pp secure filter in 200003 200020 ... （PPPoE WAN受信フィルター）
→ UDP 161（SNMPポート）を許可する行なし
→ インターネットからのSNMPアクセスは遮断されている ✅
```

### LAN側のフィルター（show configより確認済み）

```
ip lan1 に secure filter の設定なし
→ 10.0.0.220 → 10.0.0.1 の SNMP通信は通る ✅
```

### 総合判断

```
自宅LAN学習環境:  許容範囲内
会社・本番環境:   SNMPv3（暗号化・認証付き）を推奨
```

### より安全にする選択肢（将来の参考）

| 対策 | 効果 | 複雑さ |
|------|------|--------|
| SNMPv3に変更 | 暗号化・認証が使える | 高（設定が複雑） |
| 問い合わせ元IPを限定 | 10.0.0.220以外は不可 | 低（Yamaha対応要確認） |
| コミュニティ名を複雑にする | 推測されにくくなる | ゼロ |

---

## 作業手順（安全な進め方）

### Step 0：読み取り専用コマンドで事前確認

```bash
# RTX830にSSHで接続してから実行
show config          # 全設定を確認
show snmp            # SNMP設定の現状確認（投入前）
```

### Step 1：コミュニティ設定（save なし）

```bash
snmp community monlab ro    # SNMPを有効化
show snmp                   # 設定が反映されたか確認
```

### Step 2：疎通テスト（WSL2から）

```bash
# snmpwalk が未インストールの場合
sudo apt install -y snmp snmp-mibs-downloader

# テスト実行
snmpwalk -v2c -c monlab 10.0.0.1 sysDescr.0
```

### Step 3：応答確認 → save

```bash
# 応答例: SNMPv2-MIB::sysDescr.0 = STRING: RTX830 Rev.15.02.33 ...
# ↑このような応答が返ってきたら成功

save    # 設定を永続化
```

### ロールバック手順

```bash
# 設定を元に戻す（save 前なら再起動でも戻る）
no snmp community monlab
show snmp    # 削除を確認
save
```

---

## 学習で気づいたこと

- `snmp community monlab ro` だけでポーリングは動く（`snmp host` はトラップ用の可能性）
- `save` しなければ再起動で完全に元に戻る → 練習は save なしで
- Yamaha RTX の設定変更コマンドは即時反映される（reloadコマンド不要）
- CLIに不慣れな場合は「read-only コマンドで慣れる → save なしで試す → save」の3段階が安全

---

## 関連ファイル

- 設計書: `.specify/memory/specs/physical-device-monitoring.md`
- SNMP設定: `config/snmp/snmp.yml`
- Terragrunt定義: `terraform/envs/local/snmp-exporter/terragrunt.hcl`
- Prometheus設定: `config/prometheus/prometheus.yml`
