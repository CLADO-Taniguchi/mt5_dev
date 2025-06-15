//+------------------------------------------------------------------+
//| HMA Backtest Script                                              |
//+------------------------------------------------------------------+
#property script_show_inputs

input string InputFileName = "EURUSD_M5.csv";      // 入力CSVファイル名
input int HMA_Period = 21;                          // HMA期間

// データ構造体
struct MarketData
{
    datetime time;
    double open;
    double high;
    double low;
    double close;
    double tick_volume;
    int spread;
    double real_volume;
};

// バックテスト結果構造体
struct TradeResult
{
    datetime entry_time;
    datetime exit_time;
    double entry_price;
    double exit_price;
    double hma_1;
    double hma_2;
    bool is_buy;
    bool is_win;
    double profit_pips;
};

// グローバル変数
MarketData marketData[];
double hmaBuffer[];
TradeResult tradeResults[];
int totalTrades = 0;
string OutputFileName; // 動的生成されるファイル名

//+------------------------------------------------------------------+
//| 出力ファイル名生成関数                                               |
//+------------------------------------------------------------------+
string GenerateOutputFileName()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    string filename = StringFormat("backtest_hma_%04d%02d%02d%02d%02d%02d.csv",
                                   dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
    return filename;
}

//+------------------------------------------------------------------+
//| 時刻文字列解析関数                                                  |
//+------------------------------------------------------------------+
datetime ParseTimeString(string time_str)
{
    // 入力文字列をクリーンアップ
    StringTrimLeft(time_str);
    StringTrimRight(time_str);
    
    // +00:00や類似のタイムゾーン表記を削除
    StringReplace(time_str, "+00:00", "");
    StringReplace(time_str, " +00:00", "");
    StringReplace(time_str, "T", " "); // ISO形式対応
    
    // まず標準的なStringToTimeを試行
    datetime result = StringToTime(time_str);
    
    if(result > D'1990.01.01 00:00:00' && result < D'2050.01.01 00:00:00') // 妥当な範囲チェック
    {
        return result;
    }
    
    // 手動解析（YYYY-MM-DD HH:MM:SS形式）
    string parts[];
    if(StringSplit(time_str, ' ', parts) >= 1)
    {
        string date_part = parts[0];
        string time_part = (parts.Size() > 1) ? parts[1] : "00:00:00";
        
        string date_components[];
        string time_components[];
        
        if(StringSplit(date_part, '-', date_components) == 3)
        {
            // 時間部分の解析
            if(StringSplit(time_part, ':', time_components) >= 2)
            {
                int year = (int)StringToInteger(date_components[0]);
                int month = (int)StringToInteger(date_components[1]);
                int day = (int)StringToInteger(date_components[2]);
                int hour = (int)StringToInteger(time_components[0]);
                int minute = (int)StringToInteger(time_components[1]);
                int second = (time_components.Size() >= 3) ? (int)StringToInteger(time_components[2]) : 0;
                
                // 妥当性チェック
                if(year >= 1990 && year <= 2050 && 
                   month >= 1 && month <= 12 && 
                   day >= 1 && day <= 31 &&
                   hour >= 0 && hour <= 23 && 
                   minute >= 0 && minute <= 59 && 
                   second >= 0 && second <= 59)
                {
                    MqlDateTime dt;
                    dt.year = year;
                    dt.mon = month;
                    dt.day = day;
                    dt.hour = hour;
                    dt.min = minute;
                    dt.sec = second;
                    dt.day_of_week = 0;
                    dt.day_of_year = 0;
                    
                    datetime manual_result = StructToTime(dt);
                    if(manual_result > 0)
                        return manual_result;
                }
            }
        }
    }
    
    return 0;
}

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("=== HMA Backtest Script Start ===");
    
    // 0. 出力ファイル名生成
    OutputFileName = GenerateOutputFileName();
    Print("Output file will be: ", OutputFileName);
    
    // 1. CSVファイル読み込み
    if(!LoadCSVData())
    {
        Print("ERROR: Failed to load CSV data");
        return;
    }
    
    // 2. HMA計算
    if(!CalculateHMA())
    {
        Print("ERROR: Failed to calculate HMA");
        return;
    }
    
    // 3. バックテスト実行
    if(!RunBacktest())
    {
        Print("ERROR: Failed to run backtest");
        return;
    }
    
    // 4. 結果出力
    if(!SaveResults())
    {
        Print("ERROR: Failed to save results");
        return;
    }
    
    // 5. 統計表示
    ShowStatistics();
    
    Print("=== HMA Backtest Script Complete ===");
}

