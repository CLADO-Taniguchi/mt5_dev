//+------------------------------------------------------------------+
//|                                    Median Standard Deviation Oscillator |
//|                                                                         |
//|                           中央値標準偏差オシレーター（レンジ相場判定用） |
//+------------------------------------------------------------------+
#property copyright "Custom Indicator"
#property link      ""
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_plots   1

// プロット設定
#property indicator_label1  "Median StdDev"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// 水平線設定
#property indicator_level1 20.0
#property indicator_level2 15.0
#property indicator_level3 10.0
#property indicator_level4 5.0
#property indicator_levelcolor clrGray
#property indicator_levelstyle STYLE_DOT

// 入力パラメーター
input int Period = 20;                    // 計算期間
input ENUM_APPLIED_PRICE PriceType = PRICE_MEDIAN; // 価格タイプ
input bool ShowInPips = true;             // pips表示
input bool ShowAlerts = false;            // アラート表示
input double RangeThreshold = 10.0;       // レンジ判定閾値

// バッファー
double MedianStdDevBuffer[];

int OnInit()
{
    // バッファー設定
    SetIndexBuffer(0, MedianStdDevBuffer, INDICATOR_DATA);
    
    // インディケーター名設定
    string shortName = "MedianStdDev(" + IntegerToString(Period) + ")";
    IndicatorSetString(INDICATOR_SHORTNAME, shortName);
    
    // 小数点桁数
    IndicatorSetInteger(INDICATOR_DIGITS, ShowInPips ? 1 : 5);
    
    // 配列設定
    ArraySetAsSeries(MedianStdDevBuffer, false);
    
    // 最小バー数
    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, Period);
    
    return INIT_SUCCEEDED;
}

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
    if (rates_total < Period)
        return 0;

    // 配列の向き設定
    ArraySetAsSeries(open, false);
    ArraySetAsSeries(high, false);
    ArraySetAsSeries(low, false);
    ArraySetAsSeries(close, false);
    ArraySetAsSeries(time, false);

    // 計算開始位置
    int start_pos = MathMax(prev_calculated - 1, Period - 1);
    if (start_pos < Period - 1) start_pos = Period - 1;

    // メイン計算ループ
    for (int i = start_pos; i < rates_total; i++)
    {
        MedianStdDevBuffer[i] = CalculateMedianStandardDeviation(i, open, high, low, close);
        
        // アラートチェック（最新バーのみ）
        if (ShowAlerts && i == rates_total - 1)
        {
            CheckRangeAlert(i);
        }
    }

    return rates_total;
}

// 中央値標準偏差計算のメイン関数
double CalculateMedianStandardDeviation(int pos, 
                                       const double &open[],
                                       const double &high[],
                                       const double &low[],
                                       const double &close[])
{
    if (pos < Period - 1)
        return 0.0;

    // 価格配列を準備
    double prices[];
    ArrayResize(prices, Period);
    
    // 指定された価格タイプで配列を埋める
    for (int i = 0; i < Period; i++)
    {
        int index = pos - i;
        
        switch(PriceType)
        {
            case PRICE_OPEN:
                prices[i] = open[index];
                break;
            case PRICE_HIGH:
                prices[i] = high[index];
                break;
            case PRICE_LOW:
                prices[i] = low[index];
                break;
            case PRICE_CLOSE:
                prices[i] = close[index];
                break;
            case PRICE_MEDIAN:
                prices[i] = (high[index] + low[index]) / 2.0;
                break;
            case PRICE_TYPICAL:
                prices[i] = (high[index] + low[index] + close[index]) / 3.0;
                break;
            case PRICE_WEIGHTED:
                prices[i] = (high[index] + low[index] + close[index] * 2) / 4.0;
                break;
            default:
                prices[i] = close[index];
        }
    }
    
    // 中央値を計算
    double median = CalculateMedian(prices, Period);
    
    // 標準偏差を計算
    double sumSquaredDiff = 0.0;
    for (int i = 0; i < Period; i++)
    {
        double diff = prices[i] - median;
        sumSquaredDiff += diff * diff;
    }
    
    double standardDeviation = MathSqrt(sumSquaredDiff / Period);
    
    // pips表示の場合は変換
    if (ShowInPips)
    {
        double pipValue = GetPipValue();
        standardDeviation = standardDeviation / pipValue;
    }
    
    return standardDeviation;
}

// 中央値計算関数
double CalculateMedian(double &array[], int size)
{
    // 配列をコピーしてソート
    double sortedArray[];
    ArrayResize(sortedArray, size);
    ArrayCopy(sortedArray, array, 0, 0, size);
    ArraySort(sortedArray);
    
    // 中央値を取得
    if (size % 2 == 1)
    {
        // 奇数の場合：中央の値
        return sortedArray[size / 2];
    }
    else
    {
        // 偶数の場合：中央2つの平均
        int mid1 = size / 2 - 1;
        int mid2 = size / 2;
        return (sortedArray[mid1] + sortedArray[mid2]) / 2.0;
    }
}

// Pip値取得関数
double GetPipValue()
{
    string symbol = _Symbol;
    
    // 主要通貨ペアのPip値
    if (StringFind(symbol, "JPY") >= 0)
    {
        return 0.01; // JPYペアは0.01
    }
    else
    {
        return 0.0001; // その他は0.0001
    }
}

// レンジアラートチェック
void CheckRangeAlert(int pos)
{
    double currentValue = MedianStdDevBuffer[pos];
    static datetime lastAlertTime = 0;
    
    // 同じ分での重複アラートを防ぐ
    if (TimeCurrent() - lastAlertTime < 60)
        return;
    
    string message = "";
    
    if (currentValue <= RangeThreshold)
    {
        message = "レンジ相場検出: MedianStdDev = " + DoubleToString(currentValue, 1);
        if (ShowInPips) message += " pips";
        
        Alert(message + " at " + _Symbol);
        lastAlertTime = TimeCurrent();
    }
}

// インディケーター名表示用
string GetIndicatorName()
{
    string name = "MedianStdDev(" + IntegerToString(Period) + ")";
    
    switch(PriceType)
    {
        case PRICE_OPEN: name += " Open"; break;
        case PRICE_HIGH: name += " High"; break;
        case PRICE_LOW: name += " Low"; break;
        case PRICE_CLOSE: name += " Close"; break;
        case PRICE_MEDIAN: name += " Median"; break;
        case PRICE_TYPICAL: name += " Typical"; break;
        case PRICE_WEIGHTED: name += " Weighted"; break;
    }
    
    if (ShowInPips) name += " (pips)";
    
    return name;
}