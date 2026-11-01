"""main の結合テスト。ログファイルを書いて処理させ、公開されるメトリクスを読む。"""

import base64
from datetime import datetime, timedelta, timezone

import pytest
from prometheus_client import REGISTRY

from exporter import main, metrics
from exporter.insights import FirstSeenStore, Insights

JST = timezone(timedelta(hours=9))


def _line(ts: datetime, ip: str, path: str, ua: str = "zgrab/0.x") -> str:
    raw = base64.b64encode(f"GET {path} HTTP/1.1\r\nUser-Agent: {ua}\r\n\r\n".encode()).decode()
    stamp = ts.astimezone(JST).strftime("%Y-%m-%d %H:%M:%S%z")
    return f'[{stamp}] {ip} example:80 "GET {path} HTTP/1.1" 404 False {raw}\n'


def _v(name, **labels):
    return REGISTRY.get_sample_value(name, labels)


@pytest.fixture
def env(tmp_path, monkeypatch):
    for g in (
        metrics.top_paths_gauge,
        metrics.recent_top_paths,
        metrics.recent_requests_by_bucket,
        metrics.new_path_requests,
        metrics.new_path_first_seen,
    ):
        g.clear()
    logs = tmp_path / "logs"
    logs.mkdir()
    monkeypatch.setattr(main, "LOG_DIR", str(logs))
    monkeypatch.setattr(main, "TOP_N", 2)
    monkeypatch.setattr(main, "STATE", {k: type(v)() for k, v in main.STATE.items()})
    for k in ("access_offset", "access_https_offset", "wow_offset", "wow_https_offset"):
        main.STATE[k] = 0
    store = FirstSeenStore(str(tmp_path / "state" / "first_seen.json"), 180)
    monkeypatch.setattr(main, "INSIGHTS", Insights(store, window_hours=24, new_path_hours=168))
    return logs


def test_recent_window_excludes_old_lines_and_seeds_previous_generation(env):
    now = datetime.now(timezone.utc)
    # 前の世代: 2 時間前（窓に入る）と 3 日前（窓に入らない）
    (env / "access_log.1").write_text(
        _line(now - timedelta(hours=2), "192.0.2.1", "/mcp") + _line(now - timedelta(days=3), "192.0.2.9", "/.env")
    )
    (env / "access_log").write_text(_line(now - timedelta(minutes=5), "192.0.2.2", "/mcp"))

    main.seed_from_previous_generation("access_log")
    main.process_access_log("access_log", "http")
    main._flush_insights(now.timestamp())

    assert _v("wowhoneypot_recent_requests_by_bucket", path_bucket="ai-agent") == 2
    assert _v("wowhoneypot_recent_requests_by_bucket", path_bucket="secrets-probe") is None
    assert _v("wowhoneypot_recent_unique_src_ips") == 2
    # 累計のほうには前の世代を足さない
    assert _v("wowhoneypot_top_path_requests", path="/mcp") == 1
    assert (env.parent / "state" / "first_seen.json").exists()


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
