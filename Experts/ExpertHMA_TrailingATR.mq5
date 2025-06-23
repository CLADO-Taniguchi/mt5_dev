//+------------------------------------------------------------------+
//|                                     ExpertHMA_TrailingATR.mq5 |
//|                                  Copyright 2023, MetaQuotes Ltd |
//|                                              https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- EA Settings
input ulong    MagicNumber          = 12345;      // EAを識別するマジックナンバー
input double   LotSize              = 0.01;       // 固定ロットサイズ
input bool     ShowTradeObjects     = true;       // 取引オブジェクトをチャートに表示するか

//--- HMA & Trend Filter Settings
input ENUM_TIMEFRAMES HMA_Timeframe = PERIOD_M5;  // HMAを計算する時間足
input int      HMA_Period           = 21;         // HMAの期間
input double   ADX_Threshold        = 25.0;       // トレンド判定のADXしきい値
input double   Volatility_Threshold = 0.04;       // ボラティリティしきい値

//--- Trading Logic
input bool     AllowReverseTrade    = true;       // ドテン売買を許可するか

//--- Trailing Stop Settings
input bool     UseTrailingStop      = true;       // トレーリングストップを使用するか
input double   TS_AtrMultiplier_MIN = 1.5;        // レンジ相場でのATR係数（最小値）
input double   TS_AtrMultiplier_MAX = 3.5;        // トレンド相場でのATR係数（最大値）
input double   TS_ActivationPips    = 10.0;       // トレーリングストップが有効になる利益幅 (Pips)

//--- Global variables
CTrade trade;
int    hma_indicator_handle;
int    atr_handle;
long   object_counter = 0; // オブジェクト名を一意にするためのカウンター

//--- Signal enumeration
enum ENUM_SIGNAL
{
    SIGNAL_NONE,
    SIGNAL_BUY,
    SIGNAL_SELL
};

//--- Struct for Signal Info
struct SignalInfo
{
    ENUM_SIGNAL signal;
    bool        isTrending;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Initialize trade object
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetMarginMode();

    //--- Initialize HMA indicator
    hma_indicator_handle = iCustom(_Symbol, HMA_Timeframe, "hma_chart_plot",
                                   HMA_Period, 14, ADX_Threshold, 14, 20, Volatility_Threshold, 20, 2.0, 10);

    if(hma_indicator_handle == INVALID_HANDLE)
    {
        printf("Error creating HMA indicator handle - error %d", GetLastError());
        return(INIT_FAILED);
    }
    
    //--- Initialize ATR indicator for trailing stop
    atr_handle = iATR(_Symbol, PERIOD_CURRENT, 14);
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
    IndicatorRelease(hma_indicator_handle);
    IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- 1. Trailing Stop logic (runs on every tick)
    DoTrailingStop();

    //--- 2. Entry/Reversal logic (runs once per new bar on the HMA_Timeframe)
    static datetime last_bar_time;
    datetime current_bar_time = iTime(_Symbol, HMA_Timeframe, 0);
    if(last_bar_time >= current_bar_time)
    {
        return; // Not a new bar yet
    }
    last_bar_time = current_bar_time;

    //--- Get the latest signal
    SignalInfo current_signal = CalculateSignal();

    //--- If no signal, no entry/reverse action
    if(current_signal.signal == SIGNAL_NONE)
        return;
        
    //--- Execute trading logic
    TradeEntryAndReverse(current_signal);
}

//+------------------------------------------------------------------+
//| Calculate signal based on the custom indicator                   |
//+------------------------------------------------------------------+
SignalInfo CalculateSignal()
{
    SignalInfo result;
    result.signal = SIGNAL_NONE;
    result.isTrending = false;

    //--- Buffers for indicator data
    double buy_signal_buffer[];
    double sell_signal_buffer[];
    double market_condition[];

    ArraySetAsSeries(buy_signal_buffer, true);
    ArraySetAsSeries(sell_signal_buffer, true);
    ArraySetAsSeries(market_condition, true);

    //--- Get data from indicator buffers
    if(CopyBuffer(hma_indicator_handle, 2, 0, 2, buy_signal_buffer) <= 0 ||
       CopyBuffer(hma_indicator_handle, 3, 0, 2, sell_signal_buffer) <= 0 ||
       CopyBuffer(hma_indicator_handle, 4, 0, 1, market_condition) <= 0)
    {
        printf("Error copying indicator buffers - error %d", GetLastError());
        return result;
    }

    //--- Determine trend and signal
    result.isTrending = (market_condition[0] == 1.0);

    if(buy_signal_buffer[1] == 1.0)
    {
        result.signal = SIGNAL_BUY;
    }
    else if(sell_signal_buffer[1] == 1.0)
    {
        result.signal = SIGNAL_SELL;
    }

    return result;
}

//+------------------------------------------------------------------+
//| Handle position entry and reversals                              |
//+------------------------------------------------------------------+
void TradeEntryAndReverse(const SignalInfo &sig)
{
    bool position_exists = PositionSelect(_Symbol);
    
    // --- NO POSITION ---
    if(!position_exists)
    {
        if(sig.signal == SIGNAL_BUY)
        {
            if(trade.Buy(LotSize, _Symbol, 0, 0, 0, "HMA Buy"))
                DrawTradeObject(true, trade.ResultDeal());
        }
        else if(sig.signal == SIGNAL_SELL)
        {
            if(trade.Sell(LotSize, _Symbol, 0, 0, 0, "HMA Sell"))
                DrawTradeObject(true, trade.ResultDeal());
        }
    }
    // --- POSITION EXISTS ---
    else 
    {
        if(AllowReverseTrade)
        {
            long position_type = PositionGetInteger(POSITION_TYPE);
            
            if(position_type == POSITION_TYPE_BUY && sig.signal == SIGNAL_SELL)
            {
                if(trade.PositionClose(_Symbol))
                {
                    DrawTradeObject(false, trade.ResultDeal());
                    if(trade.Sell(LotSize, _Symbol, 0, 0, 0, "HMA Reverse to Sell"))
                        DrawTradeObject(true, trade.ResultDeal());
                }
            }
            else if(position_type == POSITION_TYPE_SELL && sig.signal == SIGNAL_BUY)
            {
                if(trade.PositionClose(_Symbol))
                {
                    DrawTradeObject(false, trade.ResultDeal());
                    if(trade.Buy(LotSize, _Symbol, 0, 0, 0, "HMA Reverse to Buy"))
                        DrawTradeObject(true, trade.ResultDeal());
                }
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
    if(CopyBuffer(hma_indicator_handle, 5, 1, 1, confidence_buffer) > 0)
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