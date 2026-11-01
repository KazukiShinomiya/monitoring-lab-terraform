import json

from exporter.insights import HOUR, FirstSeenStore, HourlyCounts, Insights, normalize_path

T0 = 1_793_484_000  # 2026-10-31T22:00:00Z（箱の境目）


def test_hourly_window_and_prune():
    h = HourlyCounts(retention_hours=48)
    h.add(T0 - 30 * HOUR, "old")
    h.add(T0 - 23 * HOUR, "a")
    h.add(T0 + 10, "a")
    h.add(T0 + 2 * HOUR, "future")  # now より先の箱は窓に入れない
    w = h.window(T0 + 100, 24)
    assert w == {"a": 2}
    assert h.window(T0 + 100, 48)["old"] == 1
    h.prune(T0 + 100 + 20 * HOUR)  # 48 時間より古い箱を捨てる
    assert "old" not in h.window(T0 + 20 * HOUR, 48)


def test_first_seen_is_idempotent_on_reread():
    s = FirstSeenStore(None, retention_days=180)
    for _ in range(3):  # 同じ行を何度読み直しても変わらない
        s.observe("/x", T0 + 50)
        s.observe("/x", T0 + 10)
    assert s.first_seen("/x") == T0 + 10


def test_store_roundtrip_and_atomic_save(tmp_path):
    p = tmp_path / "state" / "first_seen.json"
    s = FirstSeenStore(str(p), retention_days=180)
    assert s.load() is False  # 初回
    s.observe("/a", T0)
    s.save()
    data = json.loads(p.read_text())
    assert data["version"] == 1 and data["paths"]["/a"] == [T0, T0]
    assert [f.name for f in p.parent.iterdir()] == ["first_seen.json"]  # 一時ファイルが残らない

    s2 = FirstSeenStore(str(p), retention_days=180)
    assert s2.load() is True
    assert s2.first_seen("/a") == T0


def test_store_corrupt_file_starts_empty(tmp_path):
    p = tmp_path / "first_seen.json"
    p.write_text("{broken")
    s = FirstSeenStore(str(p), retention_days=180)
    assert s.load() is False
    assert len(s) == 0


def test_store_prunes_long_unseen(tmp_path):
    s = FirstSeenStore(None, retention_days=1)
    s.observe("/gone", T0)
    s.observe("/kept", T0 + 2 * 86400)
    s.prune(T0 + 2 * 86400 + 1)
    assert s.first_seen("/gone") is None
    assert s.first_seen("/kept") is not None


def test_baseline_hides_known_paths_from_new():
    store = FirstSeenStore(None, retention_days=180)
    ins = Insights(store, window_hours=24, new_path_hours=168)
    ins.observe(T0, "/old", "other", "192.0.2.1", None, None, None)
    store.mark_all_as_baseline()
    ins.observe(T0 + HOUR, "/old", "other", "192.0.2.1", None, None, None)
    ins.observe(T0 + HOUR, "/brand-new?q=1", "other", "192.0.2.2", None, None, None)
    ins.observe(T0 + HOUR, "/BRAND-NEW", "other", "192.0.2.3", None, None, None)
    rows = ins.new_paths(T0 + HOUR + 1, top_n=10)
    assert [(k, n) for k, _, n in rows] == [("/brand-new", 2)]
    assert ins.new_path_count(T0 + HOUR + 1, 24) == 1


def test_new_paths_drop_out_after_window():
    store = FirstSeenStore(None, retention_days=180)
    ins = Insights(store, window_hours=24, new_path_hours=24)
    ins.observe(T0, "/x", "other", "192.0.2.1", None, None, None)
    assert len(ins.new_paths(T0 + 1, 10)) == 1
    assert ins.new_paths(T0 + 25 * HOUR, 10) == []


def test_normalize_path():
    assert normalize_path("/A/B?c=1") == "/a/b"
    assert len(normalize_path("/" + "x" * 500)) == 128
