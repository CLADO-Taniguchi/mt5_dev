import pandas as pd

# CSVファイル読み込み
df = pd.read_csv('C:/MT5_portable/MQL5/Files/backtest_hma_20250613235959.csv')  # ファイル名を適宜変更

# unix_timeをdatetimeに変換
df['time'] = pd.to_datetime(df['time'], unit='s')

# unix_timeカラムを削除
#df = df.drop('unix_time', axis=1)

# カラム順序を調整（timeを先頭に）
df = df[['time', 'open', 'hma_1', 'hma_2', 'exit', 'isWin']]

# 新しいCSVファイルに保存
df.to_csv('backtest_results_converted.csv', index=False)

print("変換完了！")
print(f"データ件数: {len(df)}")
print("\n最初の5行:")
print(df.head())