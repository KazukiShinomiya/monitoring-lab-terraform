import logging
import os
import signal
import time
from collections import Counter
from typing import Callable, Dict, List, Optional, Tuple

from prometheus_client import start_http_server

from . import checkpoint as ckpt
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
# 初見の記録（first_seen.json）とチェックポイント（checkpoint.json）の置き場所。ログとは別のボリューム
STATE_DIR = os.environ.get("STATE_DIR", "/data/wow-state")
NEW_PATH_WINDOW_HOURS = int(os.environ.get("NEW_PATH_WINDOW_HOURS", "168"))
FIRST_SEEN_RETENTION_DAYS = int(os.environ.get("FIRST_SEEN_RETENTION_DAYS", "180"))


def parse_windows(spec: str) -> List[Tuple[str, int]]:
    """"1h,24h,7d" → [("1h", 1), ("24h", 24), ("7d", 168)]。ラベルは書かれたまま使う。"""
    out = []
    for part in (p.strip() for p in spec.split(",")):
        if not part:
            continue
        unit = part[-1]
        if unit not in "hd" or not part[:-1].isdigit() or int(part[:-1]) <= 0:
            raise ValueError("RECENT_WINDOWS: %r は 1h・24h・7d の形で書く" % part)
        out.append((part, int(part[:-1]) * (24 if unit == "d" else 1)))
    if not out:
        raise ValueError("RECENT_WINDOWS が空")
    return out


# 直近の集計の窓。IP 数・上位の一覧はこの中から Grafana の変数で選ぶ
RECENT_WINDOWS = parse_windows(os.environ.get("RECENT_WINDOWS", "1h,24h,7d"))

# 読むログ。(ファイル名, 種類, protocol)。低ボリュームの https を先に処理する
LOG_FILES = [
    ("access_log_https", "access", "https"),
    ("wowhoneypot_https.log", "wow", "https"),
    ("access_log", "access", "http"),
    ("wowhoneypot.log", "wow", "http"),
]

# 再起動をまたいで値を続けるカウンタ（checkpoint.py）
PERSISTED_COUNTERS = [
    metrics.http_requests_total,
    metrics.matched_requests_total,
    metrics.blocklist_denials_total,
    metrics.timeout_errors_total,
    metrics.requests_by_ua_category_total,
]

# main() で作る。テストでは差し替える
INSIGHTS = None
CHECKPOINT = None


def _new_state() -> dict:
    return {
        # ファイルごとの読み終えた位置（バイト）と、その時点の先頭のハッシュ
        "offsets": {},
        "heads": {},
        # この位置より前の行はカウンタに数え済み（チェックポイントから戻した分）
        "count_from": {},
        "unique_ips": set(),
        "path_counts": Counter(),
        "ip_counts": Counter(),
        "country_counts": Counter(),
        "asn_counts": Counter(),
        "ua_counts": Counter(),
        "ua_category_counts": Counter(),
        "blocklist_ip_counts": Counter(),
    }


STATE = _new_state()


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


# --- 1 行ごとの処理 -------------------------------------------------------

def _count_access(entry, protocol: str) -> None:
    metrics.http_requests_total.labels(
        method=entry.method,
        path_bucket=entry.path_bucket,
        status=str(entry.status),
        matched=str(entry.matched),
        protocol=protocol,
    ).inc()
    if entry.matched:
        metrics.matched_requests_total.inc()
    metrics.requests_by_ua_category_total.labels(category=entry.ua_category).inc()


def _aggregate_access(entry, country, asn) -> None:
    STATE["path_counts"][entry.path[:64]] += 1
    STATE["ip_counts"][entry.src_ip] += 1
    STATE["unique_ips"].add(entry.src_ip)
    if country:
        STATE["country_counts"][country] += 1
    if asn:
        STATE["asn_counts"][asn] += 1
    STATE["ua_category_counts"][entry.ua_category] += 1
    if entry.user_agent:
        STATE["ua_counts"][entry.user_agent[:128]] += 1


def _process_access_entry(entry, protocol: str = "http", count: bool = True) -> None:
    if count:
        _count_access(entry, protocol)
    country, asn = _geo(entry.src_ip)
    _aggregate_access(entry, country, asn)
    _observe_insights(entry, country, asn)


