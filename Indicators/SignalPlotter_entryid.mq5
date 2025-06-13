#property indicator_chart_window

struct Signal {
   datetime dt;
   string   type;
   double   price;
   string   trade_id;
   string   label;
};

input string csv_file_name = "m5_signals_stcas_20250604012505_nobom.csv";
input int gmt_offset_hours = 0;
Signal signals[1000];
int signal_count = 0;
bool loaded = false;

int find_column_index(string header_line, string column_name) {
   string columns[];
   int count = StringSplit(header_line, ',', columns);
   for(int i = 0; i < count; i++) {
      if(columns[i] == column_name){
      Print("col :" + i + " : " + column_name);
         return i;
      }
   }
   return -1;
}

bool LoadCSV() {
   int handle = FileOpen(csv_file_name, FILE_READ | FILE_TXT | FILE_ANSI, CP_UTF8);
   if(handle == INVALID_HANDLE) return false;

   string header_line = FileReadString(handle);

   int time_idx    = find_column_index(header_line, "time");
   int signal_idx  = find_column_index(header_line, "signal");
   int price_idx   = find_column_index(header_line, "price");
   int tradeid_idx = find_column_index(header_line, "trade_id");

   if(time_idx < 0 || signal_idx < 0 || price_idx < 0 || tradeid_idx < 0)
      return false;

   signal_count = 0;
   while(!FileIsEnding(handle) && signal_count < ArraySize(signals)) {
      string line = FileReadString(handle);
      StringReplace(line, "\"", "");
      string parts[];
      int count = StringSplit(line, ',', parts);
      if(count <= tradeid_idx) continue;

      datetime time_raw = StringToTime(parts[time_idx]);
      datetime dt = time_raw + gmt_offset_hours * 3600;

      signals[signal_count].dt       = dt;
      signals[signal_count].type     = parts[signal_idx];
      signals[signal_count].price    = StringToDouble(parts[price_idx]);
      signals[signal_count].trade_id = parts[tradeid_idx];
      signal_count++;
   }

   FileClose(handle);
   return true;
}

int OnInit() {
   loaded = LoadCSV();
   return(INIT_SUCCEEDED);
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
                const int &spread[]) {

   if(!loaded) return 0;

   if (prev_calculated == 0) {
      for(int i = 0; i < signal_count; i++) {
         double draw_price = signals[i].price;
         string label_name = signals[i].trade_id;
         string label_code = signals[i].trade_id;
         datetime dt = signals[i].dt;

         if(signals[i].type == "BUY") {
            ObjectCreate(0, label_name + "b_arw", OBJ_ARROW, 0, signals[i].dt, draw_price);
            ObjectSetInteger(0, label_name + "b_arw", OBJPROP_ARROWCODE, 233);         // ↑ 赤矢印
            ObjectSetInteger(0, label_name + "b_arw", OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, label_name + "b_arw", OBJPROP_WIDTH, 3);
            ObjectSetInteger(0, label_name + "b_arw", OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, label_name + "b_arw", OBJPROP_SELECTED, false);

            ObjectCreate(0, "b_" + label_name, OBJ_TEXT, 0, dt, draw_price - 0.03);
            ObjectSetString(0, "b_" + label_name, OBJPROP_TEXT, label_code);
            ObjectSetInteger(0, "b_" + label_name, OBJPROP_COLOR, clrWhite);
            ObjectSetInteger(0, "b_" + label_name, OBJPROP_ANCHOR, ANCHOR_CENTER);
            ObjectSetInteger(0, "b_" + label_name, OBJPROP_FONTSIZE, 10);
            Print("[DRAW_BUY] " + dt + " label_code: " + label_code);
         }

         if(signals[i].type == "SELL") {
            ObjectCreate(0, label_name + "s_arw", OBJ_ARROW, 0, signals[i].dt, draw_price);
            ObjectSetInteger(0, label_name + "s_arw", OBJPROP_ARROWCODE, 234);         
            ObjectSetInteger(0, label_name + "s_arw", OBJPROP_COLOR, clrBlue);
            ObjectSetInteger(0, label_name + "s_arw", OBJPROP_WIDTH, 3);
            ObjectSetInteger(0, label_name + "s_arw", OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, label_name + "s_arw", OBJPROP_SELECTED, false);

            ObjectCreate(0, "s_" + label_name, OBJ_TEXT, 0, dt, draw_price + 0.01);
            ObjectSetString(0, "s_" + label_name, OBJPROP_TEXT, label_code);
            ObjectSetInteger(0, "s_" + label_name, OBJPROP_COLOR, clrWhite);
            ObjectSetInteger(0, "s_" + label_name, OBJPROP_ANCHOR, ANCHOR_CENTER);
            ObjectSetInteger(0, "s_" + label_name, OBJPROP_FONTSIZE, 10);
            Print("[DRAW_SELL] " + dt + " label_code: " + label_code);
         }
      }
   }
   return(rates_total);
}