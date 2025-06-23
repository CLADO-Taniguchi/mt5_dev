//+------------------------------------------------------------------+
//|                                     MTF_HMA_Display.mq5 |
//|        Displays HMA data from a higher timeframe (Robust) |
//|                                         Copyright 2024, Gemini |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Gemini"
#property version   "8.00" // Final, documented version
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   3

//--- MTF Settings
input ENUM_TIMEFRAMES Source_Timeframe = PERIOD_M5;

//--- Source Indicator (hma_chart_plot) Parameters
// This needs to match the parameters of the target indicator
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

    // --- [IMPORTANT SPEC 1] Robust History Loading ---
    // iCustomで高位時間足のデータを要求する際、ターミナルにその時間足のデータがまだ無い場合にエラー4806が発生する。
    // これを防ぐため、iCustomハンドルを作成する前に、対象時間足のデータが利用可能になるまでループで意図的に待機する。
    // これにより、iCustom呼び出しとデータダウンロードの間の競合状態（レースコンディション）を回避する。
    int attempts = 0;
    while(SeriesInfoInteger(_Symbol, Source_Timeframe, SERIES_BARS_COUNT) < 2 && attempts < 20)
    {
        Sleep(500); // 0.5秒待機
        // この関数を呼び出すこと自体が、サーバーへのデータ要求をトリガーする助けとなる。
        SeriesInfoInteger(_Symbol, Source_Timeframe, SERIES_BARS_COUNT);
        attempts++;
    }

    if(attempts >= 20)
    {
        Alert("MTF Display: Failed to load history for ", _Symbol, " ", TimeframeToString(Source_Timeframe), ". Please try loading the chart manually.");
        return(INIT_FAILED);
    }
    //--------------------------------

    //--- Get Handle for the source indicator
    hma_source_handle = iCustom(_Symbol, Source_Timeframe, "hma_chart_plot",
                                HMA_Period, ADX_Period, ADX_Threshold, ATR_Period, MA_Period,
                                Volatility_Threshold, BB_Period, BB_Deviation, Trend_Strength_Period);
    
    if(hma_source_handle == INVALID_HANDLE)
    {
        Alert("ソースインジケーター 'hma_chart_plot' のハンドル作成に失敗しました - エラー ", GetLastError());
        return(INIT_FAILED);
    }

    //--- Buffer Mapping
    SetIndexBuffer(0, hmaBuffer,      INDICATOR_DATA);
    SetIndexBuffer(1, hmaColors,      INDICATOR_COLOR_INDEX);
    SetIndexBuffer(2, buySignalBuffer,  INDICATOR_DATA);
    SetIndexBuffer(3, sellSignalBuffer, INDICATOR_DATA);

    //--- Plot 0: HMA Line
    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_LINE);
    PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);
    PlotIndexSetInteger(0, PLOT_LINE_STYLE, STYLE_SOLID);
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 4);
    PlotIndexSetString(0, PLOT_LABEL, "HMA(" + TimeframeToString(Source_Timeframe) + ")");
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, clrLimeGreen);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, clrRed);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);

    //--- Plot 1: BUY Arrow
    PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW);
    PlotIndexSetString(1, PLOT_LABEL, "BUY Signal");
    PlotIndexSetInteger(1, PLOT_ARROW, 233);
    PlotIndexSetInteger(1, PLOT_LINE_COLOR, Buy_Arrow_Color);
    PlotIndexSetInteger(1, PLOT_LINE_WIDTH, ArrowSize);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    
    //--- Plot 2: SELL Arrow
    PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
    PlotIndexSetString(2, PLOT_LABEL, "SELL Signal");
    PlotIndexSetInteger(2, PLOT_ARROW, 234);
    PlotIndexSetInteger(2, PLOT_LINE_COLOR, Sell_Arrow_Color);
    PlotIndexSetInteger(2, PLOT_LINE_WIDTH, ArrowSize);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    
    // --- [IMPORTANT SPEC 2] Set Array Indexing Direction ---
    // インジケーターバッファの配列の向きを、OnCalculateの計算ループと一致させることが極めて重要。
    // OnCalculateの for(int i=...; i<rates_total; i++) というループは、古いデータ(インデックス小)から新しいデータ(インデックス大)へと進む。
    // よって、バッファの向きも ArraySetAsSeries(..., false) に設定し、「通常の配列」として扱う。
    // もしここを true (時系列配列) にすると、データがバッファの逆側から書き込まれ、チャートに何も表示されなくなる。
    ArraySetAsSeries(hmaBuffer, false);
    ArraySetAsSeries(hmaColors, false);
    ArraySetAsSeries(buySignalBuffer, false);
    ArraySetAsSeries(sellSignalBuffer, false);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(hma_source_handle != INVALID_HANDLE)
        IndicatorRelease(hma_source_handle);
    Print("MTF Display Deinitialized. Reason: ", reason);
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

    // Determine how many bars need to be calculated
    int bars_to_process = rates_total - prev_calculated;
    if (prev_calculated > 0)
        bars_to_process++;
        
    // A limit to prevent excessive history calculation on first run
    int limit = 5000; 
    if(bars_to_process > limit) bars_to_process = limit;

    // Set the starting bar for the loop
    int start_bar = rates_total - bars_to_process;
    if(start_bar < 1) start_bar = 1;

    //--- Get data from the source indicator ---
    datetime mtf_time[];
    double mtf_hma[], mtf_color[], mtf_buy[], mtf_sell[];

    // Ensure we have enough data on the source timeframe
    int mtf_bars = (int)SeriesInfoInteger(_Symbol, Source_Timeframe, SERIES_BARS_COUNT);
    if(mtf_bars < 2) return(0);

    // Copy all available data from the source indicator
    if(CopyTime(_Symbol, Source_Timeframe, 0, mtf_bars, mtf_time) < 1) return (0);
    if(CopyBuffer(hma_source_handle, 0, 0, mtf_bars, mtf_hma) < 1) return(0);
    if(CopyBuffer(hma_source_handle, 1, 0, mtf_bars, mtf_color) < 1) return(0);
    if(CopyBuffer(hma_source_handle, 2, 0, mtf_bars, mtf_buy) < 1) return(0);
    if(CopyBuffer(hma_source_handle, 3, 0, mtf_bars, mtf_sell) < 1) return(0);
    
    // CopyBufferから取得したデータは、デフォルトで「時系列配列」(新しい→古い) になっている。
    // iBarShiftで正しくインデックスを引くために、向きを明示的に時系列に設定しておく。
    ArraySetAsSeries(mtf_time, true);
    ArraySetAsSeries(mtf_hma, true);
    ArraySetAsSeries(mtf_color, true);
    ArraySetAsSeries(mtf_buy, true);
    ArraySetAsSeries(mtf_sell, true);

    //--- Map the MTF data to the current chart bars ---
    for(int i = start_bar; i < rates_total; i++)
    {
        // --- [IMPORTANT SPEC 3] Time-axis Synchronization ---
        // iBarShift()を使い、現在のチャート(M1)のバー(i)の時刻が、
        // データソースのチャート(M5)では何本前のバー(mtf_index)に該当するかを計算する。
        // これにより、異なる時間足のデータを正しい位置にマッピングする。
        int mtf_index = iBarShift(_Symbol, Source_Timeframe, time[i]);
        if(mtf_index >= mtf_bars || mtf_index < 0) continue;

        hmaBuffer[i] = mtf_hma[mtf_index];
        hmaColors[i] = mtf_color[mtf_index];
        
        // --- [IMPORTANT SPEC 4] Disable Arrow Objects ---
        // M1チャートでは矢印オブジェクトが大量に生成されるため、すべてEMPTY_VALUEに設定
        // HMAラインの表示のみを維持し、矢印は表示しない
        buySignalBuffer[i] = EMPTY_VALUE;
        sellSignalBuffer[i] = EMPTY_VALUE;
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