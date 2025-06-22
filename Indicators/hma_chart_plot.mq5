#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   6

// HMA設定
input int Period = 21;
input bool ShowAlerts = true;        // アラート表示
input bool ShowArrows = true;        // 矢印表示
input int ArrowSize = 3;            // 矢印サイズ
input bool ShowLabels = true;        // ラベル表示
input int LabelFontSize = 8;         // ラベルフォントサイズ
input color EntryLabelColor = clrWhite;   // エントリーラベル色
input color ExitLabelColor = clrWhite;     // エグジットラベル色

// 市場状態判定設定
input int ADX_Period = 14;           // ADX期間
input double ADX_Threshold = 25;     // ADXトレンド閾値
input int ATR_Period = 14;           // ATR期間
input int MA_Period = 20;            // 移動平均期間
input double Volatility_Threshold = 0.04; // ボラティリティ閾値 (EURUSD M5用に最適化)
input int BB_Period = 20;            // ボリンジャーバンド期間
input double BB_Deviation = 2.0;     // ボリンジャーバンド標準偏差
input int Trend_Strength_Period = 10; // トレンド強度期間

// バッファ
double hmaBuffer[];      // HMAライン
double hmaColors[];      // 色インデックス
double buySignalBuffer[]; // BUYシグナル
double sellSignalBuffer[]; // SELLシグナル
double marketConditionBuffer[]; // 市場状態（0=レンジ, 1=トレンド）
double confidenceBuffer[]; // 信頼度
double volatilityRatioBuffer[]; // ボラティリティ比率

// インディケーターハンドル
int adx_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;
int ma_handle = INVALID_HANDLE;
int bb_handle = INVALID_HANDLE;

// ENTRY/EXIT管理用変数
int entryCounter = 0;    // エントリーカウンター
int exitCounter = 0;     // エグジットカウンター
bool hasOpenPosition = false; // ポジション保有状態

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
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, clrLimeGreen);  // 上昇トレンド
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, clrRed);        // 下降トレンド
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 3);
    PlotIndexSetString(0, PLOT_LABEL, "HMA Trend");

    // BUYシグナル設定
    SetIndexBuffer(2, buySignalBuffer, INDICATOR_DATA);
    PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW);
    PlotIndexSetInteger(1, PLOT_ARROW, 233);  // 上向き矢印
    PlotIndexSetInteger(1, PLOT_LINE_COLOR, clrBlue);
    PlotIndexSetInteger(1, PLOT_LINE_WIDTH, ArrowSize);
    PlotIndexSetString(1, PLOT_LABEL, "BUY Signal");

    // SELLシグナル設定
    SetIndexBuffer(3, sellSignalBuffer, INDICATOR_DATA);
    PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
    PlotIndexSetInteger(2, PLOT_ARROW, 234);  // 下向き矢印
    PlotIndexSetInteger(2, PLOT_LINE_COLOR, clrRed);
    PlotIndexSetInteger(2, PLOT_LINE_WIDTH, ArrowSize);
    PlotIndexSetString(2, PLOT_LABEL, "SELL Signal");

    // 市場状態設定
    SetIndexBuffer(4, marketConditionBuffer, INDICATOR_DATA);
    PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_NONE);
    PlotIndexSetString(3, PLOT_LABEL, "Market Condition");

    // 信頼度設定
    SetIndexBuffer(5, confidenceBuffer, INDICATOR_DATA);
    PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
    PlotIndexSetString(4, PLOT_LABEL, "Confidence");

    // ボラティリティ比率設定
    SetIndexBuffer(6, volatilityRatioBuffer, INDICATOR_DATA);
    PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE);
    PlotIndexSetString(5, PLOT_LABEL, "Volatility Ratio");

    // インディケーターハンドル初期化
    adx_handle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
    atr_handle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
    ma_handle = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
    bb_handle = iBands(_Symbol, PERIOD_CURRENT, BB_Period, BB_Deviation, 0, PRICE_CLOSE);
    
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

    // バッファを空の値で初期化
    ArrayInitialize(buySignalBuffer, EMPTY_VALUE);
    ArrayInitialize(sellSignalBuffer, EMPTY_VALUE);
    ArrayInitialize(marketConditionBuffer, EMPTY_VALUE);
    ArrayInitialize(confidenceBuffer, EMPTY_VALUE);
    ArrayInitialize(volatilityRatioBuffer, EMPTY_VALUE);
    
    // カウンター初期化
    entryCounter = 0;
    exitCounter = 0;
    hasOpenPosition = false;

    return INIT_SUCCEEDED;
}

