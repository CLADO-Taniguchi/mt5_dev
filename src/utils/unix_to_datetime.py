#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Unix timestamp を datetime に変換するスクリプト
"""

import pandas as pd
from datetime import datetime
import sys

def convert_unix_to_datetime(input_file, output_file=None):
    """
    CSVファイルのUnix timestampをdatetimeに変換
    
    Args:
        input_file (str): 入力CSVファイルのパス
        output_file (str): 出力CSVファイルのパス（Noneの場合は上書き）
    """
    try:
        # CSVファイルを読み込み
        print(f"ファイル読み込み中: {input_file}")
        df = pd.read_csv(input_file)
        
        # datetime列を探す
        datetime_columns = []
        for col in df.columns:
            if 'datetime' in col.lower() or 'time' in col.lower():
                datetime_columns.append(col)
        
        if not datetime_columns:
            print("datetime列が見つかりません")
            return False
        
        print(f"変換対象列: {datetime_columns}")
        
        # 各datetime列を変換
        for col in datetime_columns:
            try:
                # Unix timestampとして解釈して変換
                df[col] = pd.to_datetime(df[col], unit='s')
                print(f"列 '{col}' を変換しました")
            except Exception as e:
                print(f"列 '{col}' の変換に失敗: {e}")
                # 既にdatetime形式の場合はスキップ
                try:
                    df[col] = pd.to_datetime(df[col])
                    print(f"列 '{col}' は既にdatetime形式でした")
                except:
                    print(f"列 '{col}' は変換できませんでした")
        
        # 出力ファイル名を決定
        if output_file is None:
            output_file = input_file.replace('.csv', '_converted.csv')
        
        # 変換されたデータを保存
        df.to_csv(output_file, index=False)
        
        print(f"\nSUCCESS: 変換完了！")
        print(f"出力ファイル: {output_file}")
        print(f"変換された行数: {len(df)}")
        
        return True
        
    except FileNotFoundError:
        print(f"ファイルが見つかりません: {input_file}")
        return False
    except Exception as e:
        print(f"エラーが発生しました: {e}")
        return False

def main():
    """メイン関数"""
    if len(sys.argv) < 2:
        print("使用方法: python unix_to_datetime.py <入力ファイル> [出力ファイル]")
        print("例: python unix_to_datetime.py data.csv")
        print("例: python unix_to_datetime.py data.csv converted_data.csv")
        return
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    print("Unix timestamp から datetime への変換を開始します...")
    print(f"入力ファイル: {input_file}")
    if output_file:
        print(f"出力ファイル: {output_file}")
    
    success = convert_unix_to_datetime(input_file, output_file)
    
    if not success:
        print("\nERROR: 変換に失敗しました。")
        sys.exit(1)

if __name__ == "__main__":
    main()