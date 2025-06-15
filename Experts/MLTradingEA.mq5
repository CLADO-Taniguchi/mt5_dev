//+------------------------------------------------------------------+
//|                                                MLTradingEA.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// アカウント管理ライブラリをインクルード
#include <AccountManager.mqh>

//--- 入力パラメータ
input double   Lots = 0.1;                               // ロットサイズ
input int      Magic = 123456;                           // マジックナンバー
input double   StopLoss = 100;                           // ストップロス(ポイント)
input double   TakeProfit = 200;                         // テイクプロフィット(ポイント)
input int      SendDataInterval = 10;                    // データ送信間隔(秒)
input double   MinConfidence = 0.7;                      // 最小信頼度
input int      MaxPositions = 1;                         // 最大ポジション数
input bool     UseAccountManager = true;                 // アカウント管理を使用

//--- 固定URL（変更されない）
const string FIXED_API_URL = "http://127.0.0.1:5000";

//--- グローバル変数
datetime last_send_time = 0;
string last_signal = "HOLD";
double last_confidence = 0.0;
double last_predicted_price = 0.0;
int consecutive_failures = 0;
int total_api_calls = 0;
int successful_api_calls = 0;
bool api_available = true;
datetime last_successful_connection = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // 初期化ログ
    Print("=== ML Trading EA 初期化 ===");
    Print("API URL: ", FIXED_API_URL, " (固定)");
    Print("データ送信間隔: ", SendDataInterval, "秒");
    Print("最小信頼度: ", MinConfidence);
    Print("アカウント管理: ", UseAccountManager ? "有効" : "無効");
    
    // API接続テスト
    if(!TestAPIConnection())
    {
        Print("警告: API接続に失敗しました。手動で確認してください。");
        api_available = false;
    }
    
    // タイマー設定
    EventSetTimer(SendDataInterval);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    Print("ML Trading EA 終了");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // アカウント管理チェック（有効な場合）
    if(UseAccountManager)
    {
        g_AccountManager.CheckAndRecordBalance();
        if(!g_AccountManager.IsTradingAllowed())
        {
            // 売買停止中はポジション管理のみ
            return;
        }
    }
    
    // ポジション管理
    ManagePositions();
}

//+------------------------------------------------------------------+
//| Timer function - 定期的にデータを送信                                |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(!api_available)
        return;
        
    // ティックデータ送信
    SendTickData();
    
    // シグナル取得と処理
    ProcessTradingSignal();
}

//+------------------------------------------------------------------+
//| API接続テスト                                                      |
//+------------------------------------------------------------------+
bool TestAPIConnection()
{
    string url = FIXED_API_URL + "/health";
    string headers = "Content-Type: application/json\r\n";
    char data[];
    char result[];
    string result_headers;
    
    Print("接続テスト開始: ", url);
    
    int timeout = 5000; // 5秒
    int res = WebRequest("GET", url, headers, timeout, data, result, result_headers);
    
    Print("WebRequest結果: ", res);
    Print("レスポンスヘッダー: ", result_headers);
    
    if(res == 200)
    {
        string response = CharArrayToString(result);
        Print("レスポンス内容: ", response);
        Print("API接続成功");
        return true;
    }
    else if(res == -1)
    {
        Print("API接続失敗: WebRequestが許可されていません");
        Print("ツール→オプション→エキスパートアドバイザーでWebRequest設定を確認してください");
    }
    else
    {
        Print("API接続失敗: HTTPエラーコード ", res);
    }
    return false;
}

