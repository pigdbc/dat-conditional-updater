# DAT Conditional Updater / DAT条件更新工具

类似 SQL UPDATE 的 DAT 文件条件更新工具，支持 BigEndianUnicode (UTF-16BE) 编码。

## 📁 文件结构

```
4-dat-conditional-updater/
├── in/                          ← 输入文件夹 (放置原始DAT文件)
├── out/                         ← 输出文件夹 (自动生成)
├── log/                         ← 日志文件夹 (自动生成)
├── config.ini                   ← 配置文件
├── update_dat.ps1              ← PowerShell脚本
└── README.md
```

## 🚀 快速开始

### PowerShell
```powershell
.\update_dat.ps1 -FileName "data.dat"
```

## ⚙️ 配置文件说明

规则配置已从代码中分离，统一使用 `config.ini` 文件：

```ini
[Settings]
RecordSize = 1300        # 每条记录的字符数
HeaderMarker = 1         # 头部记录标识符
DataMarker = 2           # 数据记录标识符

[Rule-1]
# 条件：多个条件用逗号分隔，格式为 名称:字符位置:期望值
Conditions = 条件A:50:02, 条件B:78:534
# 更新：格式为 名称:字符位置:新值
Updates = 更新值:70:056

# 也支持从起始位置写入多字符，例如：
Conditions = City:20:東京都
Updates = City:20:神奈川

[Rule-2]
Conditions = 数値条件:234:99
Updates = 数値更新:300:77
```

等同于 SQL:
```sql
UPDATE table SET Char70='056' 
WHERE Char50='02' AND Char78='534'
```

## 📌 编码说明

本工具使用 **BigEndianUnicode (UTF-16BE)** 编码：
- 每个字符占用 2 字节
- 高位字节在前，例如字符 "A" 编码为 `0x00 0x41`

## 📝 运行示例

```
╔══════════════════════════════════════════════════════════════╗
║  DAT Conditional Updater (BigEndianUnicode) - INI Config     ║
╚══════════════════════════════════════════════════════════════╝
Config: config.ini
Input:  in/data.dat
Output: out/data.dat

  Rule-1: IF Char50='02' AND Char78='534' THEN SET Char70='056'
  Rule-2: IF Char234='99' THEN SET Char300='77'

[#   2] UPDATED
  Rule-1: 更新値 '000' → '056'
[#   3] UPDATED
  Rule-1: 更新値 '000' → '056'

Summary: 3/5 records updated
  Rule-1 hits: 2
  Rule-2 hits: 1
```

## 📄 License

MIT License
