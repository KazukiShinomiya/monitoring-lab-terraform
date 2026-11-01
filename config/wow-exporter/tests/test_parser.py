import pytest

from exporter.parser import categorize_path, parse_access_line


@pytest.mark.parametrize(
    "path,expected",
    [
        # 既存の分類（ダッシュボードが依存しているので変えない）
        ("/", "root"),
        ("/wp-login.php", "wordpress"),
        ("/xmlrpc.php", "wordpress"),
        ("/.env", "secrets-probe"),
        ("/config/.env", "secrets-probe"),
        ("/.git/config", "secrets-probe"),
        ("/.aws/credentials", "secrets-probe"),
        ("/cgi-bin/luci", "cgi"),
        ("/cgi-bin/.%2e/.%2e/bin/sh", "traversal"),
        ("/boaform/admin/formLogin", "iot-device"),
        ("/manager/html", "admin-panel"),
        ("/login", "admin-panel"),
        ("/autodiscover/autodiscover.xml", "exchange"),
        ("/phpinfo.php", "php"),
        ("/favicon.ico", "well-known"),
        ("/api/v1/users", "api"),
        # 2026-11 に足した分類
        ("/mcp", "ai-agent"),
        ("/mcp/", "ai-agent"),
        ("/sse", "ai-agent"),
        ("/sse?x=1", "ai-agent"),
        ("/.aws/config", "secrets-probe"),
        ("/config.json", "config-leak"),
        ("/config/config.js", "config-leak"),
        ("/docker-compose.prod.yml", "config-leak"),
        ("/.svn/entries", "config-leak"),
        ("/terraform.tfstate", "config-leak"),
        ("/actuator/env", "config-leak"),
        ("/developmentserver/metadatauploader", "app-exploit"),
        ("/_profiler/phpinfo", "app-exploit"),
        ("/+cscoe+/logon.html", "vpn-appliance"),
        ("/sra_{ba195980-cd49-458b-9e23-c84ee0adcd75}/", "vpn-appliance"),
        ("/site.zip", "backup"),
        ("/db.sql", "backup"),
        ("/blog/", "cms"),
        ("/wp/", "cms"),
        ("/phpinfo", "php"),
        ("/phpmyadmin/", "admin-panel"),
        ("/signin", "admin-panel"),
        ("/swagger.json", "api"),
        ("/cdn-cgi/trace", "well-known"),
        ("/index.html", "root"),
        ("www.google.com:443", "proxy"),
        ("http://example.com/", "proxy"),
        ("/aaa9", "other"),
    ],
)
def test_categorize_path(path, expected):
    assert categorize_path(path) == expected


@pytest.mark.parametrize(
    "path",
    # 部分一致だと誤って拾いかねないもの
    ["/assets/app.css", "/mcpanel", "/ssework", "/blog/post-1", "/website"],
)
def test_exact_rules_do_not_overmatch(path):
    assert categorize_path(path) not in ("ai-agent", "cms")


def test_parse_access_line_sets_bucket_and_ua():
    import base64

    raw = base64.b64encode(b"GET /mcp HTTP/1.1\r\nUser-Agent: zgrab/0.x\r\n\r\n").decode()
    line = f'[2026-11-01 07:00:00+0900] 192.0.2.1 example:80 "GET /mcp HTTP/1.1" 404 False {raw}'
    e = parse_access_line(line)
    assert e is not None
    assert e.path_bucket == "ai-agent"
    assert e.ua_category == "zgrab"
    assert e.timestamp.timestamp() == 1793484000  # 2026-10-31T22:00:00Z
