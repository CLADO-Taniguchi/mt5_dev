from flask import Flask, request, jsonify
import MetaTrader5 as mt5
import pandas as pd
import pandas_ta as ta
from datetime import datetime, timedelta, timezone

app = Flask(__name__)



@app.route("/get_signal", methods=["GET"])
def get_signal():
    symbol = request.args.get("symbol", "EURUSD")
    timeframe = request.args.get("timeframe", "M5")
    position = request.args.get("position", "")
    has_position = mt5.positions_get(symbol=symbol)

    tf_map = {"M1": mt5.TIMEFRAME_M1, "M5": mt5.TIMEFRAME_M5, "M15": mt5.TIMEFRAME_M15}
    tf = tf_map.get(timeframe, mt5.TIMEFRAME_M5)

    if not mt5.initialize():
        return jsonify({"signal": "", "error": "MT5 connection failed"}), 500

    rates = mt5.copy_rates_from_pos(symbol, tf, 0, 50)
    mt5.shutdown()

    if rates is None or len(rates) < 10:
        return jsonify({"signal": "", "error": "Insufficient data"}), 400

    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s")
    df["stoch_k"] = ta.stoch(df["high"], df["low"], df["close"], k=5, d=3)["STOCHk_5_3_3"]
    df["stoch_d"] = ta.stoch(df["high"], df["low"], df["close"], k=5, d=3)["STOCHd_5_3_3"]
    df["adx"] = ta.adx(df["high"], df["low"], df["close"], length=7)["ADX_7"]
    df["wma"] = ta.wma(df["close"], length=14)

    i = len(df) - 1
    k_t0 = df["stoch_k"].iloc[i]
    k_t1 = df["stoch_k"].iloc[i - 1]
    k_t2 = df["stoch_k"].iloc[i - 2]
    d_t0 = df["stoch_d"].iloc[i] # %D（赤い点線）（バー0）
    adx0 = df["adx"].iloc[i]
    adx1 = df["adx"].iloc[i - 1]
    adx2 = df["adx"].iloc[i - 2]
    wma1 = df["wma"].iloc[i - 1]
    wma2 = df["wma"].iloc[i - 2]

    signal = ""
    trend_type = ""
    exit = False

    # === トレンドタイプ別ENTRY条件 ===
    if (adx0 > 40) and (wma2 < wma1):
        trend_type = "UP"
    elif (adx0 > 40) and (wma2 > wma1):
            trend_type = "DOWN"
    elif adx0 <= 40:
        trend_type = "BOX"
    else:
        trend_type = ""

    # === ENTRY判定（トレンド別にブロックを分ける） ===

    last_dir, last_result = check_last_trade(symbol)

    if trend_type == "BOX" and not has_position:
        if k_t0 <= 20:
            if not (last_dir == "BUY" and last_result == "LOSE"):
                signal = "BUY"
        elif k_t0 >= 80:
            if not (last_dir == "SELL" and last_result == "LOSE"):
                signal = "SELL"

#    elif trend_type == "BOX":
#        if k_t2 > k_t1 and k_t1 < k_t0:  # BUY条件（谷）
#            if k_t1 <= 20 and (k_t0 > 20 or k_t0 > d_t0) :
#                signal = "BUY"
#        elif k_t2 < k_t1 and k_t1 > k_t0:  # SELL条件（山）
#            if k_t1 >= 80 and (k_t0 < 80 or k_t0 < d_t0):
#                signal = "SELL"

    # === EXIT判定（ポジション別にトレンドを参照） ===
    if position == "BUY":
        if (k_t0 >= 80) or (k_t0 < k_t1):
            exit = True
    elif position == "SELL":
        if (k_t0 <= 20) or (k_t0 > k_t1):
            exit = True

    price = float(df["close"].iloc[i])
    time = df["time"].iloc[i].strftime("%Y-%m-%d %H:%M:%S")
    k_value = float(k_t0)

    return jsonify({
        "signal": signal,
        "price": price,
        "time": time,
        "k_value": k_value,
        "exit": exit
    })

def check_last_trade(symbol):
    from datetime import datetime, timedelta
    deals = mt5.history_deals_get(datetime.now(timezone.utc) - timedelta(days=30), datetime.now(timezone.utc))
    if deals is None:
        return None, None
    # 最新の決済済みトレード（entry = DEAL_ENTRY_OUT）のみ
    closed = [d for d in deals if d.symbol == symbol and d.entry == mt5.DEAL_ENTRY_OUT]
    closed.sort(key=lambda x: x.time, reverse=True)
    if not closed:
        return None, None
    last = closed[0]
    direction = "BUY" if last.type == mt5.DEAL_TYPE_BUY else "SELL"
    result = "WIN" if last.profit > 0 else "LOSE"
    return direction, result

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)