//+------------------------------------------------------------------+
//|                                     ExpertHMA_TrailingATR.mq5 |
//|                                  Copyright 2023, MetaQuotes Ltd |
//|                                              https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd"
#property link      "https://www.mql5.com"
#property version   "3.00" // Added Reversal Mode logic

#include <Trade/Trade.mqh>

//--- EA Settings
input ulong    MagicNumber          = 98765;      // EAを識別するマジックナンバー
input double   LotSize              = 0.01;       // 固定ロットサイズ
input bool     ShowTradeObjects     = true;       // 取引オブジェクトをチャートに表示するか

//--- HMA & Trend Filter Settings
input ENUM_TIMEFRAMES Trend_Timeframe      = PERIOD_M5;  // 長期トレンドを判断する時間足
input ENUM_TIMEFRAMES Signal_Timeframe     = PERIOD_M1;  // 売買シグナルを判断する時間足
input int      HMA_Period           = 21;         // HMAの期間
input double   ADX_Threshold        = 25.0;       // トレンド判定のADXしきい値
input double   Volatility_Threshold = 0.04;       // ボラティリティしきい値

//--- Trading Logic
input bool     AllowReverseTrade    = true;       // This is now implicitly handled by the new logic

//--- Trailing Stop Settings
input bool     UseTrailingStop      = true;       // トレーリングストップを使用するか
input double   TS_AtrMultiplier_MIN = 1.5;        // レンジ相場でのATR係数（最小値）
input double   TS_AtrMultiplier_MAX = 3.5;        // トレンド相場でのATR係数（最大値）
input double   TS_ActivationPips    = 10.0;       // トレーリングストップが有効になる利益幅 (Pips)

//--- Global variables
CTrade trade;
int    m1_signal_handle;
int    m5_trend_handle;
int    atr_handle;
long   object_counter = 0; // オブジェクト名を一意にするためのカウンター

//--- Trend and Signal enumerations
enum ENUM_TREND
{
    TREND_NONE,
    TREND_UP,
    TREND_DOWN
};

enum ENUM_REVERSAL_SIGNAL
{
    REVERSAL_NONE,
    REVERSAL_BUY,
    REVERSAL_SELL
};

//--- Trading Mode enumeration
enum ENUM_TRADING_MODE
{
    MODE_REGULAR,  // Normal mode: Filtered by M5 trend
    MODE_REVERSAL  // Reversal mode: M1 HMA cross -> Reversal trading
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Initialize trade object
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetMarginMode();

    //--- データがロードされるのを待つ (特にMTFの場合) ---
    printf("Waiting for history data to load...");
    int attempts = 0;
    // メインのシグナル時間足とトレンド時間足の両方のデータがロードされるのを待つ
    while((iBars(_Symbol, Signal_Timeframe) < HMA_Period + 50 || iBars(_Symbol, Trend_Timeframe) < HMA_Period + 50) && attempts < 120 && !IsStopped())
    {
        attempts++;
        printf("Waiting for data... Attempt %d/120. M1 bars: %d, M5 bars: %d", attempts, (int)iBars(_Symbol, Signal_Timeframe), (int)iBars(_Symbol, Trend_Timeframe));
        Sleep(500); // 0.5秒待機
    }

    if(iBars(_Symbol, Signal_Timeframe) < HMA_Period + 50 || iBars(_Symbol, Trend_Timeframe) < HMA_Period + 50)
    {
        string message = StringFormat("Error: Failed to load sufficient history data for M1 or M5 timeframe after 60 seconds. M1 Bars: %d, M5 Bars: %d. Halting initialization.", 
                                      (int)iBars(_Symbol, Signal_Timeframe), (int)iBars(_Symbol, Trend_Timeframe));
        printf(message);
        Alert(message);
        return(INIT_FAILED);
    }
    printf("History data loaded successfully.");


    //--- Initialize HMA indicators
    // M1 Signal Indicator
    m1_signal_handle = iCustom(_Symbol, Signal_Timeframe, "hma_chart_plot_GV",
                               HMA_Period, 14, ADX_Threshold, 14, 20, Volatility_Threshold, 20, 2.0, 10);
    if(m1_signal_handle == INVALID_HANDLE)
    {
        printf("Error creating M1 Signal indicator handle - error %d", GetLastError());
        return(INIT_FAILED);
    }
    
