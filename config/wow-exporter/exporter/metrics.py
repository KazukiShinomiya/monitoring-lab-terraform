from prometheus_client import Counter, Gauge

# access_log メトリクス
# path は生値だと攻撃パスの多様性で系列が際限なく増える（実測~3万系列）ため、
# categorize_path() による有限バケットのみをラベル化する。生パスの上位は
# top_paths_gauge が担う。
http_requests_total = Counter(
    "wowhoneypot_http_requests_total",
    "Total HTTP requests received by honeypot",
    ["method", "path_bucket", "status", "matched", "protocol"],
)

unique_ips_gauge = Gauge(
    "wowhoneypot_unique_src_ips",
    "Number of unique source IPs seen",
)

top_paths_gauge = Gauge(
    "wowhoneypot_top_path_requests",
    "Request count per path (top paths)",
    ["path"],
)

top_ips_gauge = Gauge(
    "wowhoneypot_top_src_ip_requests",
    "Request count per source IP (top IPs)",
    ["src_ip"],
)

matched_requests_total = Counter(
    "wowhoneypot_matched_requests_total",
    "Requests that matched a honeypot rule",
)

# wowhoneypot.log メトリクス
blocklist_denials_total = Counter(
    "wowhoneypot_blocklist_denials_total",
    "Total accesses denied by blocklist",
)

top_blocklisted_ips_gauge = Gauge(
    "wowhoneypot_top_blocklisted_ips",
    "Denial count per blocklisted source IP (top IPs)",
    ["src_ip"],
)

timeout_errors_total = Counter(
    "wowhoneypot_timeout_errors_total",
    "Total request timeout errors",
)

# GeoIP メトリクス
requests_by_country = Gauge(
    "wowhoneypot_requests_by_country",
    "Request count per country",
    ["country_code", "country_name"],
)

requests_by_asn = Gauge(
    "wowhoneypot_requests_by_asn",
    "Request count per ASN (top ASNs)",
    ["asn", "org"],
)

# User-Agent メトリクス
top_user_agents_gauge = Gauge(
    "wowhoneypot_top_user_agents",
    "Request count per user agent string (top agents)",
    ["user_agent"],
)

requests_by_ua_category = Gauge(
    "wowhoneypot_requests_by_ua_category",
    "Cumulative request count per user agent category",
    ["category"],
)

requests_by_ua_category_total = Counter(
    "wowhoneypot_ua_category_requests_total",
    "Counter for rate-based trend analysis per UA category",
    ["category"],
)

# 直近の窓（RECENT_WINDOWS、既定 1h・24h・7d）ごとの集計。window ラベルで窓を表す。
# ログの時刻で数えるので再起動・読み直しで値が跳ねない。重複を除いた IP 数や上位の一覧は
# Counter からは任意の期間で出せないので、ここで窓を決めて出し、Grafana の変数で選ぶ。
# 件数そのものは Counter（http_requests_total）の increase([$__range]) で期間に連動させる。

recent_requests_by_bucket = Gauge(
    "wowhoneypot_recent_requests_by_bucket",
    "Requests per path category in the recent window (by log timestamp)",
    ["path_bucket", "window"],
)

recent_unique_src_ips = Gauge(
    "wowhoneypot_recent_unique_src_ips",
    "Unique source IPs in the recent window",
    ["window"],
)

recent_top_paths = Gauge(
    "wowhoneypot_recent_top_path_requests",
    "Requests per path in the recent window (top paths)",
    ["path", "path_bucket", "window"],
)

recent_top_ips = Gauge(
    "wowhoneypot_recent_top_src_ip_requests",
    "Requests per source IP in the recent window (top IPs)",
    ["src_ip", "window"],
)

recent_top_user_agents = Gauge(
    "wowhoneypot_recent_top_user_agent_requests",
    "Requests per user agent in the recent window (top agents)",
    ["user_agent", "window"],
)

recent_top_asns = Gauge(
    "wowhoneypot_recent_top_asn_requests",
    "Requests per ASN in the recent window (top ASNs)",
    ["asn", "org", "window"],
)

recent_requests_by_country = Gauge(
    "wowhoneypot_recent_requests_by_country",
    "Requests per country in the recent window",
    ["country_code", "country_name", "window"],
)

# 新顔のパス（初見が NEW_PATH_WINDOW_HOURS 以内、既定 7 日）。初見は永続化している
new_path_requests = Gauge(
    "wowhoneypot_new_path_requests",
    "Requests to paths first seen within the new-path window (top by count)",
    ["path", "path_bucket"],
)

new_path_first_seen = Gauge(
    "wowhoneypot_new_path_first_seen_timestamp",
    "Unix timestamp when the path was first seen",
    ["path", "path_bucket"],
)

new_paths_24h = Gauge(
    "wowhoneypot_new_paths_24h",
    "Number of distinct paths first seen in the last 24 hours",
)

known_paths = Gauge(
    "wowhoneypot_known_paths",
    "Number of distinct paths in the first-seen store",
)

# 処理状態
processed_lines_gauge = Gauge(
    "wowhoneypot_processed_lines",
    "Byte offset of last processed position in log file",
    ["log_file"],
)

last_sync_timestamp = Gauge(
    "wowhoneypot_last_sync_timestamp",
    "Unix timestamp of last log sync",
)