def _access_handler(protocol: str, mode: str):
    """mode: "full"（集計もカウンタも）/ "seed"（前の世代: 窓と初見だけ。count 時はカウンタも）"""
    stats = {"lines": 0, "probe": 0}

    def handle(line: str, count: bool) -> None:
        entry = parse_access_line(line)
        if not entry:
            return
        if PROBE_USER_AGENT and entry.user_agent == PROBE_USER_AGENT:
            stats["probe"] += 1
            return
        stats["lines"] += 1
        if mode == "full":
            _process_access_entry(entry, protocol=protocol, count=count)
        else:
            if count:
                _count_access(entry, protocol)
            country, asn = _geo(entry.src_ip)
            _observe_insights(entry, country, asn)

    return handle, stats


def _wow_handler(protocol: str, mode: str):
    stats = {"lines": 0, "probe": 0}

    def handle(line: str, count: bool) -> None:
        entry = parse_wow_line(line)
        if not entry:
            return
        stats["lines"] += 1
        if entry.event_type == "blocklist":
            if count:
                metrics.blocklist_denials_total.inc()
            if entry.ip and mode == "full":
                STATE["blocklist_ip_counts"][entry.ip] += 1
        elif entry.event_type == "timeout":
            if count:
                metrics.timeout_errors_total.inc()

    return handle, stats


_HANDLERS = {"access": _access_handler, "wow": _wow_handler}


def _read(path: str, start: int, handle: Callable[[str, bool], None], count_from: Optional[int]) -> int:
    """path を start から最後まで読み、各行を handle に渡す。読み終えた位置を返す。

    count_from より前から始まる行はカウンタに数え済みとして count=False で渡す。
    None なら一切数えない。
    """
    pos = start
    with open(path, "rb") as f:
        f.seek(start)
        for raw in f:
            line_start = pos
            pos += len(raw)
            count = count_from is not None and line_start >= count_from
            handle(raw.decode("utf-8", errors="replace"), count)
    return pos


# --- ファイルごとの処理 ---------------------------------------------------

def _rotated(path: str, log_file: str, offset: int) -> bool:
    if os.path.getsize(path) < offset:
        return True
    head_len, head = STATE["heads"].get(log_file, (0, None))
    return not ckpt.same_file(path, head_len, head)


def process_log(log_file: str, kind: str, protocol: str) -> None:
    path = os.path.join(LOG_DIR, log_file)
    if not os.path.exists(path):
        return
    handle, stats = _HANDLERS[kind](protocol, "full")
    offset = STATE["offsets"].get(log_file, 0)

    if offset and _rotated(path, log_file, offset):
        # 前の世代の、まだ読んでいない末尾を .1 から読む（sync-logs.sh は継ぎ足してから .1 へ名前を変える）
        prev = path + ".1"
        head_len, head = STATE["heads"].get(log_file, (0, None))
        if head_len and os.path.exists(prev) and ckpt.same_file(prev, head_len, head):
            before = stats["lines"]
            _read(prev, offset, handle, STATE["count_from"].get(log_file, 0))
            logger.warning("%s: rotation detected, read %d remaining lines from .1", log_file, stats["lines"] - before)
        else:
            logger.warning("%s: rotation detected, .1 does not match; previous generation tail skipped", log_file)
        offset = 0
        STATE["count_from"][log_file] = 0

    end = _read(path, offset, handle, STATE["count_from"].get(log_file, 0))
    STATE["offsets"][log_file] = end
    STATE["heads"][log_file] = ckpt.identity(path, end)
    metrics.processed_lines_gauge.labels(log_file=log_file).set(end)

    if stats["lines"] or stats["probe"]:
        logger.info("%s: processed %d new lines (skipped %d probe lines)", log_file, stats["lines"], stats["probe"])


# 以前の呼び名（テスト等から使う）
def process_access_log(log_file: str = "access_log", protocol: str = "http") -> None:
    process_log(log_file, "access", protocol)
    _flush_access_gauges()


def process_wow_log(log_file: str = "wowhoneypot.log", protocol: str = "http") -> None:
    process_log(log_file, "wow", protocol)
    _flush_wow_gauges()


