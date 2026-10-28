include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/docker_container"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    network_name = "monitoring-lab-network"
  }
}

inputs = {
  network_name = dependency.network.outputs.network_name

  volumes = [
    "wow_logs",
    "wow_geoip",
  ]

  services = {
    wow-exporter = {
      image         = "wow-exporter:latest"
      internal_port = 9200
      external_port = 9200

      env = [
        "WOW_VPS_HOST=${get_env("WOW_VPS_HOST", "")}",
        "LOG_DIR=/data/wow-logs",
        "GEOIP_DB=/data/geoip/GeoLite2-Country.mmdb",
        "GEOIP_ASN_DB=/data/geoip/GeoLite2-ASN.mmdb",
        "EXPORTER_PORT=9200",
        "SCRAPE_INTERVAL=300",
        "TOP_N=20",
        # blackbox-exporter の honeypot_http モジュールと揃える（config/blackbox/blackbox.yml）
        "PROBE_USER_AGENT=monitoring-lab-blackbox/1.0",
      ]

      volumes = [
        {
          source = "wow_logs"
          target = "/data/wow-logs"
        },
        {
          source = "wow_geoip"
          target = "/data/geoip"
        },
      ]

      bind_mounts = [
        {
          source    = "/home/ubuntu/.ssh/wow-exporter-key"
          target    = "/root/.ssh/id_ed25519"
          read_only = true
        },
        {
          # VPS のホスト鍵（sync-logs.sh が StrictHostKeyChecking=yes で使う）。
          # 先にサーバー上に置くこと。無いまま作ると Docker が同名の空ディレクトリを作る
          source    = "/home/ubuntu/.ssh/wow-exporter-known_hosts"
          target    = "/root/.ssh/known_hosts_wow"
          read_only = true
        },
      ]
    }
  }
}