// インディケーター終了時にオブジェクト削除
void OnDeinit(const int reason)
{
    // ハンドル解放
    IndicatorRelease(adx_handle);
    IndicatorRelease(atr_handle);
    IndicatorRelease(ma_handle);
    IndicatorRelease(bb_handle);

    // すべてのE_とX_ラベルを削除
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
    {
        string objName = ObjectName(0, i);
        if(StringFind(objName, "E_") == 0 || StringFind(objName, "X_") == 0)
        {
            ObjectDelete(0, objName);
        }
    }
}

// 市場状態分析関数
MarketCondition AnalyzeMarketCondition(int shift)
{
    MarketCondition result;
    result.isTrending = false;
    result.confidence = 0.0;
    result.condition = "UNKNOWN";
    result.volatilityRatio = 0.0;
    
    // 1. ADX判定
    double adx[];
    ArraySetAsSeries(adx, false);
    ArrayResize(adx, 1);
    if(CopyBuffer(adx_handle, 0, shift, 1, adx) <= 0) return result;
    bool adx_trending = adx[0] > ADX_Threshold;
    
    // 2. ボラティリティ判定
    double atr[];
    ArraySetAsSeries(atr, false);
    ArrayResize(atr, 1);
    if(CopyBuffer(atr_handle, 0, shift, 1, atr) <= 0) return result;
    
    double ma[];
    ArraySetAsSeries(ma, false);
    ArrayResize(ma, 1);
    if(CopyBuffer(ma_handle, 0, shift, 1, ma) <= 0) return result;
    
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
    if(CopyBuffer(bb_handle, 1, shift, 1, bb_upper) <= 0) return result; // UPPER
    if(CopyBuffer(bb_handle, 2, shift, 1, bb_lower) <= 0) return result; // LOWER
    
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
        if(CopyBuffer(bb_handle, 1, shift + i, 1, upper) <= 0) continue;
        if(CopyBuffer(bb_handle, 2, shift + i, 1, lower) <= 0) continue;
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
    double bb_position = (close - bb_lower[0]) / (bb_upper[0] - bb_lower[0]);
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
    if (rates_total < Period + 2)
        return 0;

    ArraySetAsSeries(close, false);
    ArraySetAsSeries(high, false);
    ArraySetAsSeries(low, false);
    ArraySetAsSeries(time, false);

    int sqrtPeriod = (int)MathSqrt(Period);
    double rawWMA[];
    ArrayResize(rawWMA, rates_total);
    ArraySetAsSeries(rawWMA, false);

    // 中間WMA計算
    for (int i = Period - 1; i < rates_total; i++)
    {
        double wma_half = WMA(i, Period / 2, close);
        double wma_full = WMA(i, Period, close);
        rawWMA[i] = 2 * wma_half - wma_full;
    }

    // 計算開始位置を決定
    int start_pos = MathMax(prev_calculated - 1, (int)MathMax(Period - 1, sqrtPeriod - 1));
    if (start_pos < 1) start_pos = 1;

    // HMA本体とシグナル計算
    for (int i = start_pos; i < rates_total; i++)
    {
        hmaBuffer[i] = WMA(i, sqrtPeriod, rawWMA);

        // 市場状態分析
        int copy_shift = rates_total - 1 - i;
        MarketCondition market = AnalyzeMarketCondition(copy_shift);
        marketConditionBuffer[i] = market.isTrending ? 1.0 : 0.0;
        confidenceBuffer[i] = market.confidence;
        volatilityRatioBuffer[i] = market.volatilityRatio;

        // トレンド方向を判定
        if (i > 0 && hmaBuffer[i] != 0.0 && hmaBuffer[i - 1] != 0.0)
        {
            double dy = hmaBuffer[i] - hmaBuffer[i - 1];
            int currentTrend = (dy > 0) ? 0 : 1;  // 0=上昇, 1=下降
            hmaColors[i] = currentTrend;

            // シグナル検出（トレンド反転時）
            if (i > 1 && hmaBuffer[i - 2] != 0.0)
            {
                double prev_dy = hmaBuffer[i - 1] - hmaBuffer[i - 2];
                int prevTrend = (prev_dy > 0) ? 0 : 1;

                // トレンド反転チェック
                if (currentTrend != prevTrend)
                {
                    string labelName = "";
                    string labelText = "";
                    color labelColor = clrWhite;  // 初期化
                    double labelPrice = 0.0;      // 初期化
                    bool shouldTrade = false;
                    bool signalFired = false;     // シグナル発生フラグ
                    
                    // 市場状態に基づく取引判断
                    if(market.isTrending && market.confidence > 0.5)
                    {
                        shouldTrade = true;
                    }
                    
                    if (!hasOpenPosition && shouldTrade)
                    {
                        // 新規エントリー（トレンド相場のみ）
                        entryCounter++;
                        labelName = "E_" + IntegerToString(entryCounter);
                        labelText = "E_" + IntegerToString(entryCounter) + "(" + market.condition + ")";
                        hasOpenPosition = true;
                        signalFired = true;
                        
                        if (currentTrend == 0)  // BUYエントリー
                        {
                            buySignalBuffer[i] = low[i] - (high[i] - low[i]) * 0.3;
                            sellSignalBuffer[i] = EMPTY_VALUE;
                            labelPrice = low[i] - (high[i] - low[i]) * 0.5;
                            labelColor = EntryLabelColor;
                            
                            if (ShowAlerts && i == rates_total - 1)
                            {
                                Alert("HMA BUY Entry E_", entryCounter, " (", market.condition, ") at ", _Symbol);
                            }
                        }
                        else  // SELLエントリー
                        {
                            sellSignalBuffer[i] = high[i] + (high[i] - low[i]) * 0.3;
                            buySignalBuffer[i] = EMPTY_VALUE;
                            labelPrice = high[i] + (high[i] - low[i]) * 0.5;
                            labelColor = EntryLabelColor;
                            
                            if (ShowAlerts && i == rates_total - 1)
                            {
                                Alert("HMA SELL Entry E_", entryCounter, " (", market.condition, ") at ", _Symbol);
                            }
                        }
                    }
                    else if (hasOpenPosition)
                    {
                        // ポジション決済（市場状態に関係なく）
                        exitCounter++;
                        labelName = "X_" + IntegerToString(exitCounter);
                        labelText = "X_" + IntegerToString(exitCounter) + "(" + market.condition + ")";
                        hasOpenPosition = false;
                        signalFired = true;
                        
                        if (currentTrend == 0)  // BUYシグナルで決済（前のSELLポジション決済）
                        {
                            buySignalBuffer[i] = low[i] - (high[i] - low[i]) * 0.3;
                            sellSignalBuffer[i] = EMPTY_VALUE;
                            labelPrice = high[i] + (high[i] - low[i]) * 0.8;
                            labelColor = ExitLabelColor;
                            
                            if (ShowAlerts && i == rates_total - 1)
                            {
                                Alert("HMA EXIT X_", exitCounter, " (", market.condition, ") at ", _Symbol);
                            }
                        }
                        else  // SELLシグナルで決済（前のBUYポジション決済）
                        {
                            sellSignalBuffer[i] = high[i] + (high[i] - low[i]) * 0.3;
                            buySignalBuffer[i] = EMPTY_VALUE;
                            labelPrice = low[i] - (high[i] - low[i]) * 0.8;
                            labelColor = ExitLabelColor;
                            
                            if (ShowAlerts && i == rates_total - 1)
                            {
                                Alert("HMA EXIT X_", exitCounter, " (", market.condition, ") at ", _Symbol);
                            }
                        }
                    }
                    else
                    {
                        // レンジ相場でエントリーしない場合
                        buySignalBuffer[i] = EMPTY_VALUE;
                        sellSignalBuffer[i] = EMPTY_VALUE;
                    }
                    
                    // ラベル作成
                    if (ShowLabels && signalFired)
                    {
                        ObjectCreate(0, labelName, OBJ_TEXT, 0, time[i], labelPrice);
                        ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
                        ObjectSetInteger(0, labelName, OBJPROP_COLOR, labelColor);
                        ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, LabelFontSize);
                        ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_CENTER);
                        ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
                        ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
                        ObjectSetInteger(0, labelName, OBJPROP_HIDDEN, true);
                    }
                }
                else
                {
                    buySignalBuffer[i] = EMPTY_VALUE;
                    sellSignalBuffer[i] = EMPTY_VALUE;
                }
            }
        }
        else
        {
            hmaColors[i] = 1;  // 安全側
            buySignalBuffer[i] = EMPTY_VALUE;
            sellSignalBuffer[i] = EMPTY_VALUE;
        }
    }

    return rates_total;
}

double WMA(int pos, int len, const double &data[])
{
    double numerator = 0.0;
    double denominator = 0.0;
    for (int i = 0; i < len; i++)
    {
        int index = pos - i;
        if (index < 0) break;
        double weight = len - i;
        numerator += data[index] * weight;
        denominator += weight;
    }
    return (denominator != 0.0) ? numerator / denominator : 0.0;
}