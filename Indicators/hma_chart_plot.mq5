#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   3

input int Period = 21;
input bool ShowAlerts = true;        // アラート表示
input bool ShowArrows = true;        // 矢印表示
input int ArrowSize = 3;            // 矢印サイズ
input bool ShowLabels = true;        // ラベル表示
input int LabelFontSize = 8;         // ラベルフォントサイズ
input color EntryLabelColor = clrWhite;   // エントリーラベル色
input color ExitLabelColor = clrWhite;     // エグジットラベル色

// HMA角度フィルター設定
input bool UseAngleFilter = true;    // 角度フィルター使用
input double MinAngle = 0.5;         // 最小角度（度）
input int AnglePeriod = 3;           // 角度計算期間
input bool ShowAngleInAlert = true;  // アラートに角度表示

double hmaBuffer[];      // HMAライン
double hmaColors[];      // 色インデックス
double buySignalBuffer[]; // BUYシグナル
double sellSignalBuffer[]; // SELLシグナル

// ENTRY/EXIT管理用変数
int entryCounter = 0;    // エントリーカウンター
int exitCounter = 0;     // エグジットカウンター
bool hasOpenPosition = false; // ポジション保有状態

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

    // 配列設定
    ArraySetAsSeries(hmaBuffer, false);
    ArraySetAsSeries(hmaColors, false);
    ArraySetAsSeries(buySignalBuffer, false);
    ArraySetAsSeries(sellSignalBuffer, false);

    // バッファを空の値で初期化
    ArrayInitialize(buySignalBuffer, EMPTY_VALUE);
    ArrayInitialize(sellSignalBuffer, EMPTY_VALUE);
    
    // カウンター初期化
    entryCounter = 0;
    exitCounter = 0;
    hasOpenPosition = false;

    return INIT_SUCCEEDED;
}

