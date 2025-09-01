import pandas as pd
import numpy as np

def process_mortality_data():
    """
    處理死亡機率數據，整合成未來10年(2025-2035)每年每10歲年齡段的死亡機率
    """
    # 讀取原始數據
    df = pd.read_csv('死亡機率.csv', encoding='utf-8')
    
    # 篩選2025-2035年的數據，只保留總計（不分性別）
    future_data = df[
        (df['西元年'] >= 2025) & 
        (df['西元年'] <= 2035) & 
        (df['性別'] == '總計')
    ].copy()
    
    # 處理年齡欄位，將"100歲及以上"轉換為100
    def parse_age(age_str):
        if '100歲及以上' in str(age_str):
            return 100
        else:
            # 提取數字部分
            return int(str(age_str).replace('歲', ''))
    
    future_data['年齡數值'] = future_data['年齡'].apply(parse_age)
    
    # 定義年齡段分組函數
    def get_age_group(age):
        if age < 30:
            return '30歲以下'
        elif age < 60:
            return '30-60歲'
        else:
            return '60歲以上'
    
    future_data['年齡段'] = future_data['年齡數值'].apply(get_age_group)
    
    # 處理死亡機率數值（處理科學記號）
    future_data['死亡機率'] = pd.to_numeric(future_data['死亡機率'], errors='coerce')
    
    # 按年份和年齡段分組，計算平均死亡機率
    yearly_age_group_mortality = future_data.groupby(['西元年', '年齡段'])['死亡機率'].mean().reset_index()
    
    # 排序年齡段
    age_order = ['30歲以下', '30-60歲', '60歲以上']
    yearly_age_group_mortality['年齡段'] = pd.Categorical(yearly_age_group_mortality['年齡段'], categories=age_order, ordered=True)
    yearly_age_group_mortality = yearly_age_group_mortality.sort_values(['西元年', '年齡段']).reset_index(drop=True)
    
    # 格式化死亡機率為更易讀的格式
    yearly_age_group_mortality['死亡機率_格式化'] = yearly_age_group_mortality['死亡機率'].apply(lambda x: f"{x:.6f}")
    
    # 輸出結果
    print("未來10年(2025-2035)各年份各年齡段死亡機率:")
    print("=" * 60)
    for year in sorted(yearly_age_group_mortality['西元年'].unique()):
        print(f"\n{year}年:")
        year_data = yearly_age_group_mortality[yearly_age_group_mortality['西元年'] == year]
        for _, row in year_data.iterrows():
            print(f"  {row['年齡段']}: {row['死亡機率_格式化']} ({row['死亡機率']:.2%})")
    
    # 保存處理後的數據
    output_data = yearly_age_group_mortality[['西元年', '年齡段', '死亡機率']].copy()
    output_data.to_csv('死亡機率_整合.csv', index=False, encoding='utf-8')
    
    print(f"\n處理完成！結果已保存至 '死亡機率_整合.csv'")
    
    # 顯示詳細統計信息
    print(f"\n詳細統計信息:")
    print(f"原始數據總行數: {len(df)}")
    print(f"篩選後數據行數: {len(future_data)}")
    print(f"年齡範圍: {future_data['年齡數值'].min()}歲 - {future_data['年齡數值'].max()}歲")
    print(f"年份範圍: {future_data['西元年'].min()}年 - {future_data['西元年'].max()}年")
    
    # 計算並顯示整體平均值
    print(f"\n整體平均死亡機率(2025-2035):")
    overall_avg = yearly_age_group_mortality.groupby('年齡段')['死亡機率'].mean()
    for age_group in age_order:
        if age_group in overall_avg.index:
            print(f"  {age_group}: {overall_avg[age_group]:.6f} ({overall_avg[age_group]:.2%})")
    
    return output_data

if __name__ == "__main__":
    result = process_mortality_data()