//+------------------------------------------------------------------+
//| CSVデータ読み込み関数                                              |
//+------------------------------------------------------------------+
bool LoadCSVData()
{
    Print("Loading CSV data from: ", InputFileName);
    
    int file_handle = FileOpen(InputFileName, FILE_READ|FILE_TXT|FILE_ANSI);
    if(file_handle == INVALID_HANDLE)
    {
        Print("ERROR: Cannot open file ", InputFileName);
        return false;
    }
    
    // ヘッダー行をスキップ（BOM処理付き）
    string header = FileReadString(file_handle);
    
    // BOM削除（UTF-8 BOM: EF BB BF = ï»¿）
    if(StringFind(header, "ï»¿") == 0)
    {
        StringReplace(header, "ï»¿", "");
        Print("BOM detected and removed from header");
    }
    
    Print("Header: ", header);
    
    // データ行を読み込み
    int row_count = 0;
    while(!FileIsEnding(file_handle))
    {
        string line = FileReadString(file_handle);
        if(line == "") break;
        
        // CSV行を手動分割
        string parts[];
        int part_count = StringSplit(line, ',', parts);
        
        if(part_count < 9)
        {
            Print("Warning: Invalid line format at row ", row_count + 1, ": ", line);
            continue;
        }
        
        // 配列リサイズ
        ArrayResize(marketData, row_count + 1);
        
        // データ抽出と格納
        string symbol = parts[0];
        string time_str = parts[1];
        
        // 最初の行でBOM除去（念のため）
        if(row_count == 0 && StringFind(symbol, "ï»¿") >= 0)
        {
            StringReplace(symbol, "ï»¿", "");
        }
        
        double open = StringToDouble(parts[2]);
        double high = StringToDouble(parts[3]);
        double low = StringToDouble(parts[4]);
        double close = StringToDouble(parts[5]);
        double tick_volume = StringToDouble(parts[6]);
        int spread = (int)StringToInteger(parts[7]);
        double real_volume = StringToDouble(parts[8]);
        
        // 時刻解析
        datetime parsed_time = ParseTimeString(time_str);
        
        // データ格納
        marketData[row_count].time = parsed_time;
        marketData[row_count].open = open;
        marketData[row_count].high = high;
        marketData[row_count].low = low;
        marketData[row_count].close = close;
        marketData[row_count].tick_volume = tick_volume;
        marketData[row_count].spread = spread;
        marketData[row_count].real_volume = real_volume;
        
        row_count++;
        
        // 進捗表示（1000行毎）
        if(row_count % 1000 == 0)
        {
            Print("Loaded ", row_count, " rows...");
        }
    }
    
    FileClose(file_handle);
    
    Print("Total data loaded: ", row_count, " rows");
    if(row_count > 0)
    {
        Print("Date range: ", TimeToString(marketData[0].time), " to ", TimeToString(marketData[row_count-1].time));
    }
    
    return row_count > HMA_Period + 10; // 最低限のデータ確認
}

