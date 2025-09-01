import pandas as pd
import os

def process_cancer_data():
    """
    處理癌症統計CSV文件：
    1. 將中文欄位名稱改成英文
    2. 只保留新北市和台北市的資料
    3. 刪除性別為"全"的資料
    4. 將年份格式化為帶有"年"字的格式
    5. 清理數值欄位格式（移除逗號和多餘空格）
    """
    
    # 讀取CSV文件
    input_file = "68-111年縣市別性別癌症別發生率資料_Final.csv"
    
    print("正在讀取CSV文件...")
    df = pd.read_csv(input_file, encoding='utf-8')
    
    print(f"原始資料筆數: {len(df)}")
    print(f"原始欄位: {list(df.columns)}")
    
    # 定義欄位名稱對應表（中文 -> 英文）
    column_mapping = {
        '癌症診斷年': 'diagnosis_year',
        '性別': 'gender',
        '縣市別': 'city',
        '癌症別': 'cancer_type',
        '年齡標準化發生率  WHO 2000世界標準人口 (每10萬人口) ': 'age_standardized_incidence_rate',
        '癌症發生數': 'cancer_cases',
        '平均年齡': 'average_age',
        '年齡中位數': 'median_age',
        '粗率 (每10萬人口)': 'crude_rate'
    }
    
    # 重新命名欄位
    df = df.rename(columns=column_mapping)
    print(f"重新命名後的欄位: {list(df.columns)}")
    
    # 清理數值欄位格式
    print("正在清理數值欄位格式...")
    
    # 清理癌症發生數：移除逗號、引號和多餘空格
    df['cancer_cases'] = df['cancer_cases'].astype(str).str.replace(',', '').str.replace('"', '').str.strip()
    
    # 清理其他數值欄位的空格
    numeric_columns = ['age_standardized_incidence_rate', 'average_age', 'median_age', 'crude_rate']
    for col in numeric_columns:
        if col in df.columns:
            df[col] = df[col].astype(str).str.strip()
    
    # 將數值欄位轉換為適當的數據類型
    try:
        df['cancer_cases'] = pd.to_numeric(df['cancer_cases'], errors='coerce')
        df['age_standardized_incidence_rate'] = pd.to_numeric(df['age_standardized_incidence_rate'], errors='coerce')
        df['average_age'] = pd.to_numeric(df['average_age'], errors='coerce')
        df['median_age'] = pd.to_numeric(df['median_age'], errors='coerce')
        df['crude_rate'] = pd.to_numeric(df['crude_rate'], errors='coerce')
        print("數值欄位轉換完成！")
    except Exception as e:
        print(f"數值轉換時發生錯誤: {e}")
    
    # 篩選條件1: 只保留新北市和台北市
    cities_to_keep = ['臺北市', '台北市']  # 包含可能的不同寫法
    df_filtered = df[df['city'].isin(cities_to_keep)]
    print(f"篩選縣市後資料筆數: {len(df_filtered)}")
    
    # 篩選條件2: 刪除性別為"全"的資料
    df_filtered = df_filtered[df_filtered['gender'] != '全']
    print(f"刪除性別為'全'後資料筆數: {len(df_filtered)}")
    
    # 新增功能: 格式化年份，將數字轉換為帶有"年"字的格式
    print("正在格式化年份...")
    df_filtered['diagnosis_year'] = df_filtered['diagnosis_year'].astype(str) + '年'
    print("年份格式化完成！")
    
    # 顯示格式化後的年份範例
    unique_years = df_filtered['diagnosis_year'].unique()
    print(f"格式化後的年份範例: {sorted(unique_years)[:5]}...{sorted(unique_years)[-5:]}")
    
    # 顯示剩餘的性別類別
    print(f"剩餘的性別類別: {df_filtered['gender'].unique()}")
    
    # 顯示剩餘的縣市
    print(f"剩餘的縣市: {df_filtered['city'].unique()}")
    
    # 檢查清理後的數據樣本
    print("\n清理後的數據樣本:")
    sample_data = df_filtered[['diagnosis_year', 'gender', 'city', 'cancer_type', 'cancer_cases']].head()
    print(sample_data)
    
    # 儲存處理後的資料
    output_file = "processed_cancer_data.csv"
    df_filtered.to_csv(output_file, index=False, encoding='utf-8')
    print(f"處理完成！已儲存至: {output_file}")
    
    # 顯示處理後資料的基本統計
    print("\n處理後資料概覽:")
    print(df_filtered.head())
    
    # 檢查是否有空值
    print("\n空值檢查:")
    print(df_filtered.isnull().sum())
    
    return df_filtered

if __name__ == "__main__":
    processed_data = process_cancer_data()
