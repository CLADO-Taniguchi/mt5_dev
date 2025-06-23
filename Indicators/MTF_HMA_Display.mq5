//+------------------------------------------------------------------+
//|                                        MTF_HMA_Display.mq5 |
//|                 Displays HMA data from a higher timeframe |
//|                                  Copyright 2024, Gemini |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Gemini"
#property version   "5.00" // Final Version, rebuilt from successful debug
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   3

//--- MTF Settings
input ENUM_TIMEFRAMES Source_Timeframe = PERIOD_M5;

//--- Source Indicator (hma_chart_plot) Parameters
input int HMA_Period = 21;
input int ADX_Period = 14;
input double ADX_Threshold = 25;
input int ATR_Period = 14;
input int MA_Period = 20;
input double Volatility_Threshold = 0.04;
input int BB_Period = 20;
input double BB_Deviation = 2.0;
input int Trend_Strength_Period = 10;

//--- Visual Settings
input int ArrowSize = 2;
input color Buy_Arrow_Color = clrDodgerBlue;
input color Sell_Arrow_Color = clrRed;

//--- Indicator Buffers
double hmaBuffer[];       // HMA Line
double hmaColors[];       // HMA Color
double buySignalBuffer[];   // BUY Arrow
double sellSignalBuffer[];  // SELL Arrow

//--- Indicator Handle
int hma_source_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    if(Period() >= Source_Timeframe)
    {
        Alert("エラー: 表示する時間足は、データソースの時間足（", TimeframeToString(Source_Timeframe), "）より小さくしてください。");
        return(INIT_FAILED);
    }
    
    //--- Buffer Mapping
    SetIndexBuffer(0, hmaBuffer,      INDICATOR_DATA);
    SetIndexBuffer(1, hmaColors,      INDICATOR_COLOR_INDEX);
    SetIndexBuffer(2, buySignalBuffer,  INDICATOR_DATA);
    SetIndexBuffer(3, sellSignalBuffer, INDICATOR_DATA);

    //--- Plot 0: HMA Line
    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_LINE);
    PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2); // 2 colors for the line
    PlotIndexSetInteger(0, PLOT_LINE_STYLE, STYLE_SOLID);
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 4); // Keep the thick line
    PlotIndexSetString(0, PLOT_LABEL, "HMA(" + TimeframeToString(Source_Timeframe) + ")");
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, clrLimeGreen);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, clrRed);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);

    //--- Plot 1: BUY Arrow
    PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW);
    PlotIndexSetInteger(1, PLOT_ARROW, 233);
    PlotIndexSetInteger(1, PLOT_LINE_COLOR, Buy_Arrow_Color);
    PlotIndexSetInteger(1, PLOT_LINE_WIDTH, ArrowSize);
    PlotIndexSetString(1, PLOT_LABEL, "BUY Signal");
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    //--- Plot 2: SELL Arrow
    PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
    PlotIndexSetInteger(2, PLOT_ARROW, 234);
    PlotIndexSetInteger(2, PLOT_LINE_COLOR, Sell_Arrow_Color);
    PlotIndexSetInteger(2, PLOT_LINE_WIDTH, ArrowSize);
    PlotIndexSetString(2, PLOT_LABEL, "SELL Signal");
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    
    //--- Get Handle
    hma_source_handle = iCustom(_Symbol, Source_Timeframe, "hma_chart_plot",
                                HMA_Period, ADX_Period, ADX_Threshold, ATR_Period, MA_Period,
                                Volatility_Threshold, BB_Period, BB_Deviation, Trend_Strength_Period);
    
    if(hma_source_handle == INVALID_HANDLE)
    {
        Alert("ソースインジケーター 'hma_chart_plot' のハンドル作成に失敗しました - エラー ", GetLastError());
        return(INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(hma_source_handle != INVALID_HANDLE)
        IndicatorRelease(hma_source_handle);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if(rates_total < 2 || hma_source_handle == INVALID_HANDLE)
        return(0);

    int start_bar = prev_calculated > 1 ? prev_calculated - 1 : 0;
    
    // Static variables to cache the last value from the higher timeframe
    static int last_source_shift = -1;
    static double cached_hma = 0.0;
    static double cached_color = 0;
    static double cached_buy = EMPTY_VALUE;
    static double cached_sell = EMPTY_VALUE;

    for(int i = start_bar; i < rates_total; i++)
    {
        int source_shift = iBarShift(_Symbol, Source_Timeframe, time[i]);
        if(source_shift < 0)
        {
            hmaBuffer[i] = cached_hma;
            hmaColors[i] = cached_color;
            continue;
        }

        if(source_shift != last_source_shift)
        {
            double hma_val[1], color_val[1], buy_val[1], sell_val[1];
            
            // Try to copy the data from the most recently completed bar (index 1)
            if(CopyBuffer(hma_source_handle, 0, 1, 1, hma_val) > 0 && hma_val[0] != 0.0)
            {
                CopyBuffer(hma_source_handle, 1, 1, 1, color_val);
                CopyBuffer(hma_source_handle, 2, 1, 1, buy_val);
                CopyBuffer(hma_source_handle, 3, 1, 1, sell_val);

                cached_hma  = hma_val[0];
                cached_color= color_val[0];
                cached_buy  = buy_val[0];
                cached_sell = sell_val[0];
            }
            last_source_shift = source_shift;
        }
        
        hmaBuffer[i] = cached_hma;
        hmaColors[i] = cached_color;

        datetime source_bar_time = iTime(_Symbol, Source_Timeframe, source_shift);
        if(time[i] == source_bar_time)
        {
            if(cached_buy == 1.0)
                buySignalBuffer[i] = low[i] - 10 * _Point;
            else
                buySignalBuffer[i] = EMPTY_VALUE;

            if(cached_sell == 1.0)
                sellSignalBuffer[i] = high[i] + 10 * _Point;
            else
                sellSignalBuffer[i] = EMPTY_VALUE;
        }
        else
        {
            buySignalBuffer[i] = EMPTY_VALUE;
            sellSignalBuffer[i] = EMPTY_VALUE;
        }
    }
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Convert timeframe enum to string                                 |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
    switch(tf)
    {
        case PERIOD_M1:  return "M1";
        case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN1";
        default:         return "Unknown";
    }
}
//+------------------------------------------------------------------+ 