    // M5 Trend Indicator
    m5_trend_handle = iCustom(_Symbol, Trend_Timeframe, "hma_chart_plot_GV",
                              HMA_Period, 14, ADX_Threshold, 14, 20, Volatility_Threshold, 20, 2.0, 10);
    if(m5_trend_handle == INVALID_HANDLE)
    {
        printf("Error creating M5 Trend indicator handle - error %d", GetLastError());
        return(INIT_FAILED);
    }
    
    //--- Initialize ATR indicator for trailing stop (using Signal_Timeframe)
    atr_handle = iATR(_Symbol, Signal_Timeframe, 14);
    if(atr_handle == INVALID_HANDLE)
    {
        printf("Error creating ATR indicator handle - error %d", GetLastError());
        return(INIT_FAILED);
    }

    object_counter = TimeCurrent(); // カウンターを現在時刻で初期化

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handles
    IndicatorRelease(m1_signal_handle);
    IndicatorRelease(m5_trend_handle);
    IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- 1. Trailing Stop logic (runs on every tick)
    DoTrailingStop();

    //--- 2. Entry/Exit logic (runs once per new bar on the Signal_Timeframe)
    static datetime last_bar_time;
    datetime current_bar_time = iTime(_Symbol, Signal_Timeframe, 0);
    if(last_bar_time >= current_bar_time)
    {
        return; // Not a new bar yet
    }
    last_bar_time = current_bar_time;

    //--- Execute new trading logic
    CheckAndExecuteTrades();
}

//+------------------------------------------------------------------+
//| Get M5 Trend direction from indicator color                      |
//+------------------------------------------------------------------+
ENUM_TREND GetM5Trend()
{
    // M1のシグナルバー（確定足）の時間を取得
    datetime m1_bar_time = iTime(_Symbol, Signal_Timeframe, 1);
    if(m1_bar_time == 0) 
    {
        printf("DEBUG: GetM5Trend - Failed to get M1 bar time");
        return TREND_NONE; // エラーチェック
    }

    // M1のバーに対応するM5のバーシフトを取得
    int m5_bar_shift = iBarShift(_Symbol, Trend_Timeframe, m1_bar_time);
    if(m5_bar_shift < 0) 
    {
        printf("DEBUG: GetM5Trend - Failed to get M5 bar shift for M1 time %s", TimeToString(m1_bar_time));
        return TREND_NONE; // エラーチェック
    }

    double m5_color_buffer[1];
    if(CopyBuffer(m5_trend_handle, 1, m5_bar_shift, 1, m5_color_buffer) <= 0)
    {
        printf("DEBUG: GetM5Trend - Error copying M5 trend buffer for shift %d - error %d", m5_bar_shift, GetLastError());
        return TREND_NONE;
    }

    printf("DEBUG: GetM5Trend - M5 color buffer value: %.1f at shift %d", m5_color_buffer[0], m5_bar_shift);

    if(m5_color_buffer[0] == 0.0) 
    {
        printf("DEBUG: GetM5Trend - Returning TREND_UP (Green)");
        return TREND_UP;   // Green
    }
    if(m5_color_buffer[0] == 1.0) 
    {
        printf("DEBUG: GetM5Trend - Returning TREND_DOWN (Red)");
        return TREND_DOWN; // Red
    }
    
    printf("DEBUG: GetM5Trend - Returning TREND_NONE (Unknown color: %.1f)", m5_color_buffer[0]);
    return TREND_NONE;
}

//+------------------------------------------------------------------+
//| Get M1 Reversal Signal from indicator color change               |
//+------------------------------------------------------------------+
ENUM_REVERSAL_SIGNAL GetM1Signal()
{
    double m1_color_buffer[]; // 動的配列として宣言
    ArrayResize(m1_color_buffer, 3); // サイズを3に設定
    ArraySetAsSeries(m1_color_buffer, true);

    if(CopyBuffer(m1_signal_handle, 1, 0, 3, m1_color_buffer) < 3)
    {
        printf("DEBUG: GetM1Signal - Error copying M1 signal buffer - error %d", GetLastError());
        return REVERSAL_NONE;
    }

    printf("DEBUG: GetM1Signal - M1 color buffer values: [%.1f, %.1f, %.1f]", 
           m1_color_buffer[2], m1_color_buffer[1], m1_color_buffer[0]);

    // Check for reversal on the last closed bar (index 1)
    // Buy reversal: color changed from Red (1.0) to Green (0.0)
    if(m1_color_buffer[2] == 1.0 && m1_color_buffer[1] == 0.0)
    {
        printf("DEBUG: GetM1Signal - Returning REVERSAL_BUY (Red->Green)");
        return REVERSAL_BUY;
    }
    // Sell reversal: color changed from Green (0.0) to Red (1.0)
    if(m1_color_buffer[2] == 0.0 && m1_color_buffer[1] == 1.0)
    {
        printf("DEBUG: GetM1Signal - Returning REVERSAL_SELL (Green->Red)");
        return REVERSAL_SELL;
    }

    printf("DEBUG: GetM1Signal - Returning REVERSAL_NONE (No color change detected)");
    return REVERSAL_NONE;
}

