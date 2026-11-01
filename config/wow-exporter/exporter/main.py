import logging
import os
import time
from collections import Counter

from prometheus_client import start_http_server

from . import geoip, metrics
from .insights import FirstSeenStore, Insights
from .parser import parse_access_line, parse_wow_line

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

LOG_DIR = os.environ.get("LOG_DIR", "/data/wow-logs")
GEOIP_DB = os.environ.get("GEOIP_DB", "/data/geoip/GeoLite2-Country.mmdb")
GEOIP_ASN_DB = os.environ.get("GEOIP_ASN_DB", "/data/geoip/GeoLite2-ASN.mmdb")
PORT = int(os.environ.get("EXPORTER_PORT", "9200"))
SCRAPE_INTERVAL = int(os.environ.get("SCRAPE_INTERVAL", "300"))
TOP_N = int(os.environ.get("TOP_N", "20"))
# 自前の外形監視（blackbox-exporter）のリクエストは攻撃ではないので集計から除く。空なら除外しない
PROBE_USER_AGENT = os.environ.get("PROBE_USER_AGENT", "")
# 新顔の判定に使う「初めて見た時刻」の置き場所。ログとは別のボリュームに置く
STATE_DIR = os.environ.get("STATE_DIR", "/data/wow-state")
RECENT_WINDOW_HOURS = int(os.environ.get("RECENT_WINDOW_HOURS", "24"))
NEW_PATH_WINDOW_HOURS = int(os.environ.get("NEW_PATH_WINDOW_HOURS", "168"))
FIRST_SEEN_RETENTION_DAYS = int(os.environ.get("FIRST_SEEN_RETENTION_DAYS", "180"))

# main() で作る。テストでは差し替える
INSIGHTS = None

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


def _geo(src_ip: str):
    code, name = geoip.lookup(src_ip)
    asn, org = geoip.lookup_asn(src_ip)
    return ((code, name or code) if code else None), ((asn, org or asn) if asn else None)


def _observe_insights(entry, country, asn) -> None:
    if INSIGHTS is None:
        return
    INSIGHTS.observe(
        ts=entry.timestamp.timestamp(),
        path=entry.path,
        path_bucket=entry.path_bucket,
        src_ip=entry.src_ip,
        user_agent=entry.user_agent,
        country=country,
        asn=asn,
    )


def _set_top(gauge, rows) -> None:
    """上位から落ちた系列が古い値のまま残らないよう、消してから書く。"""
    gauge.clear()
    for labels, value in rows:
        gauge.labels(*labels).set(value)


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

    country, asn = _geo(entry.src_ip)
    if country:
        STATE["country_counts"][country] += 1
    if asn:
        STATE["asn_counts"][asn] += 1
    _observe_insights(entry, country, asn)

    metrics.requests_by_ua_category_total.labels(category=entry.ua_category).inc()
    STATE["ua_category_counts"][entry.ua_category] += 1
    if entry.user_agent:
        STATE["ua_counts"][entry.user_agent[:128]] += 1


def _flush_access_gauges() -> None:
    metrics.unique_ips_gauge.set(len(STATE["unique_ips"]))

    _set_top(metrics.top_paths_gauge, (((p,), c) for p, c in STATE["path_counts"].most_common(TOP_N)))
    _set_top(metrics.top_ips_gauge, (((ip,), c) for ip, c in STATE["ip_counts"].most_common(TOP_N)))

    for (code, name), count in STATE["country_counts"].items():
        metrics.requests_by_country.labels(country_code=code, country_name=name).set(count)

    _set_top(metrics.requests_by_asn, (((a, o), c) for (a, o), c in STATE["asn_counts"].most_common(TOP_N)))
    _set_top(metrics.top_user_agents_gauge, (((ua,), c) for ua, c in STATE["ua_counts"].most_common(TOP_N)))

    for category, count in STATE["ua_category_counts"].items():
        metrics.requests_by_ua_category.labels(category=category).set(count)