// インディケーター終了時にオブジェクト削除
void OnDeinit(const int reason)
{
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
                    // HMA角度フィルターチェック
                    bool trendingNow = IsTrending(i);
                    
                    if (trendingNow)  // 角度が十分にある場合のみシグナル生成
                    {
                        string labelName = "";
                        string labelText = "";
                        color labelColor;
                        double labelPrice;
                        
                        if (!hasOpenPosition)
                        {
                            // 新規エントリー
                            entryCounter++;
                            labelName = "E_" + IntegerToString(entryCounter);
                            labelText = "E_" + IntegerToString(entryCounter);
                            hasOpenPosition = true;
                            
                            if (currentTrend == 0)  // BUYエントリー
                            {
                                buySignalBuffer[i] = low[i] - (high[i] - low[i]) * 0.3;
                                sellSignalBuffer[i] = EMPTY_VALUE;
                                labelPrice = low[i] - (high[i] - low[i]) * 0.5;
                                labelColor = EntryLabelColor;
                                
                                if (ShowAngleInAlert && ShowAlerts && i == rates_total - 1)
                                {
                                    double angle = CalculateHMAAngle(i);
                                    Alert("HMA BUY Entry E_", entryCounter, " - Angle: ", DoubleToString(angle, 2), "° (Min:", DoubleToString(MinAngle, 1), "°)");
                                }
                            }
                            else  // SELLエントリー
                            {
                                sellSignalBuffer[i] = high[i] + (high[i] - low[i]) * 0.3;
                                buySignalBuffer[i] = EMPTY_VALUE;
                                labelPrice = high[i] + (high[i] - low[i]) * 0.5;
                                labelColor = EntryLabelColor;
                                
                                if (ShowAngleInAlert && ShowAlerts && i == rates_total - 1)
                                {
                                    double angle = CalculateHMAAngle(i);
                                    Alert("HMA SELL Entry E_", entryCounter, " - Angle: ", DoubleToString(angle, 2), "° (Min:", DoubleToString(MinAngle, 1), "°)");
                                }
                            }
                        }
                        else
                        {
                            // ポジション決済
                            exitCounter++;
                            labelName = "X_" + IntegerToString(exitCounter);
                            labelText = "X_" + IntegerToString(exitCounter);
                            hasOpenPosition = false;
                            
                            if (currentTrend == 0)  // BUYシグナルで決済（前のSELLポジション決済）
                            {
                                buySignalBuffer[i] = low[i] - (high[i] - low[i]) * 0.3;
                                sellSignalBuffer[i] = EMPTY_VALUE;
                                labelPrice = low[i] - (high[i] - low[i]) * 0.5;
                                labelColor = ExitLabelColor;
                                
                                if (ShowAngleInAlert && ShowAlerts && i == rates_total - 1)
                                {
                                    double angle = CalculateHMAAngle(i);
                                    Alert("HMA Exit X_", exitCounter, " - Angle: ", DoubleToString(angle, 2), "° (Min:", DoubleToString(MinAngle, 1), "°)");
                                }
                            }
                            else  // SELLシグナルで決済（前のBUYポジション決済）
                            {
                                sellSignalBuffer[i] = high[i] + (high[i] - low[i]) * 0.3;
                                buySignalBuffer[i] = EMPTY_VALUE;
                                labelPrice = high[i] + (high[i] - low[i]) * 0.5;
                                labelColor = ExitLabelColor;
                                
                                if (ShowAngleInAlert && ShowAlerts && i == rates_total - 1)
                                {
                                    double angle = CalculateHMAAngle(i);
                                    Alert("HMA Exit X_", exitCounter, " - Angle: ", DoubleToString(angle, 2), "° (Min:", DoubleToString(MinAngle, 1), "°)");
                                }
                            }
                            
                            // すぐに新規エントリー開始
                            entryCounter++;
                            hasOpenPosition = true;
                        }
                        
                        // ラベル作成
                        if (ShowLabels)
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
                        // 角度が不十分（横向き）の場合はシグナルをスキップ
                        buySignalBuffer[i] = EMPTY_VALUE;
                        sellSignalBuffer[i] = EMPTY_VALUE;
                        
                        if (ShowAngleInAlert && ShowAlerts && i == rates_total - 1)
                        {
                            double angle = CalculateHMAAngle(i);
                            Alert("HMA Signal SKIPPED - Angle: ", DoubleToString(angle, 2), "° < Min: ", DoubleToString(MinAngle, 1), "°");
                        }
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

// HMA角度計算関数
double CalculateHMAAngle(int pos)
{
    if (pos < AnglePeriod || hmaBuffer[pos] == 0.0 || hmaBuffer[pos - AnglePeriod] == 0.0)
        return 0.0;
    
    double hmaChange = hmaBuffer[pos] - hmaBuffer[pos - AnglePeriod];
    double angle = MathArctan(hmaChange / AnglePeriod) * 180.0 / 3.14159265359;
    
    // デバッグ用：角度計算の詳細をコメントアウトして確認可能
    /*
    Print("DEBUG - Pos:", pos, " HMA[", pos, "]:", hmaBuffer[pos], 
          " HMA[", pos-AnglePeriod, "]:", hmaBuffer[pos-AnglePeriod],
          " Change:", hmaChange, " Angle:", angle);
    */
    
    return angle;
}

// トレンド判定関数
bool IsTrending(int pos)
{
    if (!UseAngleFilter)
        return true;  // フィルター無効時は常にトレンド扱い
    
    double angle = CalculateHMAAngle(pos);
    bool trending = MathAbs(angle) > MinAngle;
    
    // デバッグ用：判定結果をコメントアウトして確認可能
    /*
    Print("DEBUG - Trending Check: Angle=", DoubleToString(angle, 3), 
          " MinAngle=", DoubleToString(MinAngle, 1), 
          " Result=", trending ? "TRUE" : "FALSE");
    */
    
    return trending;
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