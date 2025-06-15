import pandas as pd
import os
from datetime import datetime
import sys

sys.path.append("C:/MT5_portable/MQL5/src/python_indicator")
from hma import hull_moving_average


# ① M5データ読み込み
input_path = "C:/MT5_portable/MQL5/src/data/EURUSD_M5.csv"
df = pd.read_csv(input_path)
df['time'] = pd.to_datetime(df['time']).dt.tz_localize('UTC')

# ② HMA計算（期間21）
df['hma'] = hull_moving_average(df['close'], period=21)

# ③ シグナル判定
df['signal'] = ""
prev_trend = None

for i in range(2, len(df)):
    # 現在のトレンド判定
    if df['hma'].iloc[i-2] < df['hma'].iloc[i-1]:
        curr_trend = "SELL"
    elif df['hma'].iloc[i-2] > df['hma'].iloc[i-1]:
        curr_trend = "BUY"
    else:
        curr_trend = prev_trend  # 変化なし

    # トレンドが変化した時だけシグナルを出す
    if prev_trend is not None and curr_trend != prev_trend:
        df.at[df.index[i], 'signal'] = curr_trend

    prev_trend = curr_trend

#出力用のtrade_idを付ける
df['trade_id'] = range(len(df))

# ⑤ CSV出力処理
output_dir = "C:/MT5_portable/MQL5/src/models/results/"
os.makedirs(output_dir, exist_ok=True)

timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
output_file = f"model_hma_result_{timestamp}.csv"
output_path = os.path.join(output_dir, output_file)

# タイムゾーン除去
df['time'] = pd.to_datetime(df['time']).dt.tz_localize(None)

# BUY/SELL シグナルだけ抽出し、必要なカラムへ絞る
df_out = df[df['signal'].isin(['BUY', 'SELL'])][['time', 'signal', 'hma']].rename(columns={'hma': 'price'})

# trade_id を 0 から振り直す（重要）
df_out = df_out.reset_index(drop=True)
df_out['trade_id'] = df_out.index
df_out['label'] = df_out.index

# CSV 出力
df_out.to_csv(output_path, index=False)
print(f"[INFO] 出力完了: {output_path}")