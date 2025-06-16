//+------------------------------------------------------------------+
//|                                                MLTradingEA.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.00"

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
string current_symbol = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // シンボル名を取得
    current_symbol = _Symbol;
    
    // 初期化ログ
    Print("=== ML Trading EA 初期化 ===");
    Print("対象シンボル: ", current_symbol);
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
    Print("ML Trading EA 終了 - ", current_symbol);
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
//| ティックデータをAPIに送信（シンボル対応版）                                  |
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
    
    // JSON データ作成（シンボル情報を含む）
    string json_data = StringFormat(
        "{"
        "\"symbol\":\"%s\","
        "\"datetime\":\"%s\","
        "\"open\":%.5f,"
        "\"high\":%.5f,"
        "\"low\":%.5f,"
        "\"close\":%.5f,"
        "\"volume\":%d"
        "}",
        current_symbol,  // シンボル情報を追加
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
//| 取引シグナルを処理（シンボル対応版）                                        |
//+------------------------------------------------------------------+
void ProcessTradingSignal()
{
    // シンボル指定のエンドポイントを使用
    string url = FIXED_API_URL + "/signal/" + current_symbol;
    string response = GetRequest(url);
    
    if(response == "")
        return;
    
    // レスポンス解析
    string signal = ExtractJsonString(response, "signal");
    double confidence = ExtractJsonDouble(response, "confidence");
    double predicted_price = ExtractJsonDouble(response, "predicted_price");
    string message = ExtractJsonString(response, "message");
    
    // データ更新
    last_signal = signal;
    last_confidence = confidence;
    last_predicted_price = predicted_price;
    
    Print(StringFormat("[%s] シグナル: %s, 信頼度: %.3f, 予測価格: %.5f, メッセージ: %s", 
          current_symbol, signal, confidence, predicted_price, message));
    
    // 取引実行判定
    if(confidence >= MinConfidence && (signal == "BUY" || signal == "SELL"))
    {
        ExecuteTradeSignal(signal, confidence);
    }
    else if(signal == "HOLD")
    {
        Print(StringFormat("[%s] ホールド中 - 信頼度: %.3f (最小: %.2f)", 
              current_symbol, confidence, MinConfidence));
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
        Print(StringFormat("[%s] アカウント管理により取引停止中", current_symbol));
        return;
    }
    
    // 現在のポジション数チェック
    if(CountMyPositions() >= MaxPositions)
    {
        Print(StringFormat("[%s] 最大ポジション数に達しています (%d/%d)", 
              current_symbol, CountMyPositions(), MaxPositions));
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
//| 自分のポジション数をカウント                                            |
//+------------------------------------------------------------------+
int CountMyPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == current_symbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                count++;
            }
        }
    }
    return count;
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
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if(adjusted_lots < min_lot)
        adjusted_lots = min_lot;
    if(adjusted_lots > max_lot)
        adjusted_lots = max_lot;
    
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
    request.comment = StringFormat("ML_%s_%.2f", current_symbol, confidence);
    
    // 注文実行
    if(OrderSend(request, result))
    {
        Print(StringFormat("[%s] ポジションオープン: %s, ロット: %.2f, 価格: %.5f, 信頼度: %.2f",
              current_symbol,
              (order_type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
              adjusted_lots, price, confidence));
        
        // 予測価格情報も出力
        if(last_predicted_price > 0)
        {
            double price_diff = last_predicted_price - price;
            Print(StringFormat("[%s] 予測価格: %.5f, 差分: %.5f pips",
                  current_symbol, last_predicted_price, 
                  MathAbs(price_diff) / point / 10));
        }
    }
    else
    {
        Print(StringFormat("[%s] 注文エラー: %s (コード: %d)",
              current_symbol, result.comment, result.retcode));
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
            if(PositionGetString(POSITION_SYMBOL) != current_symbol ||
               PositionGetInteger(POSITION_MAGIC) != Magic)
                continue;
                
            // 必要に応じて追加のポジション管理ロジック
            // 例: トレーリングストップ、時間ベースの決済など
            
            // 現在は基本的なポジション情報のみログ出力
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit != 0)
            {
                // 大きな利益または損失の場合にログ出力
                if(MathAbs(profit) > 10.0)
                {
                    Print(StringFormat("[%s] ポジション #%d 損益: %.2f",
                          current_symbol, ticket, profit));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| シンボル別状態チェック機能                                            |
//+------------------------------------------------------------------+
void CheckSymbolStatus()
{
    string url = FIXED_API_URL + "/status/" + current_symbol;
    string response = GetRequest(url);
    
    if(response != "")
    {
        int buffer_size = (int)ExtractJsonDouble(response, "current_buffer_size");
        int total_records = (int)ExtractJsonDouble(response, "total_records");
        bool model_loaded = ExtractJsonString(response, "model_loaded") == "true";
        
        Print(StringFormat("[%s] API状態 - バッファ: %d件, 総レコード: %d件, モデル: %s",
              current_symbol, buffer_size, total_records, 
              model_loaded ? "読み込み済み" : "未読み込み"));
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
            Print(StringFormat("[%s] API接続復旧 - 成功率: %.1f%%", 
                  current_symbol, (double)successful_api_calls/total_api_calls*100));
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
        
        Print(StringFormat("[%s] API接続エラー: %s (連続失敗:%d回)",
              current_symbol, error_msg, consecutive_failures));
        
        // レスポンス内容がある場合は表示
        if(ArraySize(result) > 0)
        {
            string response = CharArrayToString(result);
            if(StringLen(response) > 0)
            {
                Print(StringFormat("[%s] エラー詳細: %s", current_symbol, response));
            }
        }
        
        // 3回連続失敗でAPI無効扱い
        if(consecutive_failures >= 3)
        {
            api_available = false;
            Print(StringFormat("[%s] API接続無効化 - 連続失敗数:%d", 
                  current_symbol, consecutive_failures));
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
    else if(res != 0)
    {
        // エラーログ（GETリクエストでは詳細ログは控えめに）
        Print(StringFormat("[%s] GET リクエストエラー: HTTP %d", current_symbol, res));
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
    {
        // null値のチェック
        string null_pattern = "\"" + key + "\":null";
        if(StringFind(json, null_pattern) != -1)
            return "";
            
        // boolean値のチェック
        string bool_pattern = "\"" + key + "\":";
        int bool_pos = StringFind(json, bool_pattern);
        if(bool_pos != -1)
        {
            int bool_start = bool_pos + StringLen(bool_pattern);
            if(StringSubstr(json, bool_start, 4) == "true")
                return "true";
            else if(StringSubstr(json, bool_start, 5) == "false")
                return "false";
        }
        
        return "";
    }
    
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
    
    // null値のチェック
    if(StringSubstr(json, start_pos, 4) == "null")
        return 0.0;
    
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
    
    // 文字列をトリム
    StringReplace(number_str, " ", "");
    
    return StringToDouble(number_str);
}

//+------------------------------------------------------------------+
//| Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_KEYDOWN)
    {
        if(lparam == 83) // 'S'キー - 統計表示
        {
            Print("=== ", current_symbol, " API接続統計 ===");
            Print("総API呼び出し: ", total_api_calls);
            Print("成功呼び出し: ", successful_api_calls);
            if(total_api_calls > 0)
                Print("成功率: ", DoubleToString((double)successful_api_calls/total_api_calls*100, 1), "%");
            Print("連続失敗: ", consecutive_failures);
            Print("API利用可能: ", api_available ? "YES" : "NO");
            Print("最終成功時刻: ", TimeToString(last_successful_connection));
            Print("最新シグナル: ", last_signal);
            Print("最新信頼度: ", DoubleToString(last_confidence, 3));
            if(last_predicted_price > 0)
                Print("最新予測価格: ", DoubleToString(last_predicted_price, 5));
            
            if(UseAccountManager)
            {
                g_AccountManager.PrintStatus();
            }
        }
        else if(lparam == 84) // 'T'キー - テスト送信
        {
            Print("=== ", current_symbol, " テスト送信実行 ===");
            SendTickData();
        }
        else if(lparam == 67) // 'C'キー - シンボル状態チェック
        {
            Print("=== ", current_symbol, " 状態チェック ===");
            CheckSymbolStatus();
        }
    }
}