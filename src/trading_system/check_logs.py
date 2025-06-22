#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ログファイル確認スクリプト
"""

import os
import glob
from datetime import datetime
from pathlib import Path

def check_log_files():
    """ログファイルの確認"""
    print("=== ログファイル確認 ===")
    
    # 現在のディレクトリ
    current_dir = Path(__file__).parent
    print(f"確認ディレクトリ: {current_dir}")
    
    # ログディレクトリ
    logs_dir = current_dir / "logs"
    if logs_dir.exists():
        print(f"OK: ログディレクトリ存在: {logs_dir}")
        
        # NSSMログファイル
        nssm_logs = list(logs_dir.glob("*.log"))
        if nssm_logs:
            print(f"OK: NSSMログファイル: {len(nssm_logs)}個")
            for log_file in nssm_logs:
                print(f"  - {log_file.name}")
                try:
                    # ファイルサイズと最終更新時刻
                    stat = log_file.stat()
                    size_kb = stat.st_size / 1024
                    mtime = datetime.fromtimestamp(stat.st_mtime)
                    print(f"    サイズ: {size_kb:.1f}KB, 最終更新: {mtime}")
                    
                    # 最後の10行を表示
                    with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                        lines = f.readlines()
                        if lines:
                            print(f"    最新ログ (最後の5行):")
                            for line in lines[-5:]:
                                print(f"      {line.strip()}")
                        else:
                            print("    ログファイルは空です")
                except Exception as e:
                    print(f"    読み込みエラー: {e}")
        else:
            print("NG: NSSMログファイルが見つかりません")
    else:
        print("NG: ログディレクトリが存在しません")
    
    # Flask APIログファイル
    print("\n=== Flask APIログファイル ===")
    api_log = current_dir / "trading_api.log"
    if api_log.exists():
        print(f"OK: Flask APIログ存在: {api_log}")
        try:
            stat = api_log.stat()
            size_kb = stat.st_size / 1024
            mtime = datetime.fromtimestamp(stat.st_mtime)
            print(f"  サイズ: {size_kb:.1f}KB, 最終更新: {mtime}")
            
            # 最後の10行を表示
            with open(api_log, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                if lines:
                    print(f"  最新ログ (最後の10行):")
                    for line in lines[-10:]:
                        print(f"    {line.strip()}")
                else:
                    print("  ログファイルは空です")
        except Exception as e:
            print(f"  読み込みエラー: {e}")
    else:
        print("NG: Flask APIログファイルが見つかりません")
    
    # その他のログファイル
    print("\n=== その他のログファイル ===")
    all_logs = list(current_dir.glob("*.log"))
    if all_logs:
        print(f"OK: その他のログファイル: {len(all_logs)}個")
        for log_file in all_logs:
            if log_file.name != "trading_api.log":
                print(f"  - {log_file.name}")
    else:
        print("NG: その他のログファイルはありません")

def check_data_files():
    """データファイルの確認"""
    print("\n=== データファイル確認 ===")
    
    current_dir = Path(__file__).parent
    
    # データディレクトリ
    data_dir = current_dir / "data"
    if data_dir.exists():
        print(f"OK: データディレクトリ存在: {data_dir}")
        
        # シンボル別ディレクトリ
        symbol_dirs = list(data_dir.glob("*"))
        if symbol_dirs:
            print(f"OK: シンボルディレクトリ: {len(symbol_dirs)}個")
            for symbol_dir in symbol_dirs:
                if symbol_dir.is_dir():
                    print(f"  - {symbol_dir.name}")
                    
                    # 現在のデータファイル
                    current_file = symbol_dir / f"{symbol_dir.name}_current.csv"
                    if current_file.exists():
                        try:
                            stat = current_file.stat()
                            size_kb = stat.st_size / 1024
                            mtime = datetime.fromtimestamp(stat.st_mtime)
                            print(f"    現在データ: {size_kb:.1f}KB, 更新: {mtime}")
                        except:
                            pass
                    
                    # アーカイブファイル
                    archive_dir = symbol_dir / "archive"
                    if archive_dir.exists():
                        archive_files = list(archive_dir.glob("*.csv"))
                        print(f"    アーカイブ: {len(archive_files)}個")
        else:
            print("NG: シンボルディレクトリがありません")
    else:
        print("NG: データディレクトリが存在しません")

def main():
    """メイン関数"""
    print("Flask Trading API ログ・データファイル確認")
    print(f"確認時刻: {datetime.now()}")
    print("=" * 60)
    
    check_log_files()
    check_data_files()
    
    print("\n" + "=" * 60)
    print("確認完了")

if __name__ == "__main__":
    main() 