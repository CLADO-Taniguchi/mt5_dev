//+------------------------------------------------------------------+
//|                                                    SignalTrader_EA.mq5 |
//|               Flask APIのシグナルで自動売買                    |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
#include <Indicators\Indicators.mqh>
CTrade trade;

input string api_url = "http://127.0.0.1:5000/get_signal?symbol=EURUSD&timeframe=M5";
input double lot_size = 0.1;
input int sl_pips = 20;
input int magic_number = 123456;  // 参考用として保持
double balance_at_10_jst = -1;  // JST 10:00 の残高基準値（未設定時は -1）

string g_symbol;
double point;
string last_signal = "";
bool sl_triggered = false;
datetime last_signal_time = 0;  // 最後にトリガーしたバーの時刻

//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbol = Symbol();
   point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);

   EventSetTimer(10);
   Print("[DEBUG] EA initialized. Symbol=", g_symbol, ", Point=", DoubleToString(point, 10));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   Print("[DEBUG] EA deinitialized.");
  }

void OnTimer()
  {
    // JST 10:00:00 に基準残高を取得
    datetime now = TimeLocal();  // Windowsのローカル時刻（JST想定）
    MqlDateTime dt;
    TimeToStruct(now, dt);

    if(dt.hour == 10 && dt.min == 0 && balance_at_10_jst < 0)
      {
      balance_at_10_jst = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("[DEBUG] JST 10:00:00 残高基準値を記録: ", DoubleToString(balance_at_10_jst, 2));
      }

    // 現在の残高と比較
    if(balance_at_10_jst > 0)
      {
      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double threshold = balance_at_10_jst * 0.8;

      if(current_balance < threshold)
        {
          Print("[DEBUG] 残高が10時時点の8割を下回っているためトレード中止: ", DoubleToString(current_balance, 2));
          return;
        }
      }
   char post[];
   char result[];
   string response_headers;
   string response;
   int timeout = 5000;
   int post_size = ArraySize(post);

   int res = WebRequest("GET", api_url, "", "", timeout, post, post_size, result, response_headers);

   if(res != 200)
     {
      Print("[ERROR] WebRequest failed. Code=", IntegerToString(res), ", Error=", IntegerToString(GetLastError()));
      return;
     }

   response = CharArrayToString(result);
   Print("[DEBUG] WebRequest succeeded. Raw response=" + response);

   string json = response;
   string signal = jsonValueByKey(json, "signal");
   string price_str = jsonValueByKey(json, "price");
   string trend_str = jsonValueByKey(json, "trend_type");
   string time_str  = jsonValueByKey(json, "time");
   string k_str      = jsonValueByKey(json, "k_value");
   string exit_str = jsonValueByKey(json, "exit");
   double price = StringToDouble(price_str);
   double k_val = StringToDouble(k_str);
   bool exit_flag = (exit_str == "true");
   datetime signal_time = StringToTime(time_str);

   ManagePosition(signal, price, signal_time, exit_flag);
  }

void ManagePosition(string signal, double entry_price, datetime signal_time, bool exit_flag)
  {
   bool has_position = PositionSelect(g_symbol);

   string type = "";
   double open_price = 0.0;

   if(has_position)
     {
      type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      open_price = PositionGetDouble(POSITION_PRICE_OPEN);
     }

   // === EXIT判定 ===
   if(exit_flag && has_position)
     {
      WriteTradeLog("EXIT", type, open_price, true);
      ClosePosition();
      Print("[DEBUG] Flask-triggered EXIT: closed ", type, " position.");
      has_position = false;
     }

   // === ENTRY判定（1バー1回）===
  bool same_signal_bar = (signal == last_signal && signal_time == last_signal_time);

   if(!has_position && (signal == "BUY" || signal == "SELL"))
     {
      if(!same_signal_bar)
        {
         OpenPosition(signal, entry_price);
         Print("[DEBUG] Entry executed: ", signal);
        }
      else
         Print("[DEBUG] Same signal/bar. ENTRY skipped.");
     }

  }