//+------------------------------------------------------------------+
//| HMA計算関数                                                        |
//+------------------------------------------------------------------+
bool CalculateHMA()
{
    Print("Calculating HMA with period: ", HMA_Period);
    
    int data_size = ArraySize(marketData);
    ArrayResize(hmaBuffer, data_size);
    ArrayInitialize(hmaBuffer, 0.0);
    
    int sqrtPeriod = (int)MathSqrt(HMA_Period);
    double rawWMA[];
    ArrayResize(rawWMA, data_size);
    ArrayInitialize(rawWMA, 0.0);
    
    // 中間WMA計算
    for(int i = HMA_Period - 1; i < data_size; i++)
    {
        double wma_half = CalculateWMA(i, HMA_Period / 2, marketData);
        double wma_full = CalculateWMA(i, HMA_Period, marketData);
        rawWMA[i] = 2 * wma_half - wma_full;
    }
    
    // HMA本体計算
    for(int i = HMA_Period - 1; i < data_size; i++)
    {
        hmaBuffer[i] = CalculateWMAFromArray(i, sqrtPeriod, rawWMA);
    }
    
    Print("HMA calculation completed");
    return true;
}

//+------------------------------------------------------------------+
//| WMA計算関数（MarketData配列用）                                      |
//+------------------------------------------------------------------+
double CalculateWMA(int pos, int length, const MarketData &data[])
{
    double numerator = 0.0;
    double denominator = 0.0;
    
    for(int i = 0; i < length; i++)
    {
        int index = pos - i;
        if(index < 0) break;
        
        double weight = length - i;
        numerator += data[index].close * weight;
        denominator += weight;
    }
    
    return (denominator != 0.0) ? numerator / denominator : 0.0;
}

//+------------------------------------------------------------------+
//| WMA計算関数（double配列用）                                          |
//+------------------------------------------------------------------+
double CalculateWMAFromArray(int pos, int length, const double &data[])
{
    double numerator = 0.0;
    double denominator = 0.0;
    
    for(int i = 0; i < length; i++)
    {
        int index = pos - i;
        if(index < 0) break;
        
        double weight = length - i;
        numerator += data[index] * weight;
        denominator += weight;
    }
    
    return (denominator != 0.0) ? numerator / denominator : 0.0;
}

//+------------------------------------------------------------------+
//| バックテスト実行関数                                                |
//+------------------------------------------------------------------+
bool RunBacktest()
{
    Print("Running backtest simulation...");
    
    int data_size = ArraySize(marketData);
    bool hasOpenPosition = false;
    int entryIndex = 0;
    bool isCurrentBuy = false;
    
    for(int i = HMA_Period + 2; i < data_size - 1; i++) // -1 for next bar access
    {
        if(hmaBuffer[i] == 0.0 || hmaBuffer[i-1] == 0.0 || hmaBuffer[i-2] == 0.0)
            continue;
            
        // トレンド方向判定
        double dy_current = hmaBuffer[i] - hmaBuffer[i-1];
        double dy_previous = hmaBuffer[i-1] - hmaBuffer[i-2];
        
        int currentTrend = (dy_current > 0) ? 0 : 1;  // 0=上昇, 1=下降
        int prevTrend = (dy_previous > 0) ? 0 : 1;
        
        // トレンド反転チェック
        if(currentTrend != prevTrend)
        {
            if(!hasOpenPosition)
            {
                // 新規エントリー
                entryIndex = i;
                isCurrentBuy = (currentTrend == 0);
                hasOpenPosition = true;
                
                if(i % 1000 == 0)
                {
                    Print("Entry at index ", i, " - ", (isCurrentBuy ? "BUY" : "SELL"));
                }
            }
            else
            {
                // ポジション決済
                ArrayResize(tradeResults, totalTrades + 1);
                
                // 次のバーのopen価格で約定
                double entry_price = (entryIndex < data_size - 1) ? marketData[entryIndex + 1].open : marketData[entryIndex].close;
                double exit_price = (i < data_size - 1) ? marketData[i + 1].open : marketData[i].close;
                
                // 勝敗判定
                bool is_win;
                double profit_pips;
                
                if(isCurrentBuy)
                {
                    profit_pips = (exit_price - entry_price) * 10000; // pips計算
                    is_win = (exit_price > entry_price);
                }
                else
                {
                    profit_pips = (entry_price - exit_price) * 10000; // pips計算
                    is_win = (exit_price < entry_price);
                }
                
                // 結果格納
                tradeResults[totalTrades].entry_time = marketData[entryIndex].time;
                tradeResults[totalTrades].exit_time = marketData[i].time;
                tradeResults[totalTrades].entry_price = entry_price;
                tradeResults[totalTrades].exit_price = exit_price;
                tradeResults[totalTrades].hma_1 = hmaBuffer[i-1];
                tradeResults[totalTrades].hma_2 = hmaBuffer[i-2];
                tradeResults[totalTrades].is_buy = isCurrentBuy;
                tradeResults[totalTrades].is_win = is_win;
                tradeResults[totalTrades].profit_pips = profit_pips;
                
                totalTrades++;
                hasOpenPosition = false;
                
                if(totalTrades % 10 == 0)
                {
                    Print("Completed trade #", totalTrades, " - ", (is_win ? "WIN" : "LOSE"), " (", DoubleToString(profit_pips, 1), " pips)");
                }
            }
        }
    }
    
    Print("Backtest completed. Total trades: ", totalTrades);
    return true;
}

