from io import StringIO
import MetaTrader5 as mt5

# ログバッファ作成
log_buffer = StringIO()

def log(msg):
    print(msg)
    log_buffer.write(msg + "\n")

import boto3
import pandas as pd
from datetime import datetime, timedelta
import pytz
import os
import re

# === 設定 ===
bucket = 'mt5-cld'
session = boto3.Session()
s3 = session.client('s3')
symbols = ['EURUSD']
timeframes = {
    'M5': mt5.TIMEFRAME_M5,
    #'M15': mt5.TIMEFRAME_M15,
    #'H1': mt5.TIMEFRAME_H1,
    #'D1': mt5.TIMEFRAME_D1,
    #'W1': mt5.TIMEFRAME_W1,
    #'MN': mt5.TIMEFRAME_MN1
}
# pandas用の頻度マップ
freq_map = {
    'M5': "5min",
    #'M15': "15min",
    #'H1': "1h",
    #'D1': "1d",
    #'W1': "W",
    #'MN': "ME"
}

# === 日付リスト ===
today_utc = datetime.now(pytz.utc).date()
dates_utc = [(today_utc - timedelta(days=i)) for i in range(90)]

# === S3上のCSVファイル一覧を取得 ===
def list_all_s3_keys():
    keys = set()
    continuation_token = None
    while True:
        kwargs = {'Bucket': bucket, 'Prefix': ''}
        if continuation_token:
            kwargs['ContinuationToken'] = continuation_token
        response = s3.list_objects_v2(**kwargs)
        for obj in response.get('Contents', []):
            keys.add(obj['Key'])
        if response.get('IsTruncated'):
            continuation_token = response['NextContinuationToken']
        else:
            break
    return keys

# === MT5初期化 ===
if not mt5.initialize():
    raise RuntimeError("MT5 initialization failed")

# === 欠損日付のデータを取得してアップロード ===
def fetch_and_upload(symbol, timeframe_str, date):
    timeframe = timeframes[timeframe_str]
    tz = pytz.utc
    start = datetime(date.year, date.month, date.day, tzinfo=tz)
    end = start + timedelta(days=1)

    rates = mt5.copy_rates_range(symbol, timeframe, start, end)
    if rates is None:
        log(f"[ERROR] Failed to fetch MT5 data: {symbol} {timeframe_str} {date} (rates is None)")
        return
    elif len(rates) == 0:
        log(f"[INFO] No market data in MT5 for: {symbol} {timeframe_str} {date} (empty)")
        return

    df = pd.DataFrame(rates)
    df['symbol'] = symbol
    df['time'] = pd.to_datetime(df['time'], unit='s')

    # ここですぐに NaN 行を除外
    df = df[~df[["open", "high", "low", "close"]].isnull().all(axis=1)]

    #  有効データが1件もなければ return（これが重要）
    if df.empty:
        log(f"[INFO] No valid OHLC data for {symbol} {timeframe_str} {date}")
        return

    year = f"{date.year}"
    month = f"{date.month:02d}"
    day = f"{date.day:02d}"
    key = f"{symbol}/timeframe={timeframe_str}/year={year}/month={month}/day={day}/{symbol}_{timeframe_str}.csv"

    csv_buffer = StringIO()
    df = df[["symbol", "time", "open", "high", "low", "close", "tick_volume", "spread", "real_volume"]]
    df.to_csv(csv_buffer, index=False, encoding='utf-8-sig')

    # === ローカル保存処理（階層化・日付分割なし） ===
    local_filename = f"{symbol}_{timeframe_str}.csv"
    base_dir = "C:/MT5_portable/MQL5/src/data"
    local_path = os.path.join(base_dir, local_filename)

    if not os.path.exists(base_dir):
        raise FileNotFoundError(f"Directory does not exist: {base_dir}")

    if os.path.exists(local_path):
        df_existing = pd.read_csv(local_path, parse_dates=["time"])
        df_existing["time"] = df_existing["time"].dt.tz_localize(None)
        df["time"] = df["time"].dt.tz_localize(None)
        df = pd.concat([df_existing, df], ignore_index=True)
        df.drop_duplicates(subset=["time"], inplace=True)
        df.sort_values("time", inplace=True)

    # open, high, low, close が全て NaN の行を除外
    df = df[~df[["open", "high", "low", "close"]].isnull().all(axis=1)]
    df.to_csv(local_path, index=False, encoding="utf-8-sig")
    log(f"[LOCAL] Saved: {local_path}")

    # === 欠損補完処理 ===
    freq = freq_map.get(timeframe_str)
    if freq is None:
        raise ValueError(f"Unsupported timeframe: {timeframe_str}")

    if freq == "M":
        start_time = df["time"].min().replace(day=1)
        end_time = (df["time"].max().replace(day=1) + pd.DateOffset(months=1))
    elif freq == "W":
        start_time = df["time"].min() - timedelta(days=df["time"].min().weekday())
        end_time = df["time"].max() + timedelta(days=6 - df["time"].max().weekday())
    else:
        start_time = df["time"].min().floor(freq)
        end_time = df["time"].max().ceil(freq)

    df.to_csv(local_path, index=False, encoding="utf-8-sig")
    print(f"[LOCAL] Saved: {local_path}")

    # === S3アップロード ===
    s3.put_object(Bucket=bucket, Key=key, Body=csv_buffer.getvalue())
    log(f"Uploaded: {key}")

# === 実行 ===
existing_keys = list_all_s3_keys()
log("S3 key list loaded")

valid_key_re = re.compile(r"^[A-Z]{6}/timeframe=[A-Z0-9]+/year=\d{4}/month=\d{2}/day=\d{2}/[A-Z]{6}_[A-Z0-9]+\.csv$")
for key in existing_keys.copy():
    if not valid_key_re.match(key):
        try:
            s3.delete_object(Bucket=bucket, Key=key)
            log(f"[CLEANUP] Deleted unexpected key: {key}")
            existing_keys.remove(key)
        except Exception as e:
            log(f"[ERROR] Failed to delete key: {key} - {e}")

for symbol in symbols:
    for tf_str, tf in timeframes.items():
        local_filename = f"{symbol}_{tf_str}.csv"
        base_dir = "C:/MT5_portable/MQL5/src/data"
        local_path = os.path.join(base_dir, local_filename)

        if os.path.exists(local_path):
            try:
                df_existing = pd.read_csv(local_path, parse_dates=["time"])
                df_existing["time"] = df_existing["time"].dt.tz_localize(None)
                for date in dates_utc:
                    date_start = datetime(date.year, date.month, date.day)
                    date_end = date_start + timedelta(days=1)
                    mask = (df_existing["time"] >= date_start) & (df_existing["time"] < date_end)
                    if not mask.any():
                        log(f"[MISSING-DATE] Missing {symbol} {tf_str} on {date}")
                        fetch_and_upload(symbol, tf_str, date)
            except Exception as e:
                log(f"[ERROR] Failed to read existing CSV for {symbol} {tf_str}: {e}")
        else:
            for date in dates_utc:
                fetch_and_upload(symbol, tf_str, date)

mt5.shutdown()
log("All missing files fetched and uploaded.")

try:
    log_date_str = datetime.now(pytz.utc).strftime('%Y%m%d')
    log_key = f"logs/check_missing_bars/check_missing_bars_{log_date_str}.log"
    s3.put_object(Bucket=bucket, Key=log_key, Body=log_buffer.getvalue().encode('utf-8'))
    print(f"[INFO] Log uploaded to s3://{bucket}/{log_key}")
except Exception as e:
    print(f"[ERROR] Failed to upload log to S3: {e}")