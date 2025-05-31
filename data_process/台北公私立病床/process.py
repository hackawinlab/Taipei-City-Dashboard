import pandas as pd
import os
import glob
from pathlib import Path
import chardet

def detect_encoding(file_path):
    """檢測檔案編碼"""
    with open(file_path, 'rb') as f:
        raw_data = f.read()
        result = chardet.detect(raw_data)
        return result['encoding']

def load_area_mapping():
    """載入區域代碼對應表"""
    mapping_file = "欄位說明.csv"
    
    # 嘗試不同編碼
    encodings = ['utf-8', 'big5', 'cp950', 'gb2312']
    df_mapping = None
    
    for encoding in encodings:
        try:
            df_mapping = pd.read_csv(mapping_file, encoding=encoding)
            print(f"成功使用 {encoding} 編碼讀取欄位說明檔案")
            break
        except UnicodeDecodeError:
            continue
    
    if df_mapping is None:
        # 使用自動檢測編碼
        detected_encoding = detect_encoding(mapping_file)
        print(f"自動檢測到編碼: {detected_encoding}")
        df_mapping = pd.read_csv(mapping_file, encoding=detected_encoding)
    
    # 建立區域代碼對應字典
    area_mapping = {}
    for _, row in df_mapping.iterrows():
        code = row['鄉鎮市區碼']
        # 使用103年以後的名稱，如果沒有則使用101、102年的名稱
        area_name = row['鄉鎮市區名稱(103年以後適用)'] if pd.notna(row['鄉鎮市區名稱(103年以後適用)']) else row['鄉鎮市區名稱(101、102年適用)']
        area_mapping[code] = area_name
    
    return area_mapping

def filter_taipei_areas(df, area_mapping):
    """篩選出台北市和新北市的資料，並移除城市名稱前綴"""
    # 篩選台北市和新北市的區域代碼
    taipei_codes = []
    new_taipei_codes = []
    
    for code, name in area_mapping.items():
        if name.startswith('臺北市'):
            taipei_codes.append(code)
        elif name.startswith('新北市'):
            new_taipei_codes.append(code)
    
    # 篩選台北市資料
    taipei_df = df[df['鄉鎮市區碼'].isin(taipei_codes)].copy()
    taipei_df['區域名稱'] = taipei_df['鄉鎮市區碼'].map(
        lambda x: area_mapping[x].replace('臺北市', '') if x in area_mapping else ''
    )
    
    # 篩選新北市資料
    new_taipei_df = df[df['鄉鎮市區碼'].isin(new_taipei_codes)].copy()
    new_taipei_df['區域名稱'] = new_taipei_df['鄉鎮市區碼'].map(
        lambda x: area_mapping[x].replace('新北市', '') if x in area_mapping else ''
    )
    
    # 合併雙北資料
    combined_df = pd.concat([taipei_df, new_taipei_df], ignore_index=True)
    combined_df['區域名稱'] = combined_df['鄉鎮市區碼'].map(
        lambda x: area_mapping[x].replace('臺北市', '').replace('新北市', '') if x in area_mapping else ''
    )
    
    return taipei_df, combined_df

def process_year_data(year_folder):
    """處理單一年份的資料"""
    # 尋找該年份的CSV檔案
    csv_files = glob.glob(os.path.join(year_folder, "hos_bed*.csv"))
    
    if not csv_files:
        print(f"警告: 在 {year_folder} 中找不到病床統計檔案")
        return None
    
    # 嘗試不同編碼讀取資料
    encodings = ['utf-8', 'big5', 'cp950', 'gb2312']
    df = None
    
    for encoding in encodings:
        try:
            df = pd.read_csv(csv_files[0], encoding=encoding)
            break
        except UnicodeDecodeError:
            continue
    
    if df is None:
        # 使用自動檢測編碼
        try:
            detected_encoding = detect_encoding(csv_files[0])
            print(f"  自動檢測到編碼: {detected_encoding}")
            df = pd.read_csv(csv_files[0], encoding=detected_encoding)
        except Exception as e:
            print(f"  錯誤: 無法讀取檔案 {csv_files[0]}: {e}")
            return None
    
    # 從資料夾名稱提取年份並格式化為"111年"格式
    year = os.path.basename(year_folder).replace('年醫院病床統計', '')
    df['年份'] = f"{year}年"
    
    return df

def save_data(df, filename, description):
    """儲存資料並顯示統計資訊"""
    if df.empty:
        print(f"警告: {description}沒有資料")
        return
    
    # 重新排列欄位順序
    base_cols = ['年份', '鄉鎮市區碼', '區域名稱']
    cols = base_cols + [col for col in df.columns if col not in base_cols]
    df = df[cols]
    
    # 按年份和區域代碼排序
    df = df.sort_values(['年份', '鄉鎮市區碼']).reset_index(drop=True)
    
    # 儲存檔案
    df.to_csv(filename, index=False, encoding='utf-8-sig')
    
    print(f"\n{description}:")
    print(f"  檔案: {filename}")
    print(f"  資料筆數: {len(df)}")
    print(f"  涵蓋年份: {sorted(df['年份'].unique())}")
    print(f"  涵蓋區域: {sorted(df['區域名稱'].unique())}")
    
    # 顯示各年份資料筆數
    year_counts = df['年份'].value_counts().sort_index()
    print(f"  各年份資料筆數:")
    for year, count in year_counts.items():
        print(f"    {year}: {count} 筆")

def main():
    """主要處理函數"""
    print("開始處理台北公私立病床統計資料...")
    
    # 載入區域代碼對應表
    area_mapping = load_area_mapping()
    print(f"載入了 {len(area_mapping)} 個區域代碼對應")
    
    # 取得所有年份資料夾
    year_folders = glob.glob("*年醫院病床統計")
    year_folders.sort()
    
    print(f"找到 {len(year_folders)} 個年份資料夾")
    
    taipei_data = []
    combined_data = []
    
    # 處理每個年份的資料
    for folder in year_folders:
        print(f"處理 {folder}...")
        year_data = process_year_data(folder)
        
        if year_data is not None:
            # 篩選台北市和雙北資料
            filtered_taipei, filtered_combined = filter_taipei_areas(year_data, area_mapping)
            
            if not filtered_taipei.empty:
                taipei_data.append(filtered_taipei)
                combined_data.append(filtered_combined)
                print(f"  - 台北市: {len(filtered_taipei)} 筆")
                print(f"  - 雙北合併: {len(filtered_combined)} 筆")
            else:
                print(f"  - 警告: 沒有找到台北市的資料")
    
    if not taipei_data:
        print("錯誤: 沒有找到任何有效資料")
        return
    
    # 合併所有年份資料
    print("\n合併所有年份資料...")
    combined_taipei_df = pd.concat(taipei_data, ignore_index=True) if taipei_data else pd.DataFrame()
    combined_all_df = pd.concat(combined_data, ignore_index=True) if combined_data else pd.DataFrame()
    
    # 儲存兩個檔案
    save_data(combined_taipei_df, "台北市醫院病床統計.csv", "台北市資料")
    save_data(combined_all_df, "雙北醫院病床統計_合併資料.csv", "雙北合併資料")
    
    print(f"\n處理完成！")
    print(f"已生成兩個檔案:")
    print(f"  1. 台北市醫院病床統計.csv (僅台北市)")
    print(f"  2. 雙北醫院病床統計_合併資料.csv (台北市+新北市)")

if __name__ == "__main__":
    main()
