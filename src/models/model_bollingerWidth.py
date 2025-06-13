import pandas as pd
import numpy as np

def calculate_bollinger_width(df, period=20, sigma=3):
    """
    ボリンジャーバンドの±σ幅（最新バー）を計算

    Parameters:
    - df: DataFrame, 必須カラム 'close'
    - period: 移動平均と標準偏差の期間（デフォルト: 20）
    - sigma: 標準偏差の乗数（デフォルト: 3）

    Returns:
    - 最新のボリンジャーバンド幅（上バンド - 下バンド）
    - 最新の中心線（SMA）、上バンド、下バンド
    """
    close = df['close']

    sma = close.rolling(window=period).mean()
    std = close.rolling(window=period).std()

    upper = sma + sigma * std
    lower = sma - sigma * std

    # 最新バー（バー0）の値幅
    latest_width = upper.iloc[-1] - lower.iloc[-1]

    return {
        'width': latest_width,
        'sma': sma.iloc[-1],
        'upper_band': upper.iloc[-1],
        'lower_band': lower.iloc[-1]
    }

# --- 使用例 ---
# 仮の終値データを生成
# 実際はOHLCVのDataFrameを読み込んで使う
data = {
    'close': np.random.normal(loc=100, scale=1, size=100)
}
df = pd.DataFrame(data)

result = calculate_bollinger_width(df)
print(f"ボリンジャーバンド ±3σ の値幅: {result['width']:.4f}")
print(f"中心線: {result['sma']:.4f}")
print(f"上バンド: {result['upper_band']:.4f}")
print(f"下バンド: {result['lower_band']:.4f}")