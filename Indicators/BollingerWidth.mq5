//+------------------------------------------------------------------+
//|                                           BollingerWidthRate.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//--- インジケーターのプロパティ定義
#property indicator_separate_window    // サブウィンドウに表示
#property indicator_buffers 1          // 使用するバッファは1つ
#property indicator_plots   1          // 描画するラインは1つ

//--- ラインの見た目設定
#property indicator_label1  "WidthChangeRate"      // ラインのラベル
#property indicator_type1   DRAW_LINE              // ラインで描画
#property indicator_color1  clrOrange              // 色をオレンジに
#property indicator_style1  STYLE_SOLID            // 実線
#property indicator_width1  2                      // 太さ

//--- 入力パラメータ
input int    BBPeriod = 20;     // ボリンジャーバンドの期間
input double Sigma    = 3.0;    // シグマ（標準偏差の倍率）

//--- グローバル変数
double ExtWidthChangeRateBuffer[]; // 計算結果を格納するバッファ

//+------------------------------------------------------------------+
//| インジケーター初期化関数                                           |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- インジケーターバッファと描画ラインを紐付け
    SetIndexBuffer(0, ExtWidthChangeRateBuffer, INDICATOR_DATA);
    PlotIndexSetString(0, PLOT_LABEL, "WidthChangeRate(%)");
    IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("BBWidthRate(%d, %.1f)", BBPeriod, Sigma));

    //--- 0レベルに水平線を描画
    IndicatorSetInteger(INDICATOR_LEVELS, 1);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, 0.0);
    IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
    IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrGray);
    IndicatorSetInteger(INDICATOR_LEVELWIDTH, 0, 1);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| インジケーター計算関数                                             |
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
    //--- 計算に必要な最低限のバー数をチェック
    if(rates_total < BBPeriod + 1)
    {
        return(0);
    }
    
    //--- 標準偏差を計算するためのMQL5標準関数ハンドルを取得
    int stddev_handle = iStdDev(NULL, 0, BBPeriod, 0, MODE_SMA, PRICE_CLOSE);
    if(stddev_handle == INVALID_HANDLE)
    {
        Print("iStdDev handle create error");
        return(0);
    }

    //--- 標準偏差の値をコピーするための配列を準備
    double stddev_buffer[];
    
    //--- 標準偏差の値を配列にコピー
    if(CopyBuffer(stddev_handle, 0, 0, rates_total, stddev_buffer) <= 0)
    {
        Print("CopyBuffer from iStdDev failed");
        return(0);
    }
    
    //--- メインの計算ループ ---
    int start;
    if(prev_calculated == 0) // 初回計算時
    {
        start = BBPeriod + 1; 
    }
    else
    {
        start = prev_calculated - 1;
    }

    for(int i = start; i < rates_total; i++)
    {
        // ボリンジャーバンドの幅を計算
        double current_width = stddev_buffer[i] * Sigma * 2.0;
        double prev_width    = stddev_buffer[i-1] * Sigma * 2.0;

        // 変化率(%)を計算
        if(prev_width > 0.00000001)
        {
            ExtWidthChangeRateBuffer[i] = ((current_width - prev_width) / prev_width) * 100.0;
        }
        else
        {
            ExtWidthChangeRateBuffer[i] = 0.0;
        }
    }
    
    return(rates_total);
}
//+------------------------------------------------------------------+