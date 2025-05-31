import pandas as pd

# 讀取癌症發生率原始資料
cancer_path = 'cancer.csv'

# 嘗試讀取CSV
try:
    cancer_df = pd.read_csv(cancer_path, encoding='utf-8')
except:
    cancer_df = pd.read_csv(cancer_path, encoding='big5')

# 檢查欄位名稱是否正確
print("欄位名稱檢查:", cancer_df.columns.tolist())

# 篩選雙北資料（台北市、新北市）+ 年份
filtered_df = cancer_df[
    (cancer_df['縣市別'].isin(['台北市', '新北市'])) &
    (cancer_df['癌症診斷年'].between(2018, 2022))  # 107~111年對應的西元年
]

# 確認要重新命名的欄位名稱是否正確
for col in cancer_df.columns:
    if '年齡標準化發生率' in col:
        發生率欄位 = col
        break

# 欄位重新命名
filtered_df = filtered_df.rename(columns={
    '縣市別': '縣市',
    '性別': '性別',
    '癌症別': '癌症類別',
    '癌症診斷年': '年份',
    發生率欄位: '發生率'
})

# 輸出篩選後的CSV
output_path = 'cancer_cleaned.csv'
filtered_df.to_csv(output_path, index=False, encoding='utf-8-sig')

print(f'✅ 清洗完成！已輸出至 {output_path}')
