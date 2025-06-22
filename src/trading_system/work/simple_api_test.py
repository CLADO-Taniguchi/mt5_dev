#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
簡易 Flask Trading API 接続テストスクリプト
"""

import requests
import socket
import time
from datetime import datetime

def test_port_5000():
    """ポート5000の接続テスト"""
    print("=== ポート5000接続テスト ===")
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(3)
        result = sock.connect_ex(('localhost', 5000))
        sock.close()
        
        if result == 0:
            print("OK: ポート5000は開いています")
            return True
        else:
            print("NG: ポート5000は閉じています")
            return False
    except Exception as e:
        print(f"NG: ポート確認エラー: {e}")
        return False

def test_health_endpoint():
    """ヘルスチェックエンドポイントテスト"""
    print("\n=== ヘルスチェックテスト ===")
    try:
        response = requests.get("http://localhost:5000/health", timeout=5)
        print(f"レスポンスコード: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("OK: APIサーバーは正常に動作しています")
            print(f"  ステータス: {data.get('status')}")
            print(f"  タイムスタンプ: {data.get('timestamp')}")
            print(f"  アクティブシンボル: {data.get('active_symbols')}")
            return True
        else:
            print(f"NG: エラーレスポンス: {response.text}")
            return False
            
    except requests.exceptions.ConnectionError:
        print("NG: 接続エラー: サーバーに接続できません")
        return False
    except requests.exceptions.Timeout:
        print("NG: タイムアウト: 5秒以内にレスポンスがありません")
        return False
    except Exception as e:
        print(f"NG: 予期しないエラー: {e}")
        return False

def test_tick_endpoint():
    """ティックデータ送信テスト"""
    print("\n=== ティックデータ送信テスト ===")
    
    test_data = {
        "symbol": "TEST_USDJPY",
        "datetime": datetime.now().isoformat(),
        "open": 150.123,
        "high": 150.145,
        "low": 150.100,
        "close": 150.135,
        "volume": 1000
    }
    
    try:
        response = requests.post("http://localhost:5000/tick", 
                               json=test_data, 
                               timeout=5)
        print(f"レスポンスコード: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("OK: データ送信成功")
            print(f"  メッセージ: {data.get('message')}")
            print(f"  シンボル: {data.get('symbol')}")
            print(f"  バッファサイズ: {data.get('buffer_size')}")
            return True
        else:
            print(f"NG: エラーレスポンス: {response.text}")
            return False
            
    except Exception as e:
        print(f"NG: エラー: {e}")
        return False

def main():
    """メイン関数"""
    print("Flask Trading API 接続状況確認")
    print(f"確認時刻: {datetime.now()}")
    print("=" * 50)
    
    # 1. ポート確認
    port_open = test_port_5000()
    
    if not port_open:
        print("\nERROR: ポート5000が閉じているため、APIサーバーは起動していません")
        print("   確認事項:")
        print("   1. NSSMサービスが正常に起動しているか")
        print("   2. Flask APIサーバーが正常に開始されているか")
        print("   3. ファイアウォールでポート5000がブロックされていないか")
        return
    
    # 2. ヘルスチェック
    health_ok = test_health_endpoint()
    
    # 3. データ送信テスト
    if health_ok:
        tick_ok = test_tick_endpoint()
        
        if tick_ok:
            print("\nSUCCESS: APIサーバーは完全に正常に動作しています")
        else:
            print("\nWARNING: APIサーバーは起動していますが、データ処理に問題があります")
    else:
        print("\nERROR: APIサーバーは起動していますが、正常に応答していません")

if __name__ == "__main__":
    main() 