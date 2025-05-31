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
    for code, name in area_mapping.items():
        if name.startswith('臺北市') or name.startswith('新北市'):
            taipei_codes.append(code)
    
    # 篩選資料
    filtered_df = df[df['鄉鎮市區碼'].isin(taipei_codes)].copy()
    
    # 新增區域名稱欄位（移除城市前綴）
    filtered_df['區域名稱'] = filtered_df['鄉鎮市區碼'].map(
        lambda x: area_mapping[x].replace('臺北市', '').replace('新北市', '') if x in area_mapping else ''
    )
    
    return filtered_df

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
    
    # 從資料夾名稱提取年份
    year = os.path.basename(year_folder).replace('年醫院病床統計', '')
    df['年份'] = year
    
    return df

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
    
    all_data = []
    
    # 處理每個年份的資料
    for folder in year_folders:
        print(f"處理 {folder}...")
        year_data = process_year_data(folder)
        
        if year_data is not None:
            # 篩選台北市和新北市資料
            filtered_data = filter_taipei_areas(year_data, area_mapping)
            
            if not filtered_data.empty:
                all_data.append(filtered_data)
                print(f"  - 篩選出 {len(filtered_data)} 筆資料")
            else:
                print(f"  - 警告: 沒有找到台北市或新北市的資料")
    
    if not all_data:
        print("錯誤: 沒有找到任何有效資料")
        return
    
    # 合併所有年份資料
    print("合併所有年份資料...")
    combined_df = pd.concat(all_data, ignore_index=True)
    
    # 重新排列欄位順序，將年份和區域名稱放在前面
    cols = ['年份', '鄉鎮市區碼', '區域名稱'] + [col for col in combined_df.columns if col not in ['年份', '鄉鎮市區碼', '區域名稱']]
    combined_df = combined_df[cols]
    
    # 按年份和區域代碼排序
    combined_df = combined_df.sort_values(['年份', '鄉鎮市區碼']).reset_index(drop=True)
    
    # 儲存結果
    output_file = "台北新北醫院病床統計_合併資料.csv"
    combined_df.to_csv(output_file, index=False, encoding='utf-8-sig')
    
    print(f"處理完成！")
    print(f"總共處理了 {len(combined_df)} 筆資料")
    print(f"涵蓋年份: {sorted(combined_df['年份'].unique())}")
    print(f"涵蓋區域: {sorted(combined_df['區域名稱'].unique())}")
    print(f"結果已儲存至: {output_file}")
    
    # 顯示資料摘要
    print("\n資料摘要:")
    print(f"欄位數量: {len(combined_df.columns)}")
    print(f"主要欄位: {list(combined_df.columns[:10])}")
    
    # 顯示各年份資料筆數
    print("\n各年份資料筆數:")
    year_counts = combined_df['年份'].value_counts().sort_index()
    for year, count in year_counts.items():
        print(f"  {year}年: {count} 筆")

if __name__ == "__main__":
    main()