//+------------------------------------------------------------------+
//| ティックデータをAPIに送信（改良版）                                        |
//+------------------------------------------------------------------+
void SendTickData()
{
    if(!api_available)
    {
        // 5分ごとに再接続を試行
        if(TimeCurrent() - last_successful_connection > 300)
        {
            Print("API再接続試行中...");
            if(TestAPIConnection())
            {
                api_available = true;
                consecutive_failures = 0;
            }
        }
        return;
    }
        
    // 現在の価格情報を取得
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick))
    {
        Print("ティック情報取得エラー");
        return;
    }
    
    // OHLCV データを準備
    MqlRates rates[1];
    if(CopyRates(_Symbol, _Period, 0, 1, rates) != 1)
    {
        Print("レート情報取得エラー");
        return;
    }
    
    // JSON データ作成
    string json_data = StringFormat(
        "{"
        "\"datetime\":\"%s\","
        "\"open\":%.5f,"
        "\"high\":%.5f,"
        "\"low\":%.5f,"
        "\"close\":%.5f,"
        "\"volume\":%d"
        "}",
        TimeToString(tick.time, TIME_DATE|TIME_SECONDS),
        rates[0].open,
        rates[0].high,
        rates[0].low,
        rates[0].close,
        (int)rates[0].tick_volume
    );
    
    // API に送信（リトライ機能付き）
    string url = FIXED_API_URL + "/tick";
    int retry_count = 0;
    int max_retries = 2;
    
    while(retry_count <= max_retries)
    {
        if(SendPostRequest(url, json_data))
        {
            if(retry_count > 0)
                Print("API送信成功 (", retry_count, "回目の試行)");
            return;
        }
        
        retry_count++;
        if(retry_count <= max_retries)
        {
            Print("API送信リトライ中... (", retry_count, "/", max_retries, ")");
            Sleep(1000); // 1秒待機してリトライ
        }
    }
    
    Print("API送信最終失敗 - 全", max_retries + 1, "回の試行失敗");
}

//+------------------------------------------------------------------+
//| 取引シグナルを処理                                                    |
//+------------------------------------------------------------------+
void ProcessTradingSignal()
{
    string url = FIXED_API_URL + "/signal";
    string response = GetRequest(url);
    
    if(response == "")
        return;
    
    // レスポンス解析
    string signal = ExtractJsonString(response, "signal");
    double confidence = ExtractJsonDouble(response, "confidence");
    double predicted_price = ExtractJsonDouble(response, "predicted_price");
    
    // データ更新
    last_signal = signal;
    last_confidence = confidence;
    last_predicted_price = predicted_price;
    
    Print(StringFormat("シグナル: %s, 信頼度: %.3f, 予測価格: %.5f", 
          signal, confidence, predicted_price));
    
    // 取引実行判定
    if(confidence >= MinConfidence)
    {
        ExecuteTradeSignal(signal, confidence);
    }
}

//+------------------------------------------------------------------+
//| 取引シグナルを実行                                                    |
//+------------------------------------------------------------------+
void ExecuteTradeSignal(string signal, double confidence)
{
    // アカウント管理チェック
    if(UseAccountManager && !g_AccountManager.IsTradingAllowed())
    {
        Print("アカウント管理により取引停止中");
        return;
    }
    
    // 現在のポジション数チェック
    if(PositionsTotal() >= MaxPositions)
    {
        Print("最大ポジション数に達しています");
        return;
    }
    
    // シグナルに基づく取引実行
    if(signal == "BUY")
    {
        OpenPosition(ORDER_TYPE_BUY, confidence);
    }
    else if(signal == "SELL")
    {
        OpenPosition(ORDER_TYPE_SELL, confidence);
    }
}

//+------------------------------------------------------------------+
//| ポジションオープン                                                   |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE order_type, double confidence)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    double price = (order_type == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // 信頼度に基づくロットサイズ調整
    double adjusted_lots = Lots * confidence;
    adjusted_lots = NormalizeDouble(adjusted_lots, 2);
    
    // 最小ロットサイズチェック
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    if(adjusted_lots < min_lot)
        adjusted_lots = min_lot;
    
    // ストップロスとテイクプロフィット
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
    
    // 注文設定
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = adjusted_lots;
    request.type = order_type;
    request.price = NormalizeDouble(price, digits);
    request.sl = sl;
    request.tp = tp;
    request.magic = Magic;
    request.comment = StringFormat("ML_%.2f", confidence);
    
    // 注文実行
    if(OrderSend(request, result))
    {
        Print(StringFormat("ポジションオープン: %s, ロット: %.2f, 価格: %.5f, 信頼度: %.2f",
              (order_type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
              adjusted_lots, price, confidence));
    }
    else
    {
        Print("注文エラー: ", result.comment);
    }
}

//+------------------------------------------------------------------+
//| ポジション管理                                                      |
//+------------------------------------------------------------------+
void ManagePositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != Magic)
                continue;
                
            // 必要に応じて追加のポジション管理ロジック
            // 例: トレーリングストップ、時間ベースの決済など
        }
    }
}

