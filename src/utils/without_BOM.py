import os

input_path = "C:\MT5_portable\MQL5\Files\model_hma_result_20250615012532.csv"
output_path = "C:\MT5_portable\MQL5\Files\model_hma_result_20250615012532.csv_nobom.csv"

# BOM付きで開いて、BOMなしで書き直す
with open(input_path, "r", encoding="utf-8-sig") as fin:
    content = fin.read()

with open(output_path, "w", encoding="utf-8") as fout:
    fout.write(content)