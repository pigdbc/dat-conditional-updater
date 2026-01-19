#!/usr/bin/env python3
"""
DAT Conditional Updater - Python version (BigEndianUnicode)
Reads configuration from config.ini
"""
import os
import sys
import configparser
from datetime import datetime

def parse_conditions(cond_str):
    """Parse 'Byte:Value, Byte:Value' format"""
    conditions = []
    for item in cond_str.split(','):
        item = item.strip()
        if ':' in item:
            byte_pos, value = item.split(':', 1)
            conditions.append({'StartByte': int(byte_pos), 'Value': value})
    return conditions

def parse_updates(upd_str):
    """Parse 'Byte:Value, Byte:Value' format"""
    return parse_conditions(upd_str)  # Same format

def load_config(config_file='config.ini'):
    """Load configuration from INI file"""
    config = configparser.ConfigParser()
    config.read(config_file, encoding='utf-8')
    
    settings = {
        'RecordSize': config.getint('Settings', 'RecordSize', fallback=1300),
        'HeaderMarker': config.getint('Settings', 'HeaderMarker', fallback=1),
        'DataMarker': config.getint('Settings', 'DataMarker', fallback=2),
    }
    
    rules = []
    for section in config.sections():
        if section.startswith('Rule-'):
            rule = {
                'Name': section,
                'Conditions': parse_conditions(config.get(section, 'Conditions', fallback='')),
                'Updates': parse_updates(config.get(section, 'Updates', fallback='')),
            }
            if rule['Conditions'] and rule['Updates']:
                rules.append(rule)
    
    return settings, rules

def main():
    # 使用脚本所在目录作为基础目录
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    
    filename = sys.argv[1] if len(sys.argv) > 1 else 'data.dat'
    config_file = os.path.join(BASE_DIR, sys.argv[2] if len(sys.argv) > 2 else 'config.ini')
    
    input_file = os.path.join(BASE_DIR, 'in', filename)
    output_file = os.path.join(BASE_DIR, 'out', filename)
    
    os.makedirs(os.path.join(BASE_DIR, 'out'), exist_ok=True)
    os.makedirs(os.path.join(BASE_DIR, 'log'), exist_ok=True)
    
    if not os.path.exists(config_file):
        print(f"Error: Config file {config_file} not found!")
        return 1
    
    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found!")
        return 1
    
    # Load config
    settings, rules = load_config(config_file)
    RECORD_SIZE = settings['RecordSize']
    HEADER_MARKER = 0x30 + settings['HeaderMarker']  # ASCII
    DATA_MARKER = 0x30 + settings['DataMarker']
    
    timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    log_file = os.path.join(BASE_DIR, 'log', f'{filename.replace(".dat", "")}_{timestamp}.log')
    
    logs = []
    def log(msg):
        logs.append(msg)
        print(msg)
    
    log("╔══════════════════════════════════════════════════════════════╗")
    log("║  DAT Conditional Updater (BigEndianUnicode) - INI Config     ║")
    log("╚══════════════════════════════════════════════════════════════╝")
    log(f"Config: {config_file}")
    log(f"Input:  {input_file}")
    log(f"Output: {output_file}")
    log(f"RecordSize: {RECORD_SIZE} bytes")
    log("")
    
    file_size = os.path.getsize(input_file)
    record_count = file_size // RECORD_SIZE
    log(f"File size: {file_size} bytes, Records: {record_count}, Rules: {len(rules)}")
    log("")
    
    # Show rules
    for rule in rules:
        conds = ' AND '.join([f"Byte{c['StartByte']}='{c['Value']}'" for c in rule['Conditions']])
        updates = ', '.join([f"Byte{u['StartByte']}='{u['Value']}'" for u in rule['Updates']])
        log(f"  {rule['Name']}: IF {conds} THEN SET {updates}")
    log("")
    log("─" * 64)
    
    modified_count = 0
    rule_hits = {rule['Name']: 0 for rule in rules}
    
    with open(input_file, 'rb') as f_in, open(output_file, 'wb') as f_out:
        for i in range(record_count):
            record = bytearray(f_in.read(RECORD_SIZE))
            record_num = i + 1
            first_byte = record[0]
            
            if first_byte == HEADER_MARKER:
                log(f"[#{record_num:4d}] HEADER - Skip")
            elif first_byte == DATA_MARKER:
                changes = []
                has_change = False
                
                for rule in rules:
                    all_match = True
                    for cond in rule['Conditions']:
                        offset = cond['StartByte'] - 1
                        expected = cond['Value'].encode('utf-16-be')
                        actual = bytes(record[offset:offset+len(expected)])
                        if actual != expected:
                            all_match = False
                            break
                    
                    if all_match:
                        for upd in rule['Updates']:
                            offset = upd['StartByte'] - 1
                            new_bytes = upd['Value'].encode('utf-16-be')
                            old_bytes = bytes(record[offset:offset+len(new_bytes)])
                            old_val = old_bytes.decode('utf-16-be', errors='replace')
                            
                            record[offset:offset+len(new_bytes)] = new_bytes
                            changes.append(f"  {rule['Name']}: Byte{upd['StartByte']} '{old_val}' → '{upd['Value']}'")
                        
                        has_change = True
                        rule_hits[rule['Name']] += 1
                
                if has_change:
                    log(f"[#{record_num:4d}] UPDATED")
                    for c in changes:
                        log(c)
                    modified_count += 1
            
            f_out.write(record)
    
    log("")
    log("─" * 64)
    log(f"Summary: {modified_count}/{record_count} records updated")
    for rule in rules:
        log(f"  {rule['Name']} hits: {rule_hits[rule['Name']]}")
    
    with open(log_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(logs))
    
    print(f"\n✓ Output: {output_file}")
    print(f"✓ Log: {log_file}")
    return 0

if __name__ == '__main__':
    sys.exit(main())
