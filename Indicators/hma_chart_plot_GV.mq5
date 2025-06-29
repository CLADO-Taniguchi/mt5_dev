#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   3 // HMAラインと売買シグナルのみ

// HMA設定
input int Period = 21;

// 市場状態判定設定
input int ADX_Period = 14;           // ADX期間
input double ADX_Threshold = 25;     // ADXトレンド閾値
input int ATR_Period = 14;           // ATR期間
input int MA_Period = 20;            // 移動平均期間
input double Volatility_Threshold = 0.04; // ボラティリティ閾値
input int BB_Period = 20;            // ボリンジャーバンド期間
input double BB_Deviation = 2.0;     // ボリンジャーバンド標準偏差
input int Trend_Strength_Period = 10; // トレンド強度期間

// バッファ
double hmaBuffer[];      // HMAライン
double hmaColors[];      // 色インデックス
double buySignalBuffer[]; // EAが読み取るBUYシグナル (非表示)
double sellSignalBuffer[];// EAが読み取るSELLシグナル (非表示)
double marketConditionBuffer[]; // 市場状態（0=レンジ, 1=トレンド）
double confidenceBuffer[]; // 信頼度
double volatilityRatioBuffer[]; // ボラティリティ比率

// インディケーターハンドル
int adx_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;
int ma_handle = INVALID_HANDLE;
int bb_handle = INVALID_HANDLE;

// 市場状態構造体
struct MarketCondition
{
    bool isTrending;
    double confidence;  // 0.0-1.0の信頼度
    string condition;   // 状態文字列
    double volatilityRatio; // ボラティリティ比率
};

int OnInit()
{
    // HMAライン設定
    SetIndexBuffer(0, hmaBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, hmaColors, INDICATOR_COLOR_INDEX);
    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_LINE);
    PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, clrLimeGreen);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, clrRed);
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2);
    PlotIndexSetString(0, PLOT_LABEL, "HMA Trend");

    // BUYシグナルバッファ (EA読み取り用、描画しない)
    SetIndexBuffer(2, buySignalBuffer, INDICATOR_DATA);
    PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);

    // SELLシグナルバッファ (EA読み取り用、描画しない)
    SetIndexBuffer(3, sellSignalBuffer, INDICATOR_DATA);
    PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
    
    // データバッファ
    SetIndexBuffer(4, marketConditionBuffer, INDICATOR_DATA);
    SetIndexBuffer(5, confidenceBuffer, INDICATOR_DATA);
    SetIndexBuffer(6, volatilityRatioBuffer, INDICATOR_DATA);

    // EMPTY_VALUE設定
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    // インディケーターハンドル初期化
    adx_handle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
    atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
    ma_handle = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
    bb_handle = iBands(_Symbol, PERIOD_CURRENT, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
    
    if(adx_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE || ma_handle == INVALID_HANDLE || bb_handle == INVALID_HANDLE)
    {
        printf("Error creating indicator handles");
        return(INIT_FAILED);
    }

    // 配列設定
    ArraySetAsSeries(hmaBuffer, false);
    ArraySetAsSeries(hmaColors, false);
    ArraySetAsSeries(buySignalBuffer, false);
    ArraySetAsSeries(sellSignalBuffer, false);
    ArraySetAsSeries(marketConditionBuffer, false);
    ArraySetAsSeries(confidenceBuffer, false);
    ArraySetAsSeries(volatilityRatioBuffer, false);
    
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    // ハンドル解放
    IndicatorRelease(adx_handle);
    IndicatorRelease(atr_handle);
    IndicatorRelease(ma_handle);
    IndicatorRelease(bb_handle);
}

