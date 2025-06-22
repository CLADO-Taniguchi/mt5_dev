#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Flask Trading API 接続テストスクリプト
"""

import requests
import json
import time
from datetime import datetime

def test_api_connection():
    """API接続テスト"""
    base_url = "http://localhost:5000"
    
    print("=== Flask Trading API 接続テスト ===")
    print(f"テスト開始時刻: {datetime.now()}")
    print(f"対象URL: {base_url}")
    print()
    
    # 1. ヘルスチェック
    print("1. ヘルスチェックテスト...")
    try:
        response = requests.get(f"{base_url}/health", timeout=10)
        if response.status_code == 200:
            data = response.json()
            print(f"OK: {response.status_code}")
            print(f"  ステータス: {data.get('status')}")
            print(f"  アクティブシンボル: {data.get('active_symbols')}")
            print(f"  総データポイント: {data.get('total_data_points')}")
            print(f"  モデル読み込み済み: {data.get('symbols_with_models')}")
        else:
            print(f"NG: {response.status_code}")
            print(f"  レスポンス: {response.text}")
    except requests.exceptions.ConnectionError:
        print("NG: 接続エラー: サーバーに接続できません")
        print("  サーバーが起動していないか、ポート5000でリッスンしていません")
    except requests.exceptions.Timeout:
        print("NG: タイムアウト: 10秒以内にレスポンスがありません")
    except Exception as e:
        print(f"NG: 予期しないエラー: {e}")
    
    print()
    
    # 2. システム状態取得
    print("2. システム状態テスト...")
    try:
        response = requests.get(f"{base_url}/status", timeout=10)
        if response.status_code == 200:
            data = response.json()
            print(f"OK: {response.status_code}")
            symbols = data.get('symbols', {})
            if symbols:
                print(f"  登録シンボル数: {len(symbols)}")
                for symbol, info in symbols.items():
                    print(f"    {symbol}: バッファ{info.get('current_buffer_size', 0)}件")
            else:
                print("  登録シンボル: なし")
        else:
            print(f"NG: {response.status_code}")
    except Exception as e:
        print(f"NG: エラー: {e}")
    
    print()
    
    # 3. テストデータ送信
    print("3. テストデータ送信...")
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
        response = requests.post(f"{base_url}/tick", 
                               json=test_data, 
                               timeout=10)
        if response.status_code == 200:
            data = response.json()
            print(f"OK: {response.status_code}")
            print(f"  メッセージ: {data.get('message')}")
            print(f"  バッファサイズ: {data.get('buffer_size')}")
        else:
            print(f"NG: {response.status_code}")
            print(f"  レスポンス: {response.text}")
    except Exception as e:
        print(f"NG: エラー: {e}")
    
    print()
    
    # 4. ポートスキャン
    print("4. ポート5000の確認...")
    try:
        import socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        result = sock.connect_ex(('localhost', 5000))
        sock.close()
        
        if result == 0:
            print("OK: ポート5000は開いています")
        else:
            print("NG: ポート5000は閉じています")
    except Exception as e:
        print(f"NG: ポート確認エラー: {e}")
    
    print()
    print("=== テスト完了 ===")

def check_process_status():
    """プロセス状態確認"""
    print("=== プロセス状態確認 ===")
    
    try:
        import psutil
        
        # Pythonプロセスを検索
        python_processes = []
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if 'python' in proc.info['name'].lower():
                    cmdline = ' '.join(proc.info['cmdline']) if proc.info['cmdline'] else ''
                    if 'flask_trading_api' in cmdline:
                        python_processes.append({
                            'pid': proc.info['pid'],
                            'name': proc.info['name'],
                            'cmdline': cmdline
                        })
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        if python_processes:
            print(f"OK: Flask API関連プロセス: {len(python_processes)}個")
            for proc in python_processes:
                print(f"  PID: {proc['pid']}, コマンド: {proc['cmdline'][:100]}...")
        else:
            print("NG: Flask API関連プロセスが見つかりません")
            
    except ImportError:
        print("psutilライブラリがインストールされていません")
    except Exception as e:
        print(f"プロセス確認エラー: {e}")
    
    print()

if __name__ == "__main__":
    check_process_status()
    test_api_connection() 