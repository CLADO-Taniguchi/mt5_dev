# 以下をPythonで実行してテスト
import talib
import numpy as np

# TA-Libのバージョン確認
print("OK: TA-Lib version:", talib.__version__)

# 簡単なテストデータ
close_prices = np.array([10.0, 10.5, 11.0, 10.8, 11.2, 11.5, 11.3, 11.8, 12.0, 11.9])

# SMA計算テスト
sma = talib.SMA(close_prices, timeperiod=3)
print("OK: SMA calculation:", sma)

print("TA-Lib test completed successfully!")