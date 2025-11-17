#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import requests
import time
import hmac
import hashlib
import base64
import json
import sys
import os
import uuid
import argparse

# ===== 設定 =====
# 環境変数から設定を取得(なければデフォルト値)
TOKEN = os.getenv("SWITCHBOT_TOKEN", "YOUR_SWITCHBOT_TOKEN")
SECRET = os.getenv("SWITCHBOT_SECRET", "YOUR_SWITCHBOT_SECRET")
BASE_URL = "https://api.switch-bot.com/v1.1/devices"

# タイムアウトは後でコマンドライン引数で上書きされる可能性があるため、関数内で取得
def get_timeout():
    """タイムアウト値を取得(環境変数またはデフォルト値)"""
    return int(os.getenv("SWITCHBOT_TIMEOUT", "10"))

# ===== エラーコード定数 =====
EXIT_CODE_OK = 0
EXIT_CODE_ERROR = 1
EXIT_CODE_CONFIG_ERROR = 2
EXIT_CODE_API_ERROR = 3

# ===== 認証ヘッダ生成 =====
def generate_headers():
    """SwitchBot API用の認証ヘッダを生成"""
    t = int(round(time.time() * 1000))
    nonce = str(uuid.uuid4())
    string_to_sign = f"{TOKEN}{t}{nonce}"
    sign = base64.b64encode(
        hmac.new(SECRET.encode('utf-8'), msg=string_to_sign.encode('utf-8'), digestmod=hashlib.sha256).digest()
    ).decode('utf-8')
    return {
        "Authorization": TOKEN,
        "sign": sign,
        "t": str(t),
        "nonce": nonce,
        "Content-Type": "application/json; charset=utf8"
    }

