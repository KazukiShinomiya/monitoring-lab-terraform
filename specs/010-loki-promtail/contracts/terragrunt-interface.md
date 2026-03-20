# Contract: Terragrunt サービス定義インターフェース

**Module**: `terraform/modules/docker_container`
**Pattern**: 既存サービス（prometheus, grafana, alertmanager）と同一

---

## loki / terragrunt.hcl インターフェース

```hcl
inputs = {
  network_name = dependency.network.outputs.network_name

  volumes = ["loki_data"]

  services = {
    loki = {
      image         = "grafana/loki:3.4.2"
      internal_port = 3100
      external_port = 3100
      env           = []
      command       = ["-config.file=/etc/loki/loki.yml"]
      volumes = [
        { source = "loki_data", target = "/loki" }
      ]
      bind_mounts = [
        { source = "/home/ubuntu/monitoring-lab/loki/loki.yml",
          target = "/etc/loki/loki.yml", read_only = true }
      ]
    }
  }
}
```

**依存関係**:
- `dependency "network"`: `../network` → `network_name` を取得

**HCP Terraform Workspace**: `loki`（実行モード: Local）

---

## promtail / terragrunt.hcl インターフェース

```hcl
inputs = {
  network_name = dependency.network.outputs.network_name

  volumes = ["promtail_positions"]

  services = {
    promtail = {
      image         = "grafana/promtail:3.4.2"
      internal_port = 9080
      external_port = 9080
      env           = []
      command       = ["-config.file=/etc/promtail/promtail.yml"]
      volumes = [
        { source = "promtail_positions", target = "/tmp" }
      ]
      bind_mounts = [
        { source = "/home/ubuntu/monitoring-lab/promtail/promtail.yml",
          target = "/etc/promtail/promtail.yml", read_only = true },
        { source = "/var/run/docker.sock",
          target = "/var/run/docker.sock", read_only = true }
      ]
    }
  }
}
```

**依存関係**:
- `dependency "network"`: `../network` → `network_name` を取得
- `dependency "loki"`: `../loki` → `container_ids` を取得（起動順序制御）

**HCP Terraform Workspace**: `promtail`（実行モード: Local）

---

## モジュール制約事項

| 制約 | 値 | 備考 |
|------|-----|------|
| `restart` ポリシー | `unless-stopped` | モジュールでハードコード済み |
| ネットワーク接続 | 自動（aliases=[サービス名]） | DNS解決: `loki`, `promtail` |
| `privileged` | false | Docker Socket は bind mount で対応（特権不要） |
| ヘルスチェック | なし（モジュール未実装） | `/ready` エンドポイントで手動確認 |

---

## outputs（docker_container モジュール標準）

```hcl
output "container_ids" {
  value = { for k, v in docker_container.service : k => v.id }
}
```

`promtail` の `dependency "loki"` は `container_ids` を mock_outputs で指定して init 時のエラーを回避する。
