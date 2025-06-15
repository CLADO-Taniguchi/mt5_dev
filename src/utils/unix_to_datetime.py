import pandas as pd

def convert_unix_to_datetime():
    """timeカラムのUnixタイムスタンプをdatetimeに変換"""
    try:
        # CSVファイル読み込み（BOM対応）
        csv_file = 'C:/MT5_portable/MQL5/Files/backtest_hma_20250613235959_split.csv'  # ファイル名を適宜変更
        print(f"ファイルを読み込み中: {csv_file}")
        
        # BOM付きファイルに対応するため、encoding指定で読み込み
        df = pd.read_csv(csv_file, encoding='utf-8-sig')
        
        print(f"データ件数: {len(df)}")
        print(f"カラム名: {list(df.columns)}")
        
        # カラム名の前後の空白を除去（BOM対策）
        df.columns = df.columns.str.strip()
        print(f"クリーンアップ後のカラム名: {list(df.columns)}")
        
        print("/n最初の3行（変換前）:")
        print(df.head(3))
        
        # timeカラムが存在するかチェック
        if 'time' not in df.columns:
            print("エラー: 'time'カラムが見つかりません")
            print(f"利用可能なカラム: {list(df.columns)}")
            return False
        
        # unix_timeをdatetimeに変換
        print("Unixタイムスタンプを変換中...")
        df['datetime'] = pd.to_datetime(df['time'], unit='s')
        
        # timeカラムを削除してdatetimeカラムを先頭に移動
        df = df.drop('time', axis=1)
        columns = ['datetime'] + [col for col in df.columns if col != 'datetime']
        df = df[columns]
        
        # 新しいCSVファイルに保存（BOMなしで出力）
        output_file = 'backtest_results_converted.csv'
        df.to_csv(output_file, index=False, encoding='utf-8')
        
        print(f"\n✅ 変換完了！")
        print(f"📁 出力ファイル: {output_file}")
        print(f"📊 データ件数: {len(df)}")
        print("\n🔍 変換後の最初の5行:")
        print(df.head())
        
        # 統計情報
        if 'isWin' in df.columns:
            win_count = (df['isWin'] == 'WIN').sum()
            total_trades = len(df)
            win_rate = (win_count / total_trades) * 100 if total_trades > 0 else 0
            print(f"\n📈 統計情報:")
            print(f"   勝利数: {win_count}/{total_trades} ({win_rate:.1f}%)")
        
        # 時間範囲
        print(f"   期間: {df['datetime'].min()} ～ {df['datetime'].max()}")
        
        return True
        
    except FileNotFoundError:
        print(f"エラー: ファイルが見つかりません: {csv_file}")
        print("ファイル名を確認してください。")
        return False
    except Exception as e:
        print(f"エラー: {str(e)}")
        return False

if __name__ == "__main__":
    print("=== Unixタイムスタンプ → Datetime変換ツール ===\n")
    
    success = convert_unix_to_datetime()
    
    if success:
        print("\n✨ 変換が完了しました！")
        print("📁 'backtest_results_converted.csv' ファイルを確認してください。")
    else:
        print("\n❌ 変換に失敗しました。")