def seed_from_previous_generation(log_file: str, kind: str = "access", count_from: Optional[int] = None) -> None:
    """起動時に前の世代（.1）を読む。

    access は窓の集計と初見を埋める（現世代だけだとローテーション直後の再起動で窓が欠ける）。
    count_from が与えられたら（止まっている間にローテーションした）、その位置より後の行を
    カウンタにも足す。累計の Gauge（STATE）には足さない。
    """
    if kind == "access" and INSIGHTS is None and count_from is None:
        return
    if kind == "wow" and count_from is None:
        return
    path = os.path.join(LOG_DIR, log_file + ".1")
    if not os.path.exists(path):
        return
    handle, stats = _HANDLERS[kind]("https" if "https" in log_file else "http", "seed")
    if kind == "access":
        _read(path, 0, handle, count_from)
    else:
        _read(path, count_from, handle, count_from)
    logger.info("%s.1: seeded %d lines (counting from %s)", log_file, stats["lines"], count_from)


# --- 出力 ----------------------------------------------------------------

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


def _flush_wow_gauges() -> None:
    _set_top(
        metrics.top_blocklisted_ips_gauge,
        (((ip,), c) for ip, c in STATE["blocklist_ip_counts"].most_common(TOP_N)),
    )


def _flush_insights(now: float) -> None:
    if INSIGHTS is None:
        return
    ins = INSIGHTS
    ins.prune(now)

    buckets, ips, paths, uas, asns, countries, unique = [], [], [], [], [], [], []
    for label, hours in RECENT_WINDOWS:
        buckets += [((b, label), c) for b, c in ins.buckets.window(now, hours).items()]
        w_ips = ins.ips.window(now, hours)
        metrics.recent_unique_src_ips.labels(window=label).set(len(w_ips))
        ips += [((ip, label), c) for ip, c in w_ips.most_common(TOP_N)]
        paths += [((p, ins.path_bucket_of(p), label), c) for p, c in ins.paths.window(now, hours).most_common(TOP_N)]
        uas += [((ua, label), c) for ua, c in ins.user_agents.window(now, hours).most_common(TOP_N)]
        asns += [((a, o, label), c) for (a, o), c in ins.asns.window(now, hours).most_common(TOP_N)]
        countries += [((cc, cn, label), c) for (cc, cn), c in ins.countries.window(now, hours).items()]
    _set_top(metrics.recent_requests_by_bucket, buckets)
    _set_top(metrics.recent_top_ips, ips)
    _set_top(metrics.recent_top_paths, paths)
    _set_top(metrics.recent_top_user_agents, uas)
    _set_top(metrics.recent_top_asns, asns)
    _set_top(metrics.recent_requests_by_country, countries)

    rows = ins.new_paths(now, TOP_N)
    _set_top(metrics.new_path_requests, (((k[:64], ins.path_bucket_of(k)), n) for k, _, n in rows))
    _set_top(metrics.new_path_first_seen, (((k[:64], ins.path_bucket_of(k)), f) for k, f, _ in rows))
    metrics.new_paths_24h.set(ins.new_path_count(now, 24))
    metrics.known_paths.set(len(ins.store))

    try:
        ins.store.save()
    except OSError:
        logger.exception("failed to save first-seen store")


def save_checkpoint() -> None:
    if CHECKPOINT is None:
        return
    files = {}
    for log_file, offset in STATE["offsets"].items():
        head_len, head = STATE["heads"].get(log_file, (0, None))
        files[log_file] = {"offset": offset, "head_len": head_len, "head": head}
    try:
        CHECKPOINT.save(files, ckpt.snapshot_counters(PERSISTED_COUNTERS))
    except OSError:
        logger.exception("failed to save checkpoint")