void OpenPosition(string signal, double price)
  {
   // --- ATRハンドル取得 ---
   int atr_handle = iATR(g_symbol, PERIOD_CURRENT, 14);
   double atr_values[];
   double atr;

   // --- ATR値取得（バー0の1本分） ---
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_values) <= 0)
     {
      Print("[ERROR] ATR取得失敗。代替SLを使用します。");
      atr = sl_pips * point;  // 代替：静的SL
     }
   else
     {
      atr = atr_values[0];
     }

   // --- SLをATRに基づいて設定 ---
  double market_price = (signal == "BUY") ? SymbolInfoDouble(g_symbol, SYMBOL_ASK)
                                          : SymbolInfoDouble(g_symbol, SYMBOL_BID);
  double sl = (signal == "BUY") ? market_price - atr : market_price + atr;

   // --- エントリー ---
bool result;
string signal_label = "ENTRY_" + signal + "_" + IntegerToString(GetTickCount());  // 一意なラベル名
datetime now = TimeCurrent();

if(signal == "BUY")
  result = trade.Buy(lot_size, g_symbol, 0, sl, 0, "Auto BUY");
else
  result = trade.Sell(lot_size, g_symbol, 0, sl, 0, "Auto SELL");

// === オブジェクト描画 ===
if(!ObjectCreate(0, signal_label, OBJ_TEXT, 0, now, price))
  Print("[ERROR] ObjectCreate failed: ", GetLastError());
else
  {
   ObjectSetInteger(0, signal_label, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, signal_label, OBJPROP_TEXT, signal);
   ObjectSetInteger(0, signal_label, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, signal_label, OBJPROP_CORNER, 0);
  }

WriteTradeLog("ENTRY", signal, price, result);

   // --- デバッグ出力 ---
   uint retcode = trade.ResultRetcode();
   Print("[DEBUG] OpenPosition(", signal, "): market_price=", DoubleToString(price,5),
         ", SL=", DoubleToString(sl,5),
         ", ATR=", DoubleToString(atr,5),
         ", success=", (result ? "true" : "false"),
         ", retcode=", IntegerToString((int)retcode));
  }


void ClosePosition()
  {
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   bool result = trade.PositionClose(ticket);
   uint retcode = trade.ResultRetcode();
   Print("[DEBUG] ClosePosition: ticket=", IntegerToString((int)ticket), ", result=", (result ? "true" : "false"), ", retcode=", IntegerToString((int)retcode));
  }

string jsonValueByKey(string json, string key)
  {
   string pattern = "\"" + key + "\"";
   int key_pos = StringFind(json, pattern);
   if(key_pos == -1) return "";

   int colon_pos = StringFind(json, ":", key_pos);
   if(colon_pos == -1) return "";

   int val_start = colon_pos + 1;

   // 値が "..." か直接数値かを判定
   if(StringGetCharacter(json, val_start) == '\"')
     {
      val_start++;
      int val_end = StringFind(json, "\"", val_start);
      if(val_end == -1) return "";
      return StringSubstr(json, val_start, val_end - val_start);
     }
   else
     {
      // 数値または bool/null 対応（カンマ or } まで）
      int val_end = StringFind(json, ",", val_start);
      if(val_end == -1)
         val_end = StringFind(json, "}", val_start);
      if(val_end == -1) return "";
      return StringSubstr(json, val_start, val_end - val_start);
     }
  }


void WriteTradeLog(string action, string signal, double price, bool success)
  {
   int file = FileOpen("trade_log.csv", FILE_CSV | FILE_READ | FILE_WRITE | FILE_ANSI);
   if(file != INVALID_HANDLE)
     {
      FileSeek(file, 0, SEEK_END);
      FileWrite(file,
                TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS),
                action,
                signal,
                DoubleToString(price, 5),
                success);
      FileClose(file);
     }
  }
void CleanupOldObjects()
{
   datetime now = TimeCurrent();
   int total = ObjectsTotal(0);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      // ENTRYまたはEXITで始まるオブジェクトだけを対象
      if(StringFind(name, "ENTRY_") == 0 || StringFind(name, "EXIT_") == 0)
      {
         datetime created_time;
         if(ObjectGetInteger(0, name, OBJPROP_TIME, 0, created_time))
         {
            if((now - created_time) > 7 * 24 * 60 * 60)  // 7日 = 604800秒
            {
               ObjectDelete(0, name);
               Print("[DEBUG] Deleted old object: ", name);
            }
         }
      }
   }
}