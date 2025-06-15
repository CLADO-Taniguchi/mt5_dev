import numpy as np
import pandas as pd

def weighted_moving_average(data: pd.Series, length: int) -> pd.Series:
    weights = np.arange(length, 0, -1)
    return data.rolling(length).apply(lambda x: np.dot(x, weights) / weights.sum(), raw=True)

def hull_moving_average(close: pd.Series, period: int = 21) -> pd.Series:
    sqrt_period = int(np.sqrt(period))
    wma_half = weighted_moving_average(close, period // 2)
    wma_full = weighted_moving_average(close, period)
    raw_wma = 2 * wma_half - wma_full
    hma = weighted_moving_average(raw_wma, sqrt_period)
    return hma