# ===== メインロジック =====
def get_device_status(device_id: str, timeout: int = None, debug: bool = False):
    """デバイスのステータスを取得し、Zabbix向けにJSON出力

    Args:
        device_id: SwitchBot デバイスID
        timeout: リクエストタイムアウト(秒、Noneの場合は環境変数またはデフォルト値)
        debug: デバッグモード(詳細ログ出力)
    """
    # タイムアウト値の決定
    if timeout is None:
        timeout = get_timeout()

    url = f"{BASE_URL}/{device_id}/status"

    if debug:
        print(f"Debug: Using device_id={device_id}, timeout={timeout}, TOKEN configured={TOKEN != 'YOUR_SWITCHBOT_TOKEN'}, SECRET configured={SECRET != 'YOUR_SWITCHBOT_SECRET'}", file=sys.stderr)
        print(f"Debug: API URL={url}", file=sys.stderr)

    # トークンとシークレットの検証
    if TOKEN == "YOUR_SWITCHBOT_TOKEN" or SECRET == "YOUR_SWITCHBOT_SECRET":
        error_msg = {
            "error": "Missing SwitchBot credentials",
            "message": "Please set SWITCHBOT_TOKEN and SWITCHBOT_SECRET environment variables",
            "exit_code": EXIT_CODE_CONFIG_ERROR,
            "timestamp": int(time.time())
        }
        print(json.dumps(error_msg, ensure_ascii=False))
        print("Error: Missing SwitchBot credentials. Please set SWITCHBOT_TOKEN and SWITCHBOT_SECRET.", file=sys.stderr)
        sys.exit(EXIT_CODE_CONFIG_ERROR)

    try:
        response = requests.get(url, headers=generate_headers(), timeout=timeout)
        response.raise_for_status()
        data = response.json()

        # API レスポンスの確認
        status_code = data.get("statusCode")
        if status_code != 100:
            error_msg = {
                "error": f"API returned status code {status_code}",
                "message": data.get('message', 'Unknown error'),
                "exit_code": EXIT_CODE_API_ERROR,
                "timestamp": int(time.time())
            }
            print(json.dumps(error_msg, ensure_ascii=False))
            print(f"Error: API returned status code {status_code}: {data.get('message', 'Unknown error')}", file=sys.stderr)
            sys.exit(EXIT_CODE_API_ERROR)

        body = data.get("body", {})

        # 必須データの存在確認（温度と湿度のみ必須）
        if not all(key in body for key in ["temperature", "humidity"]):
            error_msg = {
                "error": "Missing required data fields",
                "message": "API response missing temperature or humidity field",
                "exit_code": EXIT_CODE_API_ERROR,
                "timestamp": int(time.time())
            }
            print(json.dumps(error_msg, ensure_ascii=False))
            print("Error: Missing required data fields in API response", file=sys.stderr)
            sys.exit(EXIT_CODE_API_ERROR)

        # 基本データ
        result = {
            "device_id": device_id,
            "device_type": body.get("deviceType", "Unknown"),
            "temperature": body.get("temperature"),
            "humidity": body.get("humidity"),
            "timestamp": int(time.time()),
            "exit_code": EXIT_CODE_OK
        }

        # オプショナルデータ（存在する場合のみ追加）
        if "battery" in body:
            result["battery"] = body.get("battery")
        if "lightLevel" in body:
            result["lightLevel"] = body.get("lightLevel")
        if "moveDetected" in body:
            result["moveDetected"] = body.get("moveDetected")

        if debug:
            print("Debug: Raw API response body:", file=sys.stderr)
            print(json.dumps(body, indent=2, ensure_ascii=False), file=sys.stderr)

        # Zabbix向けにJSON出力(改行なし、デバッグ時は整形)
        if debug:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(json.dumps(result, ensure_ascii=False))

        # 正常終了(明示的にexit codeを返す)
        sys.exit(EXIT_CODE_OK)

    except requests.exceptions.Timeout:
        error_msg = {
            "error": "Request timeout",
            "message": f"Request timeout after {timeout} seconds",
            "exit_code": EXIT_CODE_ERROR,
            "timestamp": int(time.time())
        }
        print(json.dumps(error_msg, ensure_ascii=False))
        print(f"Error: Request timeout after {timeout} seconds", file=sys.stderr)
        sys.exit(EXIT_CODE_ERROR)
    except requests.exceptions.RequestException as e:
        error_msg = {
            "error": "Network error",
            "message": str(e),
            "exit_code": EXIT_CODE_ERROR,
            "timestamp": int(time.time())
        }
        print(json.dumps(error_msg, ensure_ascii=False))
        print(f"Error: Network error: {e}", file=sys.stderr)
        sys.exit(EXIT_CODE_ERROR)
    except json.JSONDecodeError as e:
        error_msg = {
            "error": "Invalid JSON response",
            "message": str(e),
            "exit_code": EXIT_CODE_ERROR,
            "timestamp": int(time.time())
        }
        print(json.dumps(error_msg, ensure_ascii=False))
        print(f"Error: Invalid JSON response: {e}", file=sys.stderr)
        sys.exit(EXIT_CODE_ERROR)
    except Exception as e:
        error_msg = {
            "error": "Unexpected error",
            "message": str(e),
            "exit_code": EXIT_CODE_ERROR,
            "timestamp": int(time.time())
        }
        print(json.dumps(error_msg, ensure_ascii=False))
        print(f"Error: Unexpected error: {e}", file=sys.stderr)
        sys.exit(EXIT_CODE_ERROR)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="SwitchBot温湿度計からデータを取得してZabbix用にJSON出力",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用例:
  %(prog)s YOUR_DEVICE_ID
  %(prog)s YOUR_DEVICE_ID --debug

環境変数:
  SWITCHBOT_TOKEN    - SwitchBot API トークン
  SWITCHBOT_SECRET   - SwitchBot API シークレット
  SWITCHBOT_TIMEOUT  - リクエストタイムアウト(秒、デフォルト: 10)
        """
    )
    parser.add_argument("device_id", help="SwitchBot デバイスID")
    parser.add_argument("--debug", action="store_true", help="デバッグ情報を標準エラーに出力し、JSONを整形して表示")
    parser.add_argument("--timeout", type=int, help="タイムアウト秒数を上書き(環境変数より優先、デフォルト: 10秒)")
    args = parser.parse_args()

    # デバイスIDの基本検証
    if not args.device_id or not args.device_id.strip():
        print("Error: Device ID cannot be empty", file=sys.stderr)
        sys.exit(EXIT_CODE_CONFIG_ERROR)

    # タイムアウト値の設定(コマンドライン引数があれば使用)
    timeout = args.timeout if args.timeout else None

    get_device_status(args.device_id, timeout=timeout, debug=args.debug)
