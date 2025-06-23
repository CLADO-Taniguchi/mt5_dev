# MQL5 iCustom MTFインジケーター 安定化手法

`iCustom` を使ってマルチタイムフレーム（MTF）インジケーターを作成する際に発生する代表的な問題と、その最終的な解決策のまとめ。

### 問題1：エラー4806 (ERR_INDICATOR_DATA_NOT_FOUND)

-   **原因**:
    `OnInit`関数内で`iCustom`を呼び出す際、データソースとなる高位時間足のヒストリーデータが、まだターミナルにダウンロードされていないために発生する競合状態（レースコンディション）。
-   **解決策**:
    `iCustom`を呼び出す**前**に、`SeriesInfoInteger`と`Sleep`を使った待機ループを設置する。これにより、高位時間足のデータが利用可能になるのを意図的に待ち、エラーを確実に回避する。

```c++
// OnInit()内
int attempts = 0;
while(SeriesInfoInteger(_Symbol, Source_Timeframe, SERIES_BARS_COUNT) < 2 && attempts < 20)
{
    Sleep(500); // 0.5秒待機
    SeriesInfoInteger(_Symbol, Source_Timeframe, SERIES_BARS_COUNT);
    attempts++;
}
```

### 問題2：データは取得できるのに、チャートに描画されない

-   **原因**:
    インジケーターバッファの配列の「向き」と、`OnCalculate`内の計算ループの「向き」が一致していない。
    -   `for(int i = ...; i < rates_total; i++)` というループは、古いデータ（インデックス小）から新しいデータ（インデックス大）へと進む。
    -   一方、バッファが`ArraySetAsSeries(..., true)`（時系列配列）になっていると、インデックス0が最新データを指すため、データがバッファの逆側に書き込まれてしまい、結果として描画されない。
-   **解決策**:
    `OnInit`内ですべてのインジケーターバッファを`ArraySetAsSeries(..., false)`に設定し、計算ループの向きとバッファの向きを「古い→新しい」で完全に一致させる。

```c++
// OnInit()内
ArraySetAsSeries(hmaBuffer, false);
ArraySetAsSeries(hmaColors, false);
ArraySetAsSeries(buySignalBuffer, false);
ArraySetAsSeries(sellSignalBuffer, false);
```

### 問題3：データが時間的にずれて表示される

-   **原因**:
    下位足と上位足のローソク足の時間軸が同期されていない。
-   **解決策**:
    `OnCalculate`内のループで、`iBarShift()`関数を必ず使用する。これにより、下位足の各バーの時刻に対応する上位足の正しいバーインデックスを計算し、データを正確な位置にマッピングする。

```c++
// OnCalculate()内
for(int i = start_bar; i < rates_total; i++)
{
    // 現在のバー(i)の時刻に対応する、高位時間足のバーインデックス(mtf_index)を取得
    int mtf_index = iBarShift(_Symbol, Source_Timeframe, time[i]);

    // インデックスを使ってバッファに値をセット
    hmaBuffer[i] = mtf_hma[mtf_index];
}
``` 