//+------------------------------------------------------------------+
//| Get HMA values from both timeframes                              |
//+------------------------------------------------------------------+
bool GetHmaValues(double &hma_m1, double &hma_m5)
{
    // M1 HMAはシグナルと同じ確定足(1)から取得
    double m1_hma_buffer[1];
    if(CopyBuffer(m1_signal_handle, 0, 1, 1, m1_hma_buffer) <= 0)
    {
        printf("DEBUG: GetHmaValues - Failed to copy M1 HMA buffer.");
        return false;
    }
    hma_m1 = m1_hma_buffer[0];
    printf("DEBUG: GetHmaValues - M1 HMA value: %.5f", hma_m1);

    // M5 HMAは、M1の確定足に対応するM5の足から取得
    datetime m1_bar_time = iTime(_Symbol, Signal_Timeframe, 1);
    if(m1_bar_time == 0) 
    {
        printf("DEBUG: GetHmaValues - Failed to get M1 bar time");
        return false;
    }

    int m5_bar_shift = iBarShift(_Symbol, Trend_Timeframe, m1_bar_time);
    if(m5_bar_shift < 0) 
    {
        printf("DEBUG: GetHmaValues - Failed to get M5 bar shift for M1 time %s", TimeToString(m1_bar_time));
        return false;
    }

    double m5_hma_buffer[1];
    if(CopyBuffer(m5_trend_handle, 0, m5_bar_shift, 1, m5_hma_buffer) <= 0)
    {
        printf("DEBUG: GetHmaValues - Failed to copy M5 HMA buffer for shift %d. Error: %d", m5_bar_shift, GetLastError());
        return false;
    }
    hma_m5 = m5_hma_buffer[0];
    printf("DEBUG: GetHmaValues - M5 HMA value: %.5f at shift %d", hma_m5, m5_bar_shift);

    return true;
}

