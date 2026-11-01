"""直近の傾向と「新顔」を出すための集計。

既存の集計（main.STATE の Counter）は起動からの累計で、しかも起動のたびにログ
全体を読み直すため「最近なにが来たか」が分からない。ここではログに書かれた時刻で
1 時間ごとの箱に数を入れ、窓（既定 24 時間）で足し合わせる。処理した時刻ではなく
ログの時刻で数えるので、再起動してログを読み直しても値は変わらない。

新顔の判定には「初めて見た時刻」が要る。ログはローテーションで消えるため、
FirstSeenStore がパスごとの初見・最終観測の時刻をファイルに残す。読み直すたびに
min / max を取り直すだけなので、同じ行を何度読んでも結果は変わらない（冪等）。
"""

import json
import logging
import os
import tempfile
import time
from collections import Counter, defaultdict
from typing import Dict, Hashable, Iterable, List, Optional, Tuple

logger = logging.getLogger(__name__)

HOUR = 3600


class HourlyCounts:
    """キーごとの件数を 1 時間の箱で持ち、窓で足し合わせる。"""

    def __init__(self, retention_hours: int):
        self.retention_hours = retention_hours
        self._buckets: Dict[int, Counter] = defaultdict(Counter)

    def add(self, ts: float, key: Hashable, n: int = 1) -> None:
        self._buckets[int(ts // HOUR)][key] += n

    def prune(self, now: float) -> None:
        oldest = int(now // HOUR) - self.retention_hours + 1
        for hour in [h for h in self._buckets if h < oldest]:
            del self._buckets[hour]

    def window(self, now: float, hours: int) -> Counter:
        """now を含む直近 hours 時間（箱単位）の合計。未来の箱は含めない。"""
        current = int(now // HOUR)
        start = current - hours + 1
        total: Counter = Counter()
        for hour, counts in self._buckets.items():
            if start <= hour <= current:
                total.update(counts)
        return total


class FirstSeenStore:
    """正規化したパスごとの [初見, 最終観測] の UNIX 時刻をファイルに残す。"""

    def __init__(self, path: Optional[str], retention_days: int):
        self.path = path
        self.retention = retention_days * 86400
        self._seen: Dict[str, List[float]] = {}
        self._dirty = False

    def load(self) -> bool:
        """読めたら True。ファイルが無い（初回）か壊れていたら False で空から始める。"""
        if not self.path or not os.path.exists(self.path):
            return False
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self._seen = {k: [float(v[0]), float(v[1])] for k, v in data["paths"].items()}
            return True
        except (OSError, ValueError, KeyError, TypeError, IndexError):
            logger.exception("first-seen store is unreadable, starting empty: %s", self.path)
            self._seen = {}
            return False

    def observe(self, key: str, ts: float) -> None:
        cur = self._seen.get(key)
        if cur is None:
            self._seen[key] = [ts, ts]
            self._dirty = True
            return
        if ts < cur[0]:
            cur[0] = ts
            self._dirty = True
        if ts > cur[1]:
            cur[1] = ts
            self._dirty = True

    def mark_all_as_baseline(self) -> None:
        """初回（ファイルが無かった）用。いま知っているキーを「記録を始める前から既知」とする。

        手元のログは高々 2 世代（約 8 日）なので、これをしないと初見の窓（7 日）に
        ほぼ全部が入り、最初の 1 週間は新顔の一覧が古馴染みで埋まる。
        初見を 0 にすると seen_since() に二度と出ない。最終観測はそのまま残す。
        """
        for v in self._seen.values():
            v[0] = 0.0
        self._dirty = True

    def first_seen(self, key: str) -> Optional[float]:
        cur = self._seen.get(key)
        return cur[0] if cur else None

    def seen_since(self, since: float) -> Iterable[Tuple[str, float]]:
        """初見が since 以降のキーと初見時刻。"""
        return ((k, v[0]) for k, v in self._seen.items() if v[0] >= since)

    def prune(self, now: float) -> None:
        """長く来ていないキーを忘れる。また来れば新顔として扱われる。"""
        cutoff = now - self.retention
        stale = [k for k, v in self._seen.items() if v[1] < cutoff]
        for k in stale:
            del self._seen[k]
        if stale:
            self._dirty = True

    def __len__(self) -> int:
        return len(self._seen)

    def save(self) -> None:
        """変わったときだけ、一時ファイルに書いてから rename する（途中で落ちても壊れない）。"""
        if not self.path or not self._dirty:
            return
        directory = os.path.dirname(self.path) or "."
        os.makedirs(directory, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".first_seen.", dir=directory)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump({"version": 1, "saved_at": time.time(), "paths": self._seen}, f)
            os.replace(tmp, self.path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        self._dirty = False


def normalize_path(path: str) -> str:
    """新顔の判定に使うキー。クエリを落とし、大小文字を区別しない。"""
    return path.split("?", 1)[0].lower()[:128]


class Insights:
    """エントリを受け取り、窓ごとの上位と新顔を計算する。"""

    def __init__(
        self,
        store: FirstSeenStore,
        window_hours: int = 24,
        new_path_hours: int = 168,
        retention_hours: int = 168,
    ):
        self.store = store
        self.window_hours = window_hours
        self.new_path_hours = new_path_hours
        # 新顔の件数は新顔の窓の分だけ遡って数えるので、そちらが長ければ合わせる
        retention = max(retention_hours, window_hours, new_path_hours)
        self.paths = HourlyCounts(retention)
        self.buckets = HourlyCounts(retention)
        self.ips = HourlyCounts(retention)
        self.user_agents = HourlyCounts(retention)
        self.countries = HourlyCounts(retention)
        self.asns = HourlyCounts(retention)
        self._path_bucket: Dict[str, str] = {}

    def observe(
        self,
        ts: float,
        path: str,
        path_bucket: str,
        src_ip: str,
        user_agent: Optional[str],
        country: Optional[Tuple[str, str]],
        asn: Optional[Tuple[str, str]],
    ) -> None:
        key = normalize_path(path)
        self._path_bucket[key] = path_bucket
        self.paths.add(ts, key)
        self.buckets.add(ts, path_bucket)
        self.ips.add(ts, src_ip)
        if user_agent:
            self.user_agents.add(ts, user_agent[:128])
        if country:
            self.countries.add(ts, country)
        if asn:
            self.asns.add(ts, asn)
        self.store.observe(key, ts)

    def path_bucket_of(self, key: str) -> str:
        return self._path_bucket.get(key, "other")

    def prune(self, now: float) -> None:
        for h in (self.paths, self.buckets, self.ips, self.user_agents, self.countries, self.asns):
            h.prune(now)
        self.store.prune(now)
        # 窓から消えたパスの分類は覚えておく必要がない
        live = set(self.paths.window(now, self.paths.retention_hours))
        for key in [k for k in self._path_bucket if k not in live]:
            del self._path_bucket[key]

    def new_paths(self, now: float, top_n: int) -> List[Tuple[str, float, int]]:
        """初見が新顔の窓に入るパスを、その窓での件数の多い順に (key, 初見, 件数)。"""
        since = now - self.new_path_hours * HOUR
        counts = self.paths.window(now, self.new_path_hours)
        rows = [(k, first, counts.get(k, 0)) for k, first in self.store.seen_since(since)]
        rows = [r for r in rows if r[2] > 0]
        rows.sort(key=lambda r: (-r[2], -r[1], r[0]))
        return rows[:top_n]

    def new_path_count(self, now: float, hours: int) -> int:
        since = now - hours * HOUR
        return sum(1 for _ in self.store.seen_since(since))
