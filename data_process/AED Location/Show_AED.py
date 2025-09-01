import pandas as pd

# 讀取 .ods 檔案
df = pd.read_csv('AED20250531.csv')

# 資料塞選
df = df[["場所分類", "場所類型"]]
print(df)