//+------------------------------------------------------------------+
//| Handle position entry and exits based on M1/M5 logic             |
//+------------------------------------------------------------------+
void CheckAndExecuteTrades()
{
    // 1. Get all necessary data
    ENUM_TREND m5_trend = GetM5Trend();
    if(m5_trend == TREND_NONE) 
    {
        printf("DEBUG: M5 trend is NONE, skipping trade check");
        return;
    }

    ENUM_REVERSAL_SIGNAL m1_signal = GetM1Signal();

    double hma_m1, hma_m5;
    if(!GetHmaValues(hma_m1, hma_m5))
    {
        printf("Error getting HMA values, skipping trade check.");
        return;
    }

    // 2. Determine Trading Mode
    ENUM_TRADING_MODE current_mode = MODE_REGULAR;
    if (m5_trend == TREND_UP && hma_m1 < hma_m5) // Dead cross during uptrend
    {
        current_mode = MODE_REVERSAL;
        printf("DEBUG: MODE_REVERSAL detected - M5 UP trend, M1 HMA(%.5f) < M5 HMA(%.5f)", hma_m1, hma_m5);
    }
    else if (m5_trend == TREND_DOWN && hma_m1 > hma_m5) // Golden cross during downtrend
    {
        current_mode = MODE_REVERSAL;
        printf("DEBUG: MODE_REVERSAL detected - M5 DOWN trend, M1 HMA(%.5f) > M5 HMA(%.5f)", hma_m1, hma_m5);
    }
    else
    {
        printf("DEBUG: MODE_REGULAR - M5 trend: %s, M1 HMA: %.5f, M5 HMA: %.5f", 
               (m5_trend == TREND_UP ? "UP" : "DOWN"), hma_m1, hma_m5);
    }
    
    // 3. Execute logic based on mode
    bool position_exists = PositionSelect(_Symbol);
    long position_type = position_exists ? PositionGetInteger(POSITION_TYPE) : -1;

    printf("DEBUG: Position exists: %s, Position type: %s, M1 signal: %s", 
           (position_exists ? "YES" : "NO"), 
           (position_type == POSITION_TYPE_BUY ? "BUY" : position_type == POSITION_TYPE_SELL ? "SELL" : "NONE"),
           (m1_signal == REVERSAL_BUY ? "BUY" : m1_signal == REVERSAL_SELL ? "SELL" : "NONE"));

    // --- MODE_REVERSAL: M1のドテン売買 ---
    if(current_mode == MODE_REVERSAL)
    {
        printf("DEBUG: Executing MODE_REVERSAL logic");
        // M1 BUYシグナル発生時
        if(m1_signal == REVERSAL_BUY)
        {
            printf("DEBUG: MODE_REVERSAL - M1 BUY signal detected");
            if(position_type == POSITION_TYPE_SELL) // 売りポジションがあれば決済してドテン買い
            {
                printf("DEBUG: Closing SELL position and reversing to BUY");
                if(trade.PositionClose(_Symbol))
                {
                    DrawTradeObject(false, trade.ResultDeal());
                    if(trade.Buy(LotSize, _Symbol, 0, 0, 0, "HMA M1 Reverse to Buy"))
                        DrawTradeObject(true, trade.ResultDeal());
                }
            }
            else if(!position_exists) // ポジションがなければ新規買い
            {
                printf("DEBUG: Opening new BUY position");
                if(trade.Buy(LotSize, _Symbol, 0, 0, 0, "HMA M1 Reversal Buy"))
                    DrawTradeObject(true, trade.ResultDeal());
            }
        }
        // M1 SELLシグナル発生時
        else if(m1_signal == REVERSAL_SELL)
        {
            printf("DEBUG: MODE_REVERSAL - M1 SELL signal detected");
            if(position_type == POSITION_TYPE_BUY) // 買いポジションがあれば決済してドテン売り
            {
                printf("DEBUG: Closing BUY position and reversing to SELL");
                if(trade.PositionClose(_Symbol))
                {
                    DrawTradeObject(false, trade.ResultDeal());
                    if(trade.Sell(LotSize, _Symbol, 0, 0, 0, "HMA M1 Reverse to Sell"))
                        DrawTradeObject(true, trade.ResultDeal());
                }
            }
            else if(!position_exists) // ポジションがなければ新規売り
            {
                printf("DEBUG: Opening new SELL position");
                if(trade.Sell(LotSize, _Symbol, 0, 0, 0, "HMA M1 Reversal Sell"))
                    DrawTradeObject(true, trade.ResultDeal());
            }
        }
    }
    // --- MODE_REGULAR: M5トレンドフィルター売買 ---
    else 
    {
        printf("DEBUG: Executing MODE_REGULAR logic");
        // --- EXIT LOGIC ---
        if(position_exists)
        {
            bool should_close = false;
            // 買いポジションはM1売り転換 or M5トレンド下降で決済
            if(position_type == POSITION_TYPE_BUY && (m1_signal == REVERSAL_SELL || m5_trend == TREND_DOWN))
            {
                 should_close = true;
                 printf("DEBUG: Should close BUY position - M1 SELL signal or M5 DOWN trend");
            }
            // 売りポジションはM1買い転換 or M5トレンド上昇で決済
            else if(position_type == POSITION_TYPE_SELL && (m1_signal == REVERSAL_BUY || m5_trend == TREND_UP))
            {
                should_close = true;
                printf("DEBUG: Should close SELL position - M1 BUY signal or M5 UP trend");
            }

            if(should_close)
            {
                printf("DEBUG: Closing position");
                if(trade.PositionClose(_Symbol))
                {
                    DrawTradeObject(false, trade.ResultDeal());
                    position_exists = false; // 決済したのでステータスを更新
                }
            }
        }

        // --- ENTRY LOGIC (ポジションがない場合のみ) ---
        if(!position_exists)
        {
            printf("DEBUG: No position exists, checking for entry signals");
            // M5上昇トレンド中のM1買い転換でエントリー
            if(m5_trend == TREND_UP && m1_signal == REVERSAL_BUY)
            {
                printf("DEBUG: Opening BUY position - M5 UP trend + M1 BUY signal");
                if(trade.Buy(LotSize, _Symbol, 0, 0, 0, "HMA M1/M5 Buy"))
                    DrawTradeObject(true, trade.ResultDeal());
            }
            // M5下降トレンド中のM1売り転換でエントリー
            else if(m5_trend == TREND_DOWN && m1_signal == REVERSAL_SELL)
            {
                printf("DEBUG: Opening SELL position - M5 DOWN trend + M1 SELL signal");
                if(trade.Sell(LotSize, _Symbol, 0, 0, 0, "HMA M1/M5 Sell"))
                    DrawTradeObject(true, trade.ResultDeal());
            }
            else
            {
                printf("DEBUG: No entry conditions met - M5 trend: %s, M1 signal: %s", 
                       (m5_trend == TREND_UP ? "UP" : "DOWN"),
                       (m1_signal == REVERSAL_BUY ? "BUY" : m1_signal == REVERSAL_SELL ? "SELL" : "NONE"));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Draw Trade Object on Chart                                       |
//+------------------------------------------------------------------+
void DrawTradeObject(bool is_entry, ulong deal_ticket)
{
    if(!ShowTradeObjects) return;

    // --- 取引情報を取得 ---
    if(!HistoryDealSelect(deal_ticket)) return;

    double price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
    long type = HistoryDealGetInteger(deal_ticket, DEAL_TYPE); // DEAL_TYPE_BUY or DEAL_TYPE_SELL
    datetime time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
    ulong position_id = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);


    // --- オブジェクト名とテキストを作成 ---
    string obj_name = "TradeObj_" + (string)object_counter++;
    string obj_text;
    color obj_color;
    int arrow_code;

    if(is_entry)
    {
        obj_text = (type == DEAL_TYPE_BUY ? "BUY: #" : "SELL: #") + (string)position_id;
        obj_color = (type == DEAL_TYPE_BUY ? clrDodgerBlue : clrRed);
        arrow_code = (type == DEAL_TYPE_BUY ? 233 : 234);
    }
    else // is_exit
    {
        obj_text = "Close: #" + (string)position_id;
        obj_color = clrGray;
        arrow_code = 215;
    }

    // --- 矢印オブジェクトを作成 ---
    if(ObjectCreate(0, obj_name, OBJ_ARROW, 0, time, price))
    {
        ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, arrow_code);
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, obj_color);
        ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
        ObjectSetString(0, obj_name, OBJPROP_TEXT, obj_text);
        ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 8);
        ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, (type == DEAL_TYPE_BUY ? ANCHOR_BOTTOM : ANCHOR_TOP));
    }
}

