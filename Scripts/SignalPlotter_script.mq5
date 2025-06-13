//+------------------------------------------------------------------+
//|                                      SignalPlotter.mq5 (Script) |
//|     PythonのCSVからBUY/SELLシグナルをMT5チャートに描画する       |
//+------------------------------------------------------------------+

input string csv_file_name = "USDJPY_M5_signals.csv";

void OnStart()
  {
   int handle = FileOpen(csv_file_name, FILE_READ | FILE_CSV);
   if(handle == INVALID_HANDLE)
     {
      Print("File open error: ", csv_file_name);
      return;
     }

   while(!FileIsEnding(handle))
     {
      string time_str = FileReadString(handle);
      double open   = FileReadNumber(handle);
      double high   = FileReadNumber(handle);
      double low    = FileReadNumber(handle);
      double close  = FileReadNumber(handle);
      string signal = FileReadString(handle);

      datetime dt = StringToTime(time_str);
      if(dt == 0) continue;

      int shift = iBarShift(NULL, 0, dt, true);
      if(shift < 0) continue;

      double price = (signal == "BUY") ? low * 0.995 :
                     (signal == "SELL") ? high * 1.005 : 0;

      string objname = StringFormat("signal_%s_%d", signal, shift);

      if(signal == "BUY" || signal == "SELL")
        {
         ObjectCreate(0, objname, OBJ_ARROW, 0, iTime(NULL, 0, shift), price);
         ObjectSetInteger(0, objname, OBJPROP_ARROWCODE, signal == "BUY" ? 233 : 234);
         ObjectSetInteger(0, objname, OBJPROP_COLOR, signal == "BUY" ? clrLime : clrRed);
         ObjectSetInteger(0, objname, OBJPROP_WIDTH, 2);
        }
     }

   FileClose(handle);
   ChartRedraw();
  }