//+------------------------------------------------------------------+
//| 結果保存関数                                                       |
//+------------------------------------------------------------------+
bool SaveResults()
{
    Print("Saving results to: ", OutputFileName);
    
    int file_handle = FileOpen(OutputFileName, FILE_WRITE|FILE_CSV|FILE_ANSI);
    if(file_handle == INVALID_HANDLE)
    {
        Print("ERROR: Cannot create output file ", OutputFileName);
        return false;
    }
    
    // ヘッダー行
    FileWrite(file_handle, "unix_time", "open", "hma_1", "hma_2", "exit", "isWin");
    
    // データ行
    for(int i = 0; i < totalTrades; i++)
    {
        // Unixタイムスタンプで出力
        long unix_timestamp = (long)tradeResults[i].exit_time;
        string open_str = DoubleToString(tradeResults[i].entry_price, 5);
        string hma1_str = DoubleToString(tradeResults[i].hma_1, 5);
        string hma2_str = DoubleToString(tradeResults[i].hma_2, 5);
        string exit_str = DoubleToString(tradeResults[i].exit_price, 5);
        string win_str = tradeResults[i].is_win ? "WIN" : "LOSE";
        
        FileWrite(file_handle, unix_timestamp, open_str, hma1_str, hma2_str, exit_str, win_str);
    }
    
    FileClose(file_handle);
    
    Print("Results saved successfully. Total trades written: ", totalTrades);
    return true;
}

//+------------------------------------------------------------------+
//| 統計表示関数                                                       |
//+------------------------------------------------------------------+
void ShowStatistics()
{
    if(totalTrades == 0)
    {
        Print("No trades to analyze");
        return;
    }
    
    int win_count = 0;
    double total_profit = 0.0;
    double max_profit = -999999.0;
    double max_loss = 999999.0;
    
    for(int i = 0; i < totalTrades; i++)
    {
        if(tradeResults[i].is_win)
            win_count++;
            
        total_profit += tradeResults[i].profit_pips;
        
        if(tradeResults[i].profit_pips > max_profit)
            max_profit = tradeResults[i].profit_pips;
            
        if(tradeResults[i].profit_pips < max_loss)
            max_loss = tradeResults[i].profit_pips;
    }
    
    double win_rate = (double)win_count / totalTrades * 100.0;
    double avg_profit = total_profit / totalTrades;
    
    Print("=== BACKTEST STATISTICS ===");
    Print("Total Trades: ", totalTrades);
    Print("Win Rate: ", DoubleToString(win_rate, 2), "%");
    Print("Total Profit: ", DoubleToString(total_profit, 1), " pips");
    Print("Average Profit: ", DoubleToString(avg_profit, 1), " pips");
    Print("Max Profit: ", DoubleToString(max_profit, 1), " pips");
    Print("Max Loss: ", DoubleToString(max_loss, 1), " pips");
    Print("==========================");
    Print("");
    Print("NOTE: unix_time column contains Unix timestamps.");
    Print("Convert to datetime in Excel: =A2/86400+DATE(1970,1,1)");
    Print("Convert in Python: pd.to_datetime(df['unix_time'], unit='s')");
}