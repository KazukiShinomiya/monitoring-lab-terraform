"""main の結合テスト。ログファイルを書いて処理させ、公開されるメトリクスを読む。"""

import base64
import os
from datetime import datetime, timedelta, timezone

import pytest
from prometheus_client import REGISTRY

from exporter import checkpoint as ckpt
from exporter import main, metrics
from exporter.insights import FirstSeenStore, Insights

JST = timezone(timedelta(hours=9))


def _line(ts: datetime, ip: str, path: str, ua: str = "zgrab/0.x") -> str:
    raw = base64.b64encode(f"GET {path} HTTP/1.1\r\nUser-Agent: {ua}\r\n\r\n".encode()).decode()
    stamp = ts.astimezone(JST).strftime("%Y-%m-%d %H:%M:%S%z")
    return f'[{stamp}] {ip} example:80 "GET {path} HTTP/1.1" 404 False {raw}\n'


def _lines(n: int, path: str = "/mcp", start: int = 0) -> str:
    now = datetime.now(timezone.utc)
    return "".join(_line(now - timedelta(minutes=10), f"192.0.2.{start + i + 1}", path) for i in range(n))


def _v(name, **labels):
    return REGISTRY.get_sample_value(name, labels)


def _total():
    """http_requests_total の全系列の合計。"""
    return sum(
        s.value
        for fam in metrics.http_requests_total.collect()
        for s in fam.samples
        if s.name.endswith("_total")
    )


def _reset_process(tmp_path, monkeypatch):
    """プロセスの再起動を真似る: カウンタ・ゲージ・STATE を空にし、INSIGHTS を作り直す。"""
    for c in main.PERSISTED_COUNTERS:
        if c._labelnames:
            c.clear()
        else:
            c._value.set(0)
    for g in (
        metrics.top_paths_gauge,
        metrics.recent_top_paths,
        metrics.recent_requests_by_bucket,
        metrics.recent_unique_src_ips,
        metrics.new_path_requests,
        metrics.new_path_first_seen,
    ):
        g.clear()
    monkeypatch.setattr(main, "STATE", main._new_state())
    store = FirstSeenStore(str(tmp_path / "state" / "first_seen.json"), 180)
    store.load()
    monkeypatch.setattr(main, "INSIGHTS", Insights(store, window_hours=168, new_path_hours=168))
    cp = ckpt.Checkpoint(str(tmp_path / "state" / "checkpoint.json"))
    monkeypatch.setattr(main, "CHECKPOINT", cp)
    return cp


def _start(cp):
    """main() の起動手順（サーバーを立てる前まで）。"""
    prev = main.restore_from_checkpoint(cp) if cp.load() else {}
    for log_file, kind, _ in main.LOG_FILES:
        main.seed_from_previous_generation(log_file, kind, prev.get(log_file))
    main.run_pass(False)


@pytest.fixture
def env(tmp_path, monkeypatch):
    logs = tmp_path / "logs"
    logs.mkdir()
    monkeypatch.setattr(main, "LOG_DIR", str(logs))
    monkeypatch.setattr(main, "TOP_N", 2)
    _reset_process(tmp_path, monkeypatch)
    return logs


def test_parse_windows():
    assert main.parse_windows("1h, 24h,7d") == [("1h", 1), ("24h", 24), ("7d", 168)]
    for bad in ("", "24", "0h", "3w"):
        with pytest.raises(ValueError):
            main.parse_windows(bad)


def test_recent_windows_and_seed_previous_generation(env, monkeypatch):
    monkeypatch.setattr(main, "RECENT_WINDOWS", [("1h", 1), ("24h", 24)])
    now = datetime.now(timezone.utc)
    # 前の世代: 2 時間前（24h に入り 1h に入らない）と 3 日前（どちらにも入らない）
    (env / "access_log.1").write_text(
        _line(now - timedelta(hours=2), "192.0.2.1", "/mcp") + _line(now - timedelta(days=3), "192.0.2.9", "/.env")
    )
    (env / "access_log").write_text(_line(now - timedelta(minutes=5), "192.0.2.2", "/mcp"))

    main.seed_from_previous_generation("access_log")
    main.process_access_log("access_log", "http")
    main._flush_insights(now.timestamp())

    assert _v("wowhoneypot_recent_requests_by_bucket", path_bucket="ai-agent", window="24h") == 2
    assert _v("wowhoneypot_recent_requests_by_bucket", path_bucket="ai-agent", window="1h") == 1
    assert _v("wowhoneypot_recent_requests_by_bucket", path_bucket="secrets-probe", window="24h") is None
    assert _v("wowhoneypot_recent_unique_src_ips", window="24h") == 2
    assert _v("wowhoneypot_recent_unique_src_ips", window="1h") == 1
    # 累計（STATE 由来のゲージ・カウンタ）には前の世代を足さない
    assert _v("wowhoneypot_top_path_requests", path="/mcp") == 1
    assert _total() == 1


def test_top_gauges_drop_series_that_fall_out(env):
    now = datetime.now(timezone.utc)
    log = env / "access_log"
    log.write_text("".join(_line(now, "192.0.2.1", p) for p in ["/a", "/b", "/b"]))
    main.process_access_log("access_log", "http")
    assert _v("wowhoneypot_top_path_requests", path="/a") == 1

    with log.open("a") as f:
        f.write("".join(_line(now, "192.0.2.1", "/c") for _ in range(3)))
    main.process_access_log("access_log", "http")
    # TOP_N=2 なので /a は消える（以前は古い値のまま残り、系列が増え続けた）
    assert _v("wowhoneypot_top_path_requests", path="/a") is None
    assert _v("wowhoneypot_top_path_requests", path="/c") == 3


