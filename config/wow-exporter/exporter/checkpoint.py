"""再起動をまたいでカウンタを続けるためのチェックポイント。

exporter は起動のたびにログを頭から読み直す（上位の一覧などを作り直すため）。カウンタまで
数え直すと、Prometheus からはリセットに見え、`increase()` が読み直した分を丸ごと
足してしまう（グラフが跳ねる）。そこで、どこまで数えたか（ファイルごとのバイト位置と
先頭のハッシュ）とカウンタの値を一緒に残し、起動時にカウンタを前回の値へ戻す。
読み直しはこれまでどおり行うが、カウンタに足すのは記録した位置より後の行だけにする。

ファイルの同一性は先頭 HEAD_BYTES バイトのハッシュで見る。ローテーションで入れ替わると
先頭が変わるので、大きさの比較だけより確実に見分けられる。
"""

import hashlib
import json
import logging
import os
import tempfile
import time
from typing import Dict, Iterable, Optional, Tuple

logger = logging.getLogger(__name__)

HEAD_BYTES = 256
VERSION = 1


def atomic_write_json(path: str, obj) -> None:
    """一時ファイルに書いてから rename する（途中で落ちても前の内容が残る）。"""
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def head_of(path: str, length: int) -> Optional[str]:
    """先頭 length バイトのハッシュ。ファイルが無いか短ければ None。"""
    try:
        with open(path, "rb") as f:
            data = f.read(length)
    except OSError:
        return None
    if len(data) < length:
        return None
    return hashlib.sha256(data).hexdigest()[:32]


def identity(path: str, offset: int) -> Tuple[int, Optional[str]]:
    """offset まで読んだファイルの同一性 (先頭の長さ, ハッシュ)。"""
    length = min(HEAD_BYTES, offset)
    return length, (head_of(path, length) if length else None)


def same_file(path: str, head_len: int, head: Optional[str]) -> bool:
    if head_len == 0:
        return os.path.exists(path)
    return head is not None and head_of(path, head_len) == head


def snapshot_counters(counters: Iterable) -> Dict[str, list]:
    """Counter の現在値を {メトリクス名: [[ラベル, 値], ...]} にする。"""
    out: Dict[str, list] = {}
    for counter in counters:
        for family in counter.collect():
            for s in family.samples:
                if s.name.endswith("_total"):
                    out.setdefault(family.name, []).append([dict(s.labels), s.value])
    return out


def restore_counters(counters: Iterable, saved: Dict[str, list]) -> int:
    """保存した値まで Counter を進める。戻した系列の数を返す。"""
    by_name = {}
    for counter in counters:
        for family in counter.collect():
            by_name[family.name] = counter
    n = 0
    for name, rows in saved.items():
        counter = by_name.get(name)
        if counter is None:
            logger.warning("checkpoint: unknown counter %s, skipped", name)
            continue
        for labels, value in rows:
            try:
                (counter.labels(**labels) if labels else counter).inc(value)
                n += 1
            except (ValueError, TypeError):
                # ラベルの構成が変わった等。その系列だけ諦める（以後は 0 から数える）
                logger.warning("checkpoint: cannot restore %s%s", name, labels)
    return n


class Checkpoint:
    def __init__(self, path: Optional[str]):
        self.path = path
        self.files: Dict[str, dict] = {}
        self.counters: Dict[str, list] = {}
        self.loaded = False

    def load(self) -> bool:
        if not self.path or not os.path.exists(self.path):
            return False
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if data.get("version") != VERSION:
                raise ValueError("unsupported checkpoint version %r" % data.get("version"))
            self.files = {k: dict(v) for k, v in data["files"].items()}
            self.counters = data["counters"]
            self.loaded = True
            return True
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            logger.exception("checkpoint is unreadable, counting from scratch: %s", self.path)
            self.files, self.counters = {}, {}
            return False

    def save(self, files: Dict[str, dict], counters: Dict[str, list]) -> None:
        if not self.path:
            return
        atomic_write_json(
            self.path,
            {"version": VERSION, "saved_at": time.time(), "files": files, "counters": counters},
        )