// 市場状態分析関数（フォールバック処理付き）
MarketCondition AnalyzeMarketCondition(int shift)
{
    MarketCondition result;
    result.isTrending = false;
    result.confidence = 0.0;
    result.condition = "UNKNOWN";
    result.volatilityRatio = 0.0;
    
    // バー0の場合のフォールバック処理
    bool is_bar0 = (shift == 0);
    int fallback_shift = is_bar0 ? 1 : shift; // バー0で失敗したらバー1を使用
    
    // 1. ADX判定
    double adx[];
    ArraySetAsSeries(adx, false);
    ArrayResize(adx, 1);
    
    int adx_copied = CopyBuffer(adx_handle, 0, shift, 1, adx);
    if(adx_copied <= 0 && is_bar0) {
        // バー0で失敗した場合、バー1の値を使用
        adx_copied = CopyBuffer(adx_handle, 0, fallback_shift, 1, adx);
    }
    if(adx_copied <= 0) {
        // それでも失敗した場合、デフォルト値を設定
        adx[0] = 0.0;
    }
    
    bool adx_trending = adx[0] > ADX_Threshold;
    
    // 2. ボラティリティ判定
    double atr[];
    ArraySetAsSeries(atr, false);
    ArrayResize(atr, 1);
    
    int atr_copied = CopyBuffer(atr_handle, 0, shift, 1, atr);
    if(atr_copied <= 0 && is_bar0) {
        atr_copied = CopyBuffer(atr_handle, 0, fallback_shift, 1, atr);
    }
    if(atr_copied <= 0) {
        atr[0] = 0.0;
    }
    
    double ma[];
    ArraySetAsSeries(ma, false);
    ArrayResize(ma, 1);
    
    int ma_copied = CopyBuffer(ma_handle, 0, shift, 1, ma);
    if(ma_copied <= 0 && is_bar0) {
        ma_copied = CopyBuffer(ma_handle, 0, fallback_shift, 1, ma);
    }
    if(ma_copied <= 0) {
        ma[0] = 0.0;
    }
    
    double volatility_ratio = 0.0;
    if(ma[0] != 0.0)
    {
      volatility_ratio = atr[0] / ma[0] * 100;
    }
    bool volatility_trending = volatility_ratio > Volatility_Threshold;
    result.volatilityRatio = volatility_ratio;
    
    // 3. ボリンジャーバンド判定
    double bb_upper[], bb_lower[];
    ArraySetAsSeries(bb_upper, false);
    ArraySetAsSeries(bb_lower, false);
    ArrayResize(bb_upper, 1);
    ArrayResize(bb_lower, 1);
    
    int bb_upper_copied = CopyBuffer(bb_handle, 1, shift, 1, bb_upper);
    if(bb_upper_copied <= 0 && is_bar0) {
        bb_upper_copied = CopyBuffer(bb_handle, 1, fallback_shift, 1, bb_upper);
    }
    if(bb_upper_copied <= 0) {
        bb_upper[0] = 0.0;
    }
    
    int bb_lower_copied = CopyBuffer(bb_handle, 2, shift, 1, bb_lower);
    if(bb_lower_copied <= 0 && is_bar0) {
        bb_lower_copied = CopyBuffer(bb_handle, 2, fallback_shift, 1, bb_lower);
    }
    if(bb_lower_copied <= 0) {
        bb_lower[0] = 0.0;
    }
    
    double bb_width = bb_upper[0] - bb_lower[0];
    
    // ボリンジャーバンド幅の移動平均を計算
    double bb_width_array[];
    ArraySetAsSeries(bb_width_array, false);
    ArrayResize(bb_width_array, BB_Period + 1);
    
    for(int i = 0; i <= BB_Period; i++)
    {
        double upper[], lower[];
        ArraySetAsSeries(upper, false);
        ArraySetAsSeries(lower, false);
        ArrayResize(upper, 1);
        ArrayResize(lower, 1);
        
        int upper_copied = CopyBuffer(bb_handle, 1, shift + i, 1, upper);
        if(upper_copied <= 0 && is_bar0) {
            upper_copied = CopyBuffer(bb_handle, 1, fallback_shift + i, 1, upper);
        }
        if(upper_copied <= 0) {
            upper[0] = 0.0;
        }
        
        int lower_copied = CopyBuffer(bb_handle, 2, shift + i, 1, lower);
        if(lower_copied <= 0 && is_bar0) {
            lower_copied = CopyBuffer(bb_handle, 2, fallback_shift + i, 1, lower);
        }
        if(lower_copied <= 0) {
            lower[0] = 0.0;
        }
        
        bb_width_array[i] = upper[0] - lower[0];
    }
    
    double bb_width_ma = 0;
    for(int i = 0; i <= BB_Period; i++)
    {
        bb_width_ma += bb_width_array[i];
    }
    bb_width_ma /= (BB_Period + 1);
    
    bool bb_trending = bb_width > bb_width_ma * 1.2;
    
    // 4. 価格位置判定
    double close = iClose(_Symbol, PERIOD_CURRENT, shift);
    if(close == 0.0 && is_bar0) {
        close = iClose(_Symbol, PERIOD_CURRENT, fallback_shift);
    }
    
    double bb_position = 0.0;
    if(bb_upper[0] != bb_lower[0]) {
        bb_position = (close - bb_lower[0]) / (bb_upper[0] - bb_lower[0]);
    }
    bool price_extreme = bb_position < 0.2 || bb_position > 0.8;
    
    // 総合判定
    int trend_signals = 0;
    if(adx_trending) trend_signals++;
    if(volatility_trending) trend_signals++;
    if(bb_trending) trend_signals++;
    if(price_extreme) trend_signals++;
    
    result.isTrending = trend_signals >= 2;
    result.confidence = (double)trend_signals / 4.0;
    
    if(result.isTrending)
    {
        if(result.confidence >= 0.75) result.condition = "STRONG_TREND";
        else result.condition = "WEAK_TREND";
    }
    else
    {
        if(result.confidence <= 0.25) result.condition = "STRONG_RANGE";
        else result.condition = "WEAK_RANGE";
    }
    
    return result;
}