//+------------------------------------------------------------------+
//| POST リクエスト送信（エラーハンドリング強化）                               |
//+------------------------------------------------------------------+
bool SendPostRequest(string url, string json_data)
{
    string headers = "Content-Type: application/json\r\n";
    char data[];
    char result[];
    string result_headers;
    
    total_api_calls++;
    
    StringToCharArray(json_data, data, 0, StringLen(json_data));
    
    int timeout = 10000; // タイムアウトを10秒に延長
    int res = WebRequest("POST", url, headers, timeout, data, result, result_headers);
    
    if(res == 200)
    {
        successful_api_calls++;
        consecutive_failures = 0;
        last_successful_connection = TimeCurrent();
        
        if(!api_available)
        {
            api_available = true;
            Print("API接続復旧 - 成功率: ", 
                  DoubleToString((double)successful_api_calls/total_api_calls*100, 1), "%");
        }
        return true;
    }
    else
    {
        consecutive_failures++;
        
        // 詳細なエラーログ
        string error_msg = "";
        switch(res)
        {
            case -1: error_msg = "WebRequest許可されていません"; break;
            case 0:  error_msg = "タイムアウト"; break;
            case 400: error_msg = "不正なリクエスト"; break;
            case 404: error_msg = "API not found"; break;
            case 500: error_msg = "サーバーエラー"; break;
            default: error_msg = "HTTPエラー " + IntegerToString(res); break;
        }
        
        Print("API接続エラー: ", error_msg, 
              " (連続失敗:", consecutive_failures, "回)");
        
        // 3回連続失敗でAPI無効扱い
        if(consecutive_failures >= 3)
        {
            api_available = false;
            Print("API接続無効化 - 連続失敗数:", consecutive_failures);
        }
        
        return false;
    }
}

//+------------------------------------------------------------------+
//| GET リクエスト送信                                                 |
//+------------------------------------------------------------------+
string GetRequest(string url)
{
    string headers = "Content-Type: application/json\r\n";
    char data[];
    char result[];
    string result_headers;
    
    int timeout = 5000;
    int res = WebRequest("GET", url, headers, timeout, data, result, result_headers);
    
    if(res == 200)
    {
        return CharArrayToString(result);
    }
    
    return "";
}

//+------------------------------------------------------------------+
//| JSON から文字列値を抽出                                             |
//+------------------------------------------------------------------+
string ExtractJsonString(string json, string key)
{
    string search_pattern = "\"" + key + "\":\"";
    int start_pos = StringFind(json, search_pattern);
    
    if(start_pos == -1)
        return "";
    
    start_pos += StringLen(search_pattern);
    int end_pos = StringFind(json, "\"", start_pos);
    
    if(end_pos == -1)
        return "";
    
    return StringSubstr(json, start_pos, end_pos - start_pos);
}

//+------------------------------------------------------------------+
//| JSON から数値を抽出                                                |
//+------------------------------------------------------------------+
double ExtractJsonDouble(string json, string key)
{
    string search_pattern = "\"" + key + "\":";
    int start_pos = StringFind(json, search_pattern);
    
    if(start_pos == -1)
        return 0.0;
    
    start_pos += StringLen(search_pattern);
    
    // 数値の終端を見つける
    int end_pos = start_pos;
    string char_at_pos;
    
    while(end_pos < StringLen(json))
    {
        char_at_pos = StringSubstr(json, end_pos, 1);
        if(char_at_pos == "," || char_at_pos == "}" || char_at_pos == "]")
            break;
        end_pos++;
    }
    
    string number_str = StringSubstr(json, start_pos, end_pos - start_pos);
    return StringToDouble(number_str);
}

//+------------------------------------------------------------------+
//| Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_KEYDOWN)
    {
        if(lparam == 83) // 'S'キー
        {
            Print("=== API接続統計 ===");
            Print("総API呼び出し: ", total_api_calls);
            Print("成功呼び出し: ", successful_api_calls);
            if(total_api_calls > 0)
                Print("成功率: ", DoubleToString((double)successful_api_calls/total_api_calls*100, 1), "%");
            Print("連続失敗: ", consecutive_failures);
            Print("API利用可能: ", api_available ? "YES" : "NO");
            Print("最終成功時刻: ", TimeToString(last_successful_connection));
            
            if(UseAccountManager)
            {
                g_AccountManager.PrintStatus();
            }
        }
    }
}