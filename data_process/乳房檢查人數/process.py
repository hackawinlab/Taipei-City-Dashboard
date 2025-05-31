import pandas as pd

def filter_taipei_data():
    # Read the CSV file
    df = pd.read_csv('A21030000I-L50001-001.csv')
    
    # Define the columns we want to keep for Taipei data
    taipei_columns = [
        '年別',  # Year
        '女性乳房攝影檢查人數',  # Total female breast screening count
        '年齡別＿30歲以下',  # Age group: under 30
        '年齡別＿31－40歲',  # Age group: 31-40
        '年齡別＿41－50歲',  # Age group: 41-50
        '年齡別＿51－65歲',  # Age group: 51-65
        '年齡別＿65歲以上',  # Age group: over 65
        '臺北業務組＿臺北市'  # Taipei City data
    ]
    
    # Filter the dataframe to keep only Taipei-related columns
    taipei_df = df[taipei_columns].copy()
    
    # Rename the Taipei column for clarity
    taipei_df = taipei_df.rename(columns={'臺北業務組＿臺北市': '臺北市乳房檢查人數'})
    
    # Save the filtered data
    taipei_df.to_csv('taipei_breast_screening_data.csv', index=False, encoding='utf-8-sig')
    
    print("已成功篩選台北市資料並儲存至 taipei_breast_screening_data.csv")
    print(f"原始資料欄位數: {len(df.columns)}")
    print(f"篩選後欄位數: {len(taipei_df.columns)}")
    print("\n篩選後的欄位:")
    for col in taipei_df.columns:
        print(f"- {col}")
    
    # Display the first few rows
    print("\n前5筆資料預覽:")
    print(taipei_df.head())
    
    return taipei_df

if __name__ == "__main__":
    taipei_data = filter_taipei_data()