def _flush_insights(now: float) -> None:
    if INSIGHTS is None:
        return
    ins = INSIGHTS
    ins.prune(now)
    w = RECENT_WINDOW_HOURS
    metrics.recent_window_seconds.set(w * 3600)

    _set_top(metrics.recent_requests_by_bucket, (((b,), c) for b, c in ins.buckets.window(now, w).items()))

    ips = ins.ips.window(now, w)
    metrics.recent_unique_src_ips.set(len(ips))
    _set_top(metrics.recent_top_ips, (((ip,), c) for ip, c in ips.most_common(TOP_N)))

    _set_top(
        metrics.recent_top_paths,
        (((p, ins.path_bucket_of(p)), c) for p, c in ins.paths.window(now, w).most_common(TOP_N)),
    )
    _set_top(
        metrics.recent_top_user_agents,
        (((ua,), c) for ua, c in ins.user_agents.window(now, w).most_common(TOP_N)),
    )
    _set_top(
        metrics.recent_top_asns,
        (((a, o), c) for (a, o), c in ins.asns.window(now, w).most_common(TOP_N)),
    )
    _set_top(
        metrics.recent_requests_by_country,
        (((cc, cn), c) for (cc, cn), c in ins.countries.window(now, w).items()),
    )

    rows = ins.new_paths(now, TOP_N)
    _set_top(metrics.new_path_requests, (((k[:64], ins.path_bucket_of(k)), n) for k, _, n in rows))
    _set_top(metrics.new_path_first_seen, (((k[:64], ins.path_bucket_of(k)), f) for k, f, _ in rows))
    metrics.new_paths_24h.set(ins.new_path_count(now, 24))
    metrics.known_paths.set(len(ins.store))

    try:
        ins.store.save()
    except OSError:
        logger.exception("failed to save first-seen store")


def seed_from_previous_generation(log_file: str) -> None:
    """起動時に前の世代（.1）を読み、窓の集計と初見だけを埋める。

    累計の Counter / Gauge には足さない（既存の値の意味を変えないため）。
    現世代だけだとローテーション直後の再起動で直近 24 時間が欠けるので、その穴を塞ぐ。
    """
    if INSIGHTS is None:
        return
    path = os.path.join(LOG_DIR, log_file + ".1")
    if not os.path.exists(path):
        return
    n = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            entry = parse_access_line(line)
            if not entry:
                continue
            if PROBE_USER_AGENT and entry.user_agent == PROBE_USER_AGENT:
                continue
            country, asn = _geo(entry.src_ip)
            _observe_insights(entry, country, asn)
            n += 1
    logger.info("%s.1: seeded %d lines into recent/first-seen", log_file, n)


def process_access_log(log_file: str = "access_log", protocol: str = "http") -> None:
    path = os.path.join(LOG_DIR, log_file)
    if not os.path.exists(path):
        return

    offset_key = "access_offset" if protocol == "http" else "access_https_offset"

    if os.path.getsize(path) < STATE[offset_key]:
        logger.warning("%s has shrunk (rotation detected), resetting offset", log_file)
        STATE[offset_key] = 0

    new_lines = 0
    probe_lines = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        f.seek(STATE[offset_key])
        for line in f:
            entry = parse_access_line(line)
            if entry:
                if PROBE_USER_AGENT and entry.user_agent == PROBE_USER_AGENT:
                    probe_lines += 1
                    continue
                _process_access_entry(entry, protocol=protocol)
                new_lines += 1
        STATE[offset_key] = f.tell()

    metrics.processed_lines_gauge.labels(log_file=log_file).set(STATE[offset_key])
    _flush_access_gauges()

    if new_lines or probe_lines:
        logger.info("%s: processed %d new lines (skipped %d probe lines)", log_file, new_lines, probe_lines)


def _flush_wow_gauges() -> None:
    _set_top(
        metrics.top_blocklisted_ips_gauge,
        (((ip,), c) for ip, c in STATE["blocklist_ip_counts"].most_common(TOP_N)),
    )


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
    global INSIGHTS
    geoip.init(GEOIP_DB)
    geoip.init_asn(GEOIP_ASN_DB)

    store = FirstSeenStore(os.path.join(STATE_DIR, "first_seen.json"), FIRST_SEEN_RETENTION_DAYS)
    bootstrap = not store.load()
    logger.info("first-seen store: %d paths (%s)", len(store), "bootstrap" if bootstrap else "loaded")
    INSIGHTS = Insights(store, window_hours=RECENT_WINDOW_HOURS, new_path_hours=NEW_PATH_WINDOW_HOURS)
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

    seed_from_previous_generation("access_log_https")
    seed_from_previous_generation("access_log")

    while True:
        try:
            # 低ボリュームの https を先に処理する。起動時の全再読込では http ログが
            # 巨大（数十万行）で数分かかるため、後回しにすると https 系列の復元が
            # 遅れる。復旧対象を先に処理して速やかに可視化を回復させる。
            process_access_log("access_log_https", "https")
            process_wow_log("wowhoneypot_https.log", "https")
            process_access_log("access_log", "http")
            process_wow_log("wowhoneypot.log", "http")
            if bootstrap:
                # 記録ファイルが無かった初回だけ。読み終えた分を既知として扱う
                INSIGHTS.store.mark_all_as_baseline()
                bootstrap = False
                logger.info("first-seen store bootstrapped with %d known paths", len(INSIGHTS.store))
            _flush_insights(time.time())
            metrics.last_sync_timestamp.set(time.time())
        except Exception:
            logger.exception("Processing error")
        time.sleep(SCRAPE_INTERVAL)


if __name__ == "__main__":
    main()
