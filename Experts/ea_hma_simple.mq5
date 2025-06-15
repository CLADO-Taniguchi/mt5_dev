//+------------------------------------------------------------------+
//|                                                ea_hma_simple.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// アカウント管理ライブラリをインクルード
#include <AccountManager.mqh>  // Include フォルダから読み込む場合
// または
// #include "AccountManager.mqh"  // 同じフォルダにある場合

//--- 入力パラメータ
input double   Lots = 0.1;           // ロットサイズ
input int      HMA_Period = 14;      // HMA期間
input int      Magic = 1105;        // マジックナンバー
input double   StopLoss = 100;       // ストップロス(ポイント)
input double   TakeProfit = 200;     // テイクプロフィット(ポイント)

//--- グローバル変数
int hma_handle;                      // HMAハンドル
double hma_buffer[];                 // HMAバッファ

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // HMAインジケーターの初期化
    hma_handle = iMA(_Symbol, _Period, HMA_Period, 0, MODE_LWMA, PRICE_MEDIAN);
    if(hma_handle == INVALID_HANDLE)
    {
        Print("HMAインジケーターの初期化に失敗しました");
        return INIT_FAILED;
    }
    
    // 配列設定
    ArraySetAsSeries(hma_buffer, true);
    
    Print("EA初期化完了 - アカウント管理機能付きHMA Simple");
    Print("損失停止比率: ", DoubleToString(g_AccountManager.GetStopLossRatio() * 100, 1), "%");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // ハンドルの解放
    if(hma_handle != INVALID_HANDLE)
        IndicatorRelease(hma_handle);
        
    Print("EA終了");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // アカウント管理：残高記録の確認
    g_AccountManager.CheckAndRecordBalance();
    
    // アカウント管理：売買許可チェック
    if(!g_AccountManager.IsTradingAllowed())
    {
        // 売買停止中の場合、ここで処理を終了
        return;
    }
    
    // HMAデータの取得
    if(CopyBuffer(hma_handle, 0, 0, 3, hma_buffer) < 3)
        return;
    
    // 現在のポジション数をチェック
    if(PositionsTotal() > 0)
        return; // 既にポジションがある場合は何もしない
    
    // HMAの傾きを判定
    bool hma_up = hma_buffer[0] > hma_buffer[1] && hma_buffer[1] > hma_buffer[2];
    bool hma_down = hma_buffer[0] < hma_buffer[1] && hma_buffer[1] < hma_buffer[2];
    
    // エントリー条件（アカウント管理の条件も含む）
    if(hma_up && g_AccountManager.IsTradingAllowed())
    {
        // 買いエントリー
        OpenPosition(ORDER_TYPE_BUY);
    }
    else if(hma_down && g_AccountManager.IsTradingAllowed())
    {
        // 売りエントリー
        OpenPosition(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| ポジションオープン関数                                                  |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE order_type)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    double price = (order_type == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // ストップロスとテイクプロフィットの計算
    double sl = 0, tp = 0;
    if(StopLoss > 0)
    {
        sl = (order_type == ORDER_TYPE_BUY) ? 
             price - StopLoss * point : 
             price + StopLoss * point;
        sl = NormalizeDouble(sl, digits);
    }
    
    if(TakeProfit > 0)
    {
        tp = (order_type == ORDER_TYPE_BUY) ? 
             price + TakeProfit * point : 
             price - TakeProfit * point;
        tp = NormalizeDouble(tp, digits);
    }
    
    // 注文リクエストの設定
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = Lots;
    request.type = order_type;
    request.price = NormalizeDouble(price, digits);
    request.sl = sl;
    request.tp = tp;
    request.magic = Magic;
    request.comment = "HMA_Simple_AccountMgr";
    
    // 注文送信
    if(OrderSend(request, result))
    {
        Print("ポジションオープン成功: ", 
              (order_type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
              " Price: ", DoubleToString(price, digits),
              " SL: ", DoubleToString(sl, digits),
              " TP: ", DoubleToString(tp, digits));
    }
    else
    {
        Print("ポジションオープン失敗: ", result.comment);
    }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    // 定期的にアカウント状況を表示（オプション）
    g_AccountManager.PrintStatus();
}

//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
{
    // トレード発生時の処理
    // 必要に応じてアカウント管理の状況を更新
}