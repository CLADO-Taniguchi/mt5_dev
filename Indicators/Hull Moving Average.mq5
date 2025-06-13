#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   1

input int Period = 21;

double hmaBuffer[];   // HMAライン
double hmaColors[];   // 色インデックス

int OnInit()
{
    SetIndexBuffer(0, hmaBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, hmaColors, INDICATOR_COLOR_INDEX);

    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_LINE);
    PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, LightGray);  // 上昇
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, Yellow);   // 下降または横ばい
    PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 4);
    PlotIndexSetString(0, PLOT_LABEL, "HMA Up/Down");

    ArraySetAsSeries(hmaBuffer, true);
    ArraySetAsSeries(hmaColors, true);

    return INIT_SUCCEEDED;
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
    if (rates_total < Period + 1)
        return 0;

    ArraySetAsSeries(close, true);

    int sqrtPeriod = (int)MathSqrt(Period);
    double rawWMA[];
    ArrayResize(rawWMA, rates_total);
    ArraySetAsSeries(rawWMA, true);

    // 中間WMA
    for (int i = Period; i < rates_total; i++)
    {
        double wma_half = WMA(i, Period / 2, close);
        double wma_full = WMA(i, Period, close);
        rawWMA[i] = 2 * wma_half - wma_full;
    }

    // HMA
    for (int i = Period + 1; i < rates_total; i++)
    {
        hmaBuffer[i] = WMA(i, sqrtPeriod, rawWMA);

        if (hmaBuffer[i] == 0.0 || hmaBuffer[i - 1] == 0.0)
        {
            hmaColors[i] = 1;  // 安全側に白
        }
        else
        {
            double dy = hmaBuffer[i] - hmaBuffer[i - 1];
            hmaColors[i] = (dy > 0) ? 0 : 1;
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