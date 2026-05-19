from prometheus_client import Counter, Gauge

# access_log メトリクス
http_requests_total = Counter(
    "wowhoneypot_http_requests_total",
    "Total HTTP requests received by honeypot",
    ["method", "path", "status", "matched", "protocol"],
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
