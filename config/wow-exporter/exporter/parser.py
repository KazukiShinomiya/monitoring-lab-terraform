import base64
import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

VALID_METHOD = re.compile(r'^[A-Za-z]{1,20}$')

ACCESS_PATTERN = re.compile(
    r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\+\d{4})\] '
    r'(\S+) '
    r'(\S+:\d+) '
    r'"(\S+) (\S+) (\S+)" '
    r'(\d+) '
    r'(False|\d+) '
    r'(\S+)$'
)

WOW_PATTERN = re.compile(
    r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\+\d{4})\]'
    r'\[(\w+)\](.+)$'
)

BLOCKLIST_IP_PATTERN = re.compile(r'blocklist ip\((\S+)\)')
TIMEOUT_IP_PATTERN = re.compile(r'Client\((\S+)\)')

# 既知スキャナー/ツールのキーワードとカテゴリ名。先に書いたものが優先される。
_UA_CATEGORIES = [
    ("masscan", "masscan"),
    ("zgrab", "zgrab"),
    ("shodan", "shodan"),
    ("censys", "censys"),
    ("nuclei", "nuclei"),
    ("nmap", "nmap"),
    ("python-requests", "python-requests"),
    ("python-urllib", "python-urllib"),
    ("go-http-client", "go-http-client"),
    ("libwww-perl", "libwww-perl"),
    ("curl", "curl"),
    ("wget", "wget"),
    ("axios", "axios"),
    ("java/", "java"),
    ("winhttp", "winhttp"),
    ("okhttp", "okhttp"),
]


def categorize_ua(ua: Optional[str]) -> str:
    if not ua:
        return "unknown"
    ua_lower = ua.lower()
    for keyword, category in _UA_CATEGORIES:
        if keyword in ua_lower:
            return category
    if "mozilla/5.0" in ua_lower:
        return "browser-like"  # ブラウザ偽装
    return "other"


def _extract_user_agent(b64: str) -> Optional[str]:
    try:
        padding = 4 - len(b64) % 4
        decoded = base64.b64decode(b64 + "=" * (padding % 4)).decode("utf-8", errors="replace")
        for line in decoded.splitlines():
            if line.lower().startswith("user-agent:"):
                return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return None


@dataclass
class AccessEntry:
    timestamp: datetime
    src_ip: str
    dst: str
    method: str
    path: str
    protocol: str
    status: int
    matched: bool
    user_agent: Optional[str] = field(default=None)
    ua_category: str = field(default="unknown")


@dataclass
class WowEntry:
    timestamp: datetime
    level: str
    message: str
    event_type: str
    ip: Optional[str]


def parse_access_line(line: str) -> Optional[AccessEntry]:
    m = ACCESS_PATTERN.match(line.strip())
    if not m:
        return None
    try:
        ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S%z")
        method = m.group(4) if VALID_METHOD.match(m.group(4)) else "UNKNOWN"
        ua = _extract_user_agent(m.group(9))
        return AccessEntry(
            timestamp=ts,
            src_ip=m.group(2),
            dst=m.group(3),
            method=method,
            path=m.group(5),
            protocol=m.group(6),
            status=int(m.group(7)),
            matched=m.group(8) != "False",
            user_agent=ua,
            ua_category=categorize_ua(ua),
        )
    except (ValueError, IndexError):
        return None


def parse_wow_line(line: str) -> Optional[WowEntry]:
    m = WOW_PATTERN.match(line.strip())
    if not m:
        return None
    try:
        ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S%z")
        level = m.group(2)
        message = m.group(3)

        if "blocklist" in message:
            event_type = "blocklist"
            ip_m = BLOCKLIST_IP_PATTERN.search(message)
            ip = ip_m.group(1) if ip_m else None
        elif "timed out" in message:
            event_type = "timeout"
            ip_m = TIMEOUT_IP_PATTERN.search(message)
            ip = ip_m.group(1) if ip_m else None
        else:
            event_type = "other"
            ip = None

        return WowEntry(timestamp=ts, level=level, message=message, event_type=event_type, ip=ip)
    except (ValueError, IndexError):
        return None