def restore_from_checkpoint(cp: "ckpt.Checkpoint") -> Dict[str, Optional[int]]:
    """カウンタを前回の値に戻し、ファイルごとに「どこから数えるか」を決める。

    戻り値は前の世代（.1）について、カウンタに足し始める位置（止まっている間に
    ローテーションしたファイルだけ）。
    """
    n = ckpt.restore_counters(PERSISTED_COUNTERS, cp.counters)
    prev_count_from: Dict[str, Optional[int]] = {}
    for log_file, info in cp.files.items():
        path = os.path.join(LOG_DIR, log_file)
        offset, head_len, head = int(info["offset"]), int(info.get("head_len", 0)), info.get("head")
        if os.path.exists(path) and os.path.getsize(path) >= offset and ckpt.same_file(path, head_len, head):
            STATE["count_from"][log_file] = offset
        elif head_len and ckpt.same_file(path + ".1", head_len, head):
            # 止まっている間にローテーションした。.1 の offset より後と、現世代の全部が未計上
            prev_count_from[log_file] = offset
            STATE["count_from"][log_file] = 0
            logger.warning("%s: rotated while stopped; counting .1 from byte %d", log_file, offset)
        else:
            STATE["count_from"][log_file] = 0
            logger.warning("%s: checkpoint does not match current or .1; uncounted lines may be lost", log_file)
    logger.info("checkpoint restored: %d counter series, %d files", n, len(cp.files))
    return prev_count_from


# --- 停止の扱い -----------------------------------------------------------
# 処理の途中で止まると、カウンタは進んだがチェックポイントは古いままになり、
# 次の起動で値が下がって Prometheus にリセットと見なされる。処理の切れ目まで待って止まる。
_IN_PASS = False
_STOP = False


def _on_sigterm(signum, frame):
    global _STOP
    _STOP = True
    if not _IN_PASS:
        raise SystemExit(0)


def run_pass(bootstrap: bool) -> None:
    for log_file, kind, protocol in LOG_FILES:
        process_log(log_file, kind, protocol)
    _flush_access_gauges()
    _flush_wow_gauges()
    if bootstrap and INSIGHTS is not None:
        # 初見の記録ファイルが無かった初回だけ。読み終えた分を既知として扱う
        INSIGHTS.store.mark_all_as_baseline()
        logger.info("first-seen store bootstrapped with %d known paths", len(INSIGHTS.store))
    _flush_insights(time.time())
    save_checkpoint()
    metrics.last_sync_timestamp.set(time.time())


def main():
    global INSIGHTS, CHECKPOINT, _IN_PASS
    geoip.init(GEOIP_DB)
    geoip.init_asn(GEOIP_ASN_DB)
    signal.signal(signal.SIGTERM, _on_sigterm)

    store = FirstSeenStore(os.path.join(STATE_DIR, "first_seen.json"), FIRST_SEEN_RETENTION_DAYS)
    bootstrap = not store.load()
    logger.info("first-seen store: %d paths (%s)", len(store), "bootstrap" if bootstrap else "loaded")
    retention = max(h for _, h in RECENT_WINDOWS)
    INSIGHTS = Insights(store, window_hours=retention, new_path_hours=NEW_PATH_WINDOW_HOURS, retention_hours=retention)

    # ログは毎回頭から読み直す（上位の一覧・窓の集計を作り直すため）。カウンタだけは
    # チェックポイントから戻し、記録した位置より後の行だけを足す。チェックポイントが無い
    # 初回だけは従来どおり全部を数える（この 1 回だけ increase() が跳ねる）。
    CHECKPOINT = ckpt.Checkpoint(os.path.join(STATE_DIR, "checkpoint.json"))
    prev_count_from: Dict[str, Optional[int]] = {}
    if CHECKPOINT.load():
        prev_count_from = restore_from_checkpoint(CHECKPOINT)
    else:
        logger.info("no checkpoint: counting all lines (one-time jump in increase())")

    # 前の世代と最初の 1 周はサーバーを立てる前に済ませる。途中の値を Prometheus に見せないため
    _IN_PASS = True
    try:
        for log_file, kind, _ in LOG_FILES:
            seed_from_previous_generation(log_file, kind, prev_count_from.get(log_file))
        run_pass(bootstrap)
    except Exception:
        # 落ちて再起動を繰り返すより、サーバーを立てて次の周期に賭ける（従来と同じ扱い）
        logger.exception("Processing error in the first pass")
    _IN_PASS = False
    if _STOP:
        return

    start_http_server(PORT)
    logger.info("Exporter started on :%d", PORT)

    while True:
        time.sleep(SCRAPE_INTERVAL)
        _IN_PASS = True
        try:
            run_pass(False)
        except Exception:
            logger.exception("Processing error")
        _IN_PASS = False
        if _STOP:
            return


if __name__ == "__main__":
    main()
