# 以下をPythonで実行してテスト
import talib
import numpy as np
print("✅ TA-Lib version:", talib.__version__)

# 簡単な動作テスト
close_prices = np.array([1.1000, 1.1010, 1.1005, 1.1015, 1.1020], dtype=float)
sma = talib.SMA(close_prices, timeperiod=3)
print("✅ SMA calculation:", sma)
print("TA-Lib正常動作中！")