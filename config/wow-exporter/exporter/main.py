import logging
import os
import time
from collections import Counter

from prometheus_client import start_http_server

from . import geoip, metrics
from .parser import parse_access_line, parse_wow_line

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

LOG_DIR = os.environ.get("LOG_DIR", "/data/wow-logs")
GEOIP_DB = os.environ.get("GEOIP_DB", "/data/geoip/GeoLite2-Country.mmdb")
GEOIP_ASN_DB = os.environ.get("GEOIP_ASN_DB", "/data/geoip/GeoLite2-ASN.mmdb")
PORT = int(os.environ.get("EXPORTER_PORT", "9200"))
SCRAPE_INTERVAL = int(os.environ.get("SCRAPE_INTERVAL", "300"))
TOP_N = int(os.environ.get("TOP_N", "20"))

STATE = {
    "access_offset": 0,
    "access_https_offset": 0,
    "wow_offset": 0,
    "wow_https_offset": 0,
    "unique_ips": set(),
    "path_counts": Counter(),
    "ip_counts": Counter(),
    "country_counts": Counter(),
    "asn_counts": Counter(),
    "ua_counts": Counter(),
    "ua_category_counts": Counter(),
    "blocklist_ip_counts": Counter(),
}


def _process_access_entry(entry, protocol: str = "http") -> None:
    label_path = entry.path[:64]
    metrics.http_requests_total.labels(
        method=entry.method,
        path_bucket=entry.path_bucket,
        status=str(entry.status),
        matched=str(entry.matched),
        protocol=protocol,
    ).inc()

    if entry.matched:
        metrics.matched_requests_total.inc()

    STATE["path_counts"][label_path] += 1
    STATE["ip_counts"][entry.src_ip] += 1
    STATE["unique_ips"].add(entry.src_ip)

    code, name = geoip.lookup(entry.src_ip)
    if code:
        STATE["country_counts"][(code, name or code)] += 1

    asn, org = geoip.lookup_asn(entry.src_ip)
    if asn:
        STATE["asn_counts"][(asn, org or asn)] += 1

    metrics.requests_by_ua_category_total.labels(category=entry.ua_category).inc()
    STATE["ua_category_counts"][entry.ua_category] += 1
    if entry.user_agent:
        STATE["ua_counts"][entry.user_agent[:128]] += 1


def _flush_access_gauges() -> None:
    metrics.unique_ips_gauge.set(len(STATE["unique_ips"]))

    for path_label, count in STATE["path_counts"].most_common(TOP_N):
        metrics.top_paths_gauge.labels(path=path_label).set(count)

    for ip, count in STATE["ip_counts"].most_common(TOP_N):
        metrics.top_ips_gauge.labels(src_ip=ip).set(count)

    for (code, name), count in STATE["country_counts"].items():
        metrics.requests_by_country.labels(country_code=code, country_name=name).set(count)

    for (asn, org), count in STATE["asn_counts"].most_common(TOP_N):
        metrics.requests_by_asn.labels(asn=asn, org=org).set(count)

    for ua, count in STATE["ua_counts"].most_common(TOP_N):
        metrics.top_user_agents_gauge.labels(user_agent=ua).set(count)

    for category, count in STATE["ua_category_counts"].items():
        metrics.requests_by_ua_category.labels(category=category).set(count)


def process_access_log(log_file: str = "access_log", protocol: str = "http") -> None:
    path = os.path.join(LOG_DIR, log_file)
    if not os.path.exists(path):
        return

    offset_key = "access_offset" if protocol == "http" else "access_https_offset"

    if os.path.getsize(path) < STATE[offset_key]:
        logger.warning("%s has shrunk (rotation detected), resetting offset", log_file)
        STATE[offset_key] = 0

    new_lines = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        f.seek(STATE[offset_key])
        for line in f:
            entry = parse_access_line(line)
            if entry:
                _process_access_entry(entry, protocol=protocol)
                new_lines += 1
        STATE[offset_key] = f.tell()

    metrics.processed_lines_gauge.labels(log_file=log_file).set(STATE[offset_key])
    _flush_access_gauges()

    if new_lines:
        logger.info("%s: processed %d new lines", log_file, new_lines)


def _flush_wow_gauges() -> None:
    for ip, count in STATE["blocklist_ip_counts"].most_common(TOP_N):
        metrics.top_blocklisted_ips_gauge.labels(src_ip=ip).set(count)


def process_wow_log(log_file: str = "wowhoneypot.log", protocol: str = "http") -> None:
    path = os.path.join(LOG_DIR, log_file)
    if not os.path.exists(path):
        return

    offset_key = "wow_offset" if protocol == "http" else "wow_https_offset"

    if os.path.getsize(path) < STATE[offset_key]:
        logger.warning("%s has shrunk (rotation detected), resetting offset", log_file)
        STATE[offset_key] = 0

    new_lines = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        f.seek(STATE[offset_key])
        for line in f:
            entry = parse_wow_line(line)
            if not entry:
                continue
            new_lines += 1
            if entry.event_type == "blocklist":
                metrics.blocklist_denials_total.inc()
                if entry.ip:
                    STATE["blocklist_ip_counts"][entry.ip] += 1
            elif entry.event_type == "timeout":
                metrics.timeout_errors_total.inc()
        STATE[offset_key] = f.tell()

    metrics.processed_lines_gauge.labels(log_file=log_file).set(STATE[offset_key])
    _flush_wow_gauges()

    if new_lines:
        logger.info("%s: processed %d new lines", log_file, new_lines)


def main():
    geoip.init(GEOIP_DB)
    geoip.init_asn(GEOIP_ASN_DB)
    # 起動時は空の STATE から始め、ログ全体を読み直して全メトリクスを再構築する。
    # 以前はオフセットと集計dictだけを永続化していたが、Prometheus Counter
    # (http_requests_total 等) は非永続でプロセス起動時に0へ戻る。オフセットを
    # 復元して既存行を飛ばすと、新規トラフィックが来ない protocol（例: https）の
    # Counter 系列が二度と生成されず Grafana で No data になる（2026-07 の HTTPS
    # 監視盲目の機序）。ログ全体を毎起動で再集計すれば Gauge も Counter も実ログ
    # と常に一致する。プロセス内のオフセットは二重計上防止のため引き続き機能する。
    # Prometheus 側のカウンタリセットは increase()/rate() が正しく処理する。
    start_http_server(PORT)
    logger.info("Exporter started on :%d", PORT)

    while True:
        try:
            # 低ボリュームの https を先に処理する。起動時の全再読込では http ログが
            # 巨大（数十万行）で数分かかるため、後回しにすると https 系列の復元が
            # 遅れる。復旧対象を先に処理して速やかに可視化を回復させる。
            process_access_log("access_log_https", "https")
            process_wow_log("wowhoneypot_https.log", "https")
            process_access_log("access_log", "http")
            process_wow_log("wowhoneypot.log", "http")
            metrics.last_sync_timestamp.set(time.time())
        except Exception:
            logger.exception("Processing error")
        time.sleep(SCRAPE_INTERVAL)


if __name__ == "__main__":
    main()
