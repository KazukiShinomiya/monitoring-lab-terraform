import json
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
# wow_logs volume (/data/wow-logs) に保存してコンテナ再起動を跨いで永続化する
STATE_FILE = os.environ.get("STATE_FILE", "/data/wow-logs/wow-exporter.state.json")

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


def _serialize_tuple_counter(counter: Counter) -> list:
    return [[k, v, count] for (k, v), count in counter.items()]


def _deserialize_tuple_counter(data: list) -> Counter:
    result = Counter()
    for item in data:
        if len(item) == 3:
            result[(item[0], item[1])] = item[2]
    return result


def load_state():
    try:
        with open(STATE_FILE) as f:
            data = json.load(f)
        STATE["access_offset"] = data.get("access_offset", 0)
        STATE["access_https_offset"] = data.get("access_https_offset", 0)
        STATE["wow_offset"] = data.get("wow_offset", 0)
        STATE["wow_https_offset"] = data.get("wow_https_offset", 0)
        STATE["unique_ips"] = set(data.get("unique_ips", []))
        STATE["path_counts"] = Counter(data.get("path_counts", {}))
        STATE["ip_counts"] = Counter(data.get("ip_counts", {}))
        STATE["country_counts"] = _deserialize_tuple_counter(data.get("country_counts", []))
        STATE["asn_counts"] = _deserialize_tuple_counter(data.get("asn_counts", []))
        STATE["ua_counts"] = Counter(data.get("ua_counts", {}))
        STATE["ua_category_counts"] = Counter(data.get("ua_category_counts", {}))
        STATE["blocklist_ip_counts"] = Counter(data.get("blocklist_ip_counts", {}))
        logger.info(
            "State loaded: access_offset=%d, wow_offset=%d",
            STATE["access_offset"],
            STATE["wow_offset"],
        )
    except FileNotFoundError:
        pass
    except Exception:
        logger.exception("Failed to load state, starting from 0")


def save_state():
    try:
        data = {
            "access_offset": STATE["access_offset"],
            "access_https_offset": STATE["access_https_offset"],
            "wow_offset": STATE["wow_offset"],
            "wow_https_offset": STATE["wow_https_offset"],
            "unique_ips": list(STATE["unique_ips"]),
            "path_counts": dict(STATE["path_counts"]),
            "ip_counts": dict(STATE["ip_counts"]),
            "country_counts": _serialize_tuple_counter(STATE["country_counts"]),
            "asn_counts": _serialize_tuple_counter(STATE["asn_counts"]),
            "ua_counts": dict(STATE["ua_counts"]),
            "ua_category_counts": dict(STATE["ua_category_counts"]),
            "blocklist_ip_counts": dict(STATE["blocklist_ip_counts"]),
        }
        with open(STATE_FILE, "w") as f:
            json.dump(data, f)
    except Exception:
        logger.exception("Failed to save state")


def _process_access_entry(entry, protocol: str = "http") -> None:
    label_path = entry.path[:64]
    metrics.http_requests_total.labels(
        method=entry.method,
        path=label_path,
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
    load_state()
    start_http_server(PORT)
    logger.info("Exporter started on :%d", PORT)

    while True:
        try:
            process_access_log("access_log", "http")
            process_access_log("access_log_https", "https")
            process_wow_log("wowhoneypot.log", "http")
            process_wow_log("wowhoneypot_https.log", "https")
            metrics.last_sync_timestamp.set(time.time())
            save_state()
        except Exception:
            logger.exception("Processing error")
        time.sleep(SCRAPE_INTERVAL)


if __name__ == "__main__":
    main()
