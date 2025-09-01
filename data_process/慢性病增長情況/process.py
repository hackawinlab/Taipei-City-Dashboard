import pandas as pd

def process_chronic_disease_data():
    """
    Process chronic disease growth data:
    - Translate column names to English
    - Keep only total columns (remove gender-specific breakdowns)
    """
    
    # Read the original CSV file
    df = pd.read_csv('a15003001-2149041757.csv')
    
    # Create a mapping for the columns we want to keep
    # Only keeping total columns, removing gender-specific ones
    column_mapping = {
        '年份': 'year',
        '65歲之平均餘命/總計(歲)': 'life_expectancy_65_total',
        '80歲之平均餘命/總計(歲)': 'life_expectancy_80_total',
        '65歲以上死亡人數/心臟疾病/總計(人)': 'deaths_65_heart_disease_total',
        '65歲以上死亡人數/腦血管疾病/總計(人)': 'deaths_65_cerebrovascular_disease_total',
        '65歲以上死亡人數/事故傷害/總計(人)': 'deaths_65_accidents_total'
    }
    
    # Select only the columns we want to keep
    columns_to_keep = list(column_mapping.keys())
    df_cleaned = df[columns_to_keep].copy()
    
    # Rename columns to English
    df_cleaned.rename(columns=column_mapping, inplace=True)
    
    # Clean year column (remove "年" suffix)
    df_cleaned['year'] = df_cleaned['year'].str.replace('年', '')
    
    # Add cancer deaths total (from female column since no total was provided)
    # Note: This is an approximation as only female data was available
    df_original = pd.read_csv('a15003001-2149041757.csv')
    df_cleaned['deaths_65_cancer_female'] = df_original['65歲以上死亡人數/惡性腫瘤/女(人)']
    
    # Save the cleaned data
    df_cleaned.to_csv('a15003001-2149041757_cleaned.csv', index=False)
    
    print("Data processing completed!")
    print(f"Original columns: {len(df.columns)}")
    print(f"Cleaned columns: {len(df_cleaned.columns)}")
    print("\nCleaned column names:")
    for col in df_cleaned.columns:
        print(f"- {col}")
    
    return df_cleaned

if __name__ == "__main__":
    processed_data = process_chronic_disease_data()
