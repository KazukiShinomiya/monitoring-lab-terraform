# Contract: Terragrunt インターフェース定義

**Date**: 2026-04-19

---

## 新規ファイル: `terraform/envs/local/victoriametrics/terragrunt.hcl`

### モジュール参照

```hcl
terraform {
  source = "../../../modules/docker_container"
}
```

### 必須 inputs

| 変数 | 型 | 値 |
|---|---|---|
| `network_name` | string | `dependency.network.outputs.network_name` |
| `volumes` | list(object) | `[{name = "vm_data"}]` |
| `services` | map(object) | 下記参照 |

### services オブジェクト構造

```hcl
services = {
  victoriametrics = {
    image         = "victoriametrics/victoria-metrics:stable"
    internal_port = 8428
    external_port = 8428
    command = [
      "-retentionPeriod=12",
      "-storageDataPath=/victoria-metrics-data"
    ]
    env        = []
    volumes    = [{source = "vm_data", target = "/victoria-metrics-data"}]
    bind_mounts = []
  }
}
```

### 依存関係

```hcl
dependency "network" {
  config_path = "../network"
  mock_outputs = {
    network_name = "monitoring-lab-network"
  }
}
```

---

## 既存ファイル変更: `terraform/envs/local/prometheus/terragrunt.hcl`

**変更なし** — prometheus.yml の `remote_write` 設定はファイル変更のみ（bind mount はすでに設定済み）

---

## HCP Terraform Workspace

| 項目 | 値 |
|---|---|
| Workspace 名 | `monitoring-lab-local-victoriametrics` |
| 実行モード | `Local`（他の Workspace と同様） |
| State バックエンド | HCP Terraform (k1981-learning-lab) |

**注意**: `terragrunt init` で自動作成されるが、デフォルトは "Remote" 実行モード。  
API PATCH で "Local" に変更が必要（既知の手順）。
