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
input ulong    MagicNumber          = 98765;      // EAを識別するマジックナンバー
input double   LotSize              = 0.01;       // 固定ロットサイズ

//--- HMA & Trend Filter Settings
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
    hma_indicator_handle = iCustom(_Symbol, PERIOD_CURRENT, "hma_chart_plot",
                                   HMA_Period,          // Period
                                   false,               // ShowAlerts
                                   false,               // ShowArrows
                                   3,                   // ArrowSize
                                   false,               // ShowLabels
                                   8,                   // LabelFontSize
                                   clrNONE,             // EntryLabelColor
                                   clrNONE,             // ExitLabelColor
                                   14,                  // ADX_Period
                                   ADX_Threshold,       // ADX_Threshold
                                   14,                  // ATR_Period
                                   20,                  // MA_Period
                                   Volatility_Threshold,// Volatility_Threshold
                                   20,                  // BB_Period
                                   2.0,                 // BB_Deviation
                                   10                   // Trend_Strength_Period
                                   );

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

    //--- 2. Entry/Reversal logic (runs once per new bar)
    static datetime last_bar_time;
    datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, PERIOD_CURRENT, SERIES_LASTBAR_DATE);
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
    double hma_buffer[];
    double hma_colors[];
    double market_condition[];

    ArraySetAsSeries(hma_buffer, true);
    ArraySetAsSeries(hma_colors, true);
    ArraySetAsSeries(market_condition, true);

    //--- Get data from indicator buffers
    if(CopyBuffer(hma_indicator_handle, 0, 0, 3, hma_buffer) <= 0 ||
       CopyBuffer(hma_indicator_handle, 1, 0, 3, hma_colors) <= 0 ||
       CopyBuffer(hma_indicator_handle, 4, 0, 1, market_condition) <= 0)
    {
        printf("Error copying indicator buffers - error %d", GetLastError());
        return result;
    }

    //--- Determine trend and signal
    result.isTrending = (market_condition[0] == 1.0);

    bool is_up_trend = hma_colors[1] == 0;
    bool is_down_trend = hma_colors[1] == 1;
    bool prev_is_up_trend = hma_colors[2] == 0;
    bool prev_is_down_trend = hma_colors[2] == 1;

    if(is_up_trend && prev_is_down_trend)
    {
        result.signal = SIGNAL_BUY;
    }
    else if(is_down_trend && prev_is_up_trend)
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
        if(sig.isTrending && sig.signal != SIGNAL_NONE)
        {
            if(sig.signal == SIGNAL_BUY)
                trade.Buy(LotSize, _Symbol, 0, 0, 0, "HMA Buy");
            else if(sig.signal == SIGNAL_SELL)
                trade.Sell(LotSize, _Symbol, 0, 0, 0, "HMA Sell");
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
                trade.PositionClose(_Symbol);
                trade.Sell(LotSize, _Symbol, 0, 0, 0, "HMA Reverse to Sell");
            }
            else if(position_type == POSITION_TYPE_SELL && sig.signal == SIGNAL_BUY)
            {
                trade.PositionClose(_Symbol);
                trade.Buy(LotSize, _Symbol, 0, 0, 0, "HMA Reverse to Buy");
            }
        }
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
    double confidence_buffer[1];
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
    double atr[1];
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