int OnCalculate(
    const int rates_total,
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
    if (rates_total < Period)
        return 0;

    // 初回のみバッファ初期化
    if(prev_calculated == 0)
    {
        ArrayInitialize(hmaBuffer, EMPTY_VALUE);
        ArrayInitialize(buySignalBuffer, EMPTY_VALUE);
        ArrayInitialize(sellSignalBuffer, EMPTY_VALUE);
        ArrayInitialize(hmaColors, EMPTY_VALUE);
        ArrayInitialize(marketConditionBuffer, EMPTY_VALUE);
        ArrayInitialize(confidenceBuffer, EMPTY_VALUE);
        ArrayInitialize(volatilityRatioBuffer, EMPTY_VALUE);
    }

    int sqrtPeriod = (int)MathSqrt(Period);
    double rawWMA[];
    ArrayResize(rawWMA, rates_total);
    ArraySetAsSeries(rawWMA, false);

    // 計算開始位置を必ず0にする
    int start = 0;
    for (int i = start; i < rates_total; i++)
    {
        if(i < Period) {
            hmaBuffer[i] = EMPTY_VALUE;
            hmaColors[i] = EMPTY_VALUE;
            buySignalBuffer[i] = EMPTY_VALUE;
            sellSignalBuffer[i] = EMPTY_VALUE;
            marketConditionBuffer[i] = EMPTY_VALUE;
            confidenceBuffer[i] = EMPTY_VALUE;
            volatilityRatioBuffer[i] = EMPTY_VALUE;
            continue;
        }
        // WMA計算（内側ループ削除）
        double wma_half = WMA(i, Period / 2, close);
        double wma_full = WMA(i, Period, close);
        rawWMA[i] = (wma_half != EMPTY_VALUE && wma_full != EMPTY_VALUE) ? 2 * wma_half - wma_full : EMPTY_VALUE;

        // HMA計算
        double hma_value = WMA(i, sqrtPeriod, rawWMA);
        hmaBuffer[i] = hma_value;
        
        // 市場状態分析は最新バーのみ
        if(i == rates_total - 1) {
            MarketCondition market = AnalyzeMarketCondition(i);
            marketConditionBuffer[i] = market.isTrending ? 1.0 : 0.0;
            confidenceBuffer[i] = market.confidence;
            volatilityRatioBuffer[i] = market.volatilityRatio;
        } else {
            marketConditionBuffer[i] = EMPTY_VALUE;
            confidenceBuffer[i] = EMPTY_VALUE;
            volatilityRatioBuffer[i] = EMPTY_VALUE;
        }
        
        // 色設定
        if (i > 0 && hmaBuffer[i] != EMPTY_VALUE && hmaBuffer[i - 1] != EMPTY_VALUE)
        {
            double dy = hmaBuffer[i] - hmaBuffer[i - 1];
            hmaColors[i] = (dy > 0) ? 0 : 1;
        }
        else if(i > 0) { 
            hmaColors[i] = hmaColors[i-1]; 
        }
        else { 
            hmaColors[i] = 1; 
        }
        
        // シグナル生成
        buySignalBuffer[i] = EMPTY_VALUE;
        sellSignalBuffer[i] = EMPTY_VALUE;
        
        if (i > 1 && hmaColors[i-1] != EMPTY_VALUE && hmaColors[i-2] != EMPTY_VALUE)
        {
            if(hmaColors[i-1] != hmaColors[i-2])
            {
                if(hmaColors[i-1] == 0) buySignalBuffer[i] = 1.0;
                else sellSignalBuffer[i] = 1.0;
            }
        }
    }

    // グローバル変数への書き出し（最新バーのみ）
    if(rates_total > 0)
    {
        int last_idx = rates_total - 1;
        string prefix = "GV." + _Symbol + "." + TimeframeToString(Period()) + ".";
        GlobalVariableSet(prefix + "HMA_Value", hmaBuffer[last_idx]);
        GlobalVariableSet(prefix + "HMA_Color", hmaColors[last_idx]);
        GlobalVariableSet(prefix + "Buy_Signal", buySignalBuffer[last_idx] == 1.0 ? 1.0 : 0.0);
        GlobalVariableSet(prefix + "Sell_Signal", sellSignalBuffer[last_idx] == 1.0 ? 1.0 : 0.0);
        GlobalVariableSet(prefix + "Last_Update", TimeCurrent());
    }
    return rates_total;
}

double WMA(int pos, int len, const double &data[])
{
    if(pos < len-1 || pos >= ArraySize(data)) return EMPTY_VALUE;
    double numerator = 0.0;
    double denominator = 0.0;
    for (int i = 0; i < len; i++)
    {
        int index = pos - i;
        if (index < 0 || index >= ArraySize(data)) break;
        double weight = len - i;
        numerator += data[index] * weight;
        denominator += weight;
    }
    return (denominator != 0.0) ? numerator / denominator : EMPTY_VALUE;
}

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