def test_new_paths_after_bootstrap(env):
    now = datetime.now(timezone.utc)
    (env / "access_log").write_text(_line(now - timedelta(hours=3), "192.0.2.1", "/known"))
    main.process_access_log("access_log", "http")
    main.INSIGHTS.store.mark_all_as_baseline()

    with (env / "access_log").open("a") as f:
        f.write(_line(now - timedelta(minutes=1), "192.0.2.5", "/sse"))
        f.write(_line(now - timedelta(minutes=1), "192.0.2.5", "/known"))
    main.process_access_log("access_log", "http")
    main._flush_insights(now.timestamp())

    assert _v("wowhoneypot_new_path_requests", path="/sse", path_bucket="ai-agent") == 1
    assert _v("wowhoneypot_new_path_requests", path="/known", path_bucket="other") is None
    assert _v("wowhoneypot_new_paths_24h") == 1
    first = _v("wowhoneypot_new_path_first_seen_timestamp", path="/sse", path_bucket="ai-agent")
    assert abs(first - (now - timedelta(minutes=1)).timestamp()) < 1.5


# --- チェックポイント（再起動をまたいでカウンタを続ける） --------------------

def test_no_checkpoint_counts_all_lines(env, tmp_path):
    (env / "access_log").write_text(_lines(3))
    _start(main.CHECKPOINT)
    assert _total() == 3
    assert (tmp_path / "state" / "checkpoint.json").exists()


def test_counter_continues_across_restart(env, tmp_path, monkeypatch):
    log = env / "access_log"
    log.write_text(_lines(3))
    _start(main.CHECKPOINT)
    assert _total() == 3

    cp = _reset_process(tmp_path, monkeypatch)
    with log.open("a") as f:
        f.write(_lines(2, start=10))
    _start(cp)
    # 読み直した 3 行は数えず、新しい 2 行だけを足す（以前は 0 から 5 に戻り、increase() が跳ねた）
    assert _total() == 5
    # 上位の一覧などは読み直しで作り直されている
    assert _v("wowhoneypot_top_path_requests", path="/mcp") == 5


def test_rotation_while_stopped_counts_tail_of_previous(env, tmp_path, monkeypatch):
    log = env / "access_log"
    log.write_text(_lines(3))
    _start(main.CHECKPOINT)

    cp = _reset_process(tmp_path, monkeypatch)
    # 止まっている間に 2 行増え、ローテーションして新しい世代に 1 行
    with log.open("a") as f:
        f.write(_lines(2, start=10))
    os.replace(log, env / "access_log.1")
    log.write_text(_lines(1, start=20))
    _start(cp)
    assert _total() == 3 + 2 + 1


def test_rotation_while_running_reads_tail_from_previous(env):
    log = env / "access_log"
    log.write_text(_lines(3))
    main.run_pass(False)
    # 次の周期までの間に 2 行増え、その後ローテーション（sync-logs.sh は継ぎ足してから .1 へ）
    with log.open("a") as f:
        f.write(_lines(2, start=10))
    os.replace(log, env / "access_log.1")
    log.write_text(_lines(1, start=20))
    main.run_pass(False)
    # 以前は .1 の末尾 2 行を取りこぼしていた
    assert _total() == 6
    assert _v("wowhoneypot_top_path_requests", path="/mcp") == 6


def test_replaced_file_detected_by_head_even_if_larger(env):
    log = env / "access_log"
    log.write_text(_lines(1))
    main.run_pass(False)
    # 大きさは増えたが中身が別物（.1 も無い）。大きさだけ見ると途中から読んでしまう
    log.write_text(_lines(4, path="/other", start=30))
    main.run_pass(False)
    assert _total() == 1 + 4


def test_checkpoint_restores_unlabeled_and_wow_counters(env, tmp_path, monkeypatch):
    (env / "wowhoneypot.log").write_text(
        "[2026-11-01 07:00:00+0900][INFO]blocklist ip(192.0.2.1) denied\n"
        "[2026-11-01 07:00:01+0900][INFO]Client(192.0.2.2) timed out\n"
    )
    _start(main.CHECKPOINT)
    assert _v("wowhoneypot_blocklist_denials_total") == 1

    cp = _reset_process(tmp_path, monkeypatch)
    assert _v("wowhoneypot_blocklist_denials_total") == 0
    _start(cp)
    assert _v("wowhoneypot_blocklist_denials_total") == 1
    assert _v("wowhoneypot_timeout_errors_total") == 1
    # 読み直しで、ブロックした IP の上位も作り直される
    assert _v("wowhoneypot_top_blocklisted_ips", src_ip="192.0.2.1") == 1


def test_corrupt_checkpoint_falls_back_to_counting_all(env, tmp_path):
    (tmp_path / "state").mkdir(exist_ok=True)
    (tmp_path / "state" / "checkpoint.json").write_text("{broken")
    (env / "access_log").write_text(_lines(2))
    _start(main.CHECKPOINT)
    assert _total() == 2
