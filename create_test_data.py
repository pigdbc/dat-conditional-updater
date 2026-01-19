#!/usr/bin/env python3
"""
Generate BigEndianUnicode test data for DAT Conditional Updater
"""
import os

def create_test_dat():
    record_size = 1300
    num_records = 5
    
    # 使用脚本所在目录作为基础目录
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    
    # Ensure in folder exists
    in_folder = os.path.join(BASE_DIR, 'in')
    os.makedirs(in_folder, exist_ok=True)
    
    output_file = os.path.join(in_folder, 'data.dat')
    with open(output_file, 'wb') as f:
        for i in range(num_records):
            record = bytearray(record_size)
            
            if i == 0:
                # Header record (starts with '1')
                record[0] = 0x31  # ASCII '1'
            else:
                # Data record (starts with '2')
                record[0] = 0x32  # ASCII '2'
                
                # Write test values in BigEndianUnicode (UTF-16BE)
                # At byte 50: "02" (for Rule-1 condition)
                if i in [1, 2]:  # Records 2 and 3 will match Rule-1
                    val = "02".encode('utf-16-be')
                    record[49:49+len(val)] = val
                    
                    # At byte 78: "534" (for Rule-1 condition)
                    val2 = "534".encode('utf-16-be')
                    record[77:77+len(val2)] = val2
                    
                    # At byte 70: initial value "000" (will be updated to "056")
                    val3 = "000".encode('utf-16-be')
                    record[69:69+len(val3)] = val3
                
                # At byte 234: "99" (for Rule-2 condition) 
                if i == 3:  # Record 4 will match Rule-2
                    val = "99".encode('utf-16-be')
                    record[233:233+len(val)] = val
                    
                    # At byte 300: initial value "00" (will be updated to "77")
                    val2 = "00".encode('utf-16-be')
                    record[299:299+len(val2)] = val2
            
            f.write(record)
    
    print(f"Created in/data.dat with {num_records} records ({num_records * record_size} bytes)")
    print("Records 2,3: Match Rule-1 (Byte50='02' AND Byte78='534')")
    print("Record 4: Match Rule-2 (Byte234='99')")

if __name__ == '__main__':
    create_test_dat()