//+------------------------------------------------------------------+
//| Handle trailing stop loss                                        |
//+------------------------------------------------------------------+
void DoTrailingStop()
{
    if(!UseTrailingStop)
        return;

    if(!PositionSelect(_Symbol))
        return;

    long position_type = PositionGetInteger(POSITION_TYPE);
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_price_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double current_price_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double activation_points = TS_ActivationPips * _Point;
    bool activated = false;
    if(position_type == POSITION_TYPE_BUY && (current_price_bid - open_price) > activation_points)
    {
        activated = true;
    }
    else if(position_type == POSITION_TYPE_SELL && (open_price - current_price_ask) > activation_points)
    {
        activated = true;
    }

    if(!activated)
        return;

    //--- Get confidence from indicator
    double confidence_buffer[];
    ArrayResize(confidence_buffer, 1);
    ArraySetAsSeries(confidence_buffer, true);
    double confidence_value = 0.0; // Default to minimum confidence on error
    if(CopyBuffer(m5_trend_handle, 5, 1, 1, confidence_buffer) > 0)
    {
        confidence_value = confidence_buffer[0];
    }
    else
    {
        printf("Error copying confidence buffer - using minimum ATR multiplier");
    }
    
    //--- Calculate dynamic ATR multiplier based on confidence
    double dynamic_multiplier = TS_AtrMultiplier_MIN + (TS_AtrMultiplier_MAX - TS_AtrMultiplier_MIN) * confidence_value;

    //--- Get ATR
    double atr[];
    ArrayResize(atr, 1);
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atr_handle, 0, 1, 1, atr) <= 0)
    {
        return;
    }

    double new_sl = 0;
    if(position_type == POSITION_TYPE_BUY)
    {
        new_sl = current_price_bid - (atr[0] * dynamic_multiplier);
    }
    else
    {
        new_sl = current_price_ask + (atr[0] * dynamic_multiplier);
    }
    
    new_sl = NormalizeDouble(new_sl, _Digits);

    bool should_modify = false;
    if(position_type == POSITION_TYPE_BUY && new_sl > current_sl)
    {
        should_modify = true;
    }
    else if(position_type == POSITION_TYPE_SELL && (new_sl < current_sl || current_sl == 0))
    {
        should_modify = true;
    }
    
    if(should_modify)
    {
        double current_tp = PositionGetDouble(POSITION_TP);
        trade.PositionModify(_Symbol, new_sl, current_tp);
    }
} 