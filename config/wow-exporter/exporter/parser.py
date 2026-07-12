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


# 攻撃パスのカテゴリ分類。生パスは高カーディナリティ（実測~3万系列）のため
# Counter のラベルには使わず、有限個のバケットに落とす。生パスの詳細は
# top_paths_gauge (TOP_N) が引き続き担う。先に書いたものが優先される。
# 分類の根拠: 2026-07 時点の wowhoneypot_top_path_requests 実測 TOP40。
_PATH_CATEGORIES = [
    ("wp-", "wordpress"),          # /wp-login.php 等（.php より先に判定）
    ("wordpress", "wordpress"),
    ("xmlrpc", "wordpress"),
    (".env", "secrets-probe"),
    (".git", "secrets-probe"),
    ("config/getuser", "secrets-probe"),
    ("credential", "secrets-probe"),
    ("/aws", "secrets-probe"),
    ("cgi-bin", "cgi"),
    (".cgi", "cgi"),
    ("/luci", "cgi"),
    ("boaform", "iot-device"),
    ("gponform", "iot-device"),
    ("hnap1", "iot-device"),
    ("sdk/weblanguage", "iot-device"),
    ("manager/html", "admin-panel"),  # Tomcat Manager
    ("/admin", "admin-panel"),
    ("/login", "admin-panel"),
    ("/console", "admin-panel"),
    ("jenkins", "admin-panel"),
    ("autodiscover", "exchange"),
    ("/owa", "exchange"),
    ("/ews", "exchange"),
    (".php", "php"),
    ("xdebug", "php"),
    ("_ignition", "php"),          # Laravel RCE probe
    ("favicon.ico", "well-known"),
    ("robots.txt", "well-known"),
    (".well-known", "well-known"),
    ("sitemap", "well-known"),
    ("/api/", "api"),
    ("graphql", "api"),
    ("/v1/", "api"),
    ("/v2/", "api"),
]


def categorize_path(path: str) -> str:
    if path == "/" or path == "":
        return "root"
    path_lower = path.lower()
    if "../" in path_lower or "%2e" in path_lower or "/etc/passwd" in path_lower:
        return "traversal"
    for keyword, category in _PATH_CATEGORIES:
        if keyword in path_lower:
            return category
    return "other"


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
    path_bucket: str = field(default="other")


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
            path_bucket=categorize_path(m.group(5)),
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
