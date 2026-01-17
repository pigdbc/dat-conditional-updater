# DAT Conditional Updater / DAT条件更新工具

类似 SQL UPDATE 的 DAT 文件条件更新工具，支持二进制大端存储。

## 📁 文件结构

```
4-DATConditionalUpdater/
├── in/                          ← 输入文件夹 (放置原始DAT文件)
├── out/                         ← 输出文件夹 (自动生成)
├── log/                         ← 日志文件夹 (自动生成)
├── update_dat_中文版.ps1        ← PowerShell脚本
└── README.md
```

## 🚀 快速开始

```powershell
# 1. 将DAT文件放入 in/ 文件夹
# 2. 运行脚本
.\update_dat_中文版.ps1 -FileName "yourfile.dat"

# 或使用默认文件名 data.dat
.\update_dat_中文版.ps1
```

## ⚙️ 规则配置

在脚本中修改 `$UpdateRules` 数组：

```powershell
$UpdateRules = @(
    @{
        Name = "Rule-1"
        # WHERE 条件 (所有条件必须同时满足 - AND关系)
        Conditions = @(
            @{ StartByte = 50;  Length = 2; Value = 02 },    # 第50~51位 = 02
            @{ StartByte = 78;  Length = 3; Value = 534 }    # AND 第78~80位 = 534
        )
        # SET 修改操作
        Updates = @(
            @{ StartByte = 70;  Length = 3; Value = 056 }    # 则修改第70~72位为056
        )
    }
)
```

等同于 SQL:
```sql
UPDATE table 
SET field_70_72 = 056 
WHERE field_50_51 = 02 AND field_78_80 = 534
```

## 📌 大端存储说明

| 数值 | 长度 | 大端字节 |
|------|------|----------|
| 02   | 2字节 | `00 02` |
| 534  | 3字节 | `00 02 16` |
| 77   | 2字节 | `00 4D` |

脚本会自动将配置中的数值转换为大端字节进行匹配和写入。

## 📝 日志示例

```
[#   2] UPDATED
  Rule-1: [70-72] 0 → 56 (00 00 00 → 00 00 38)
[#   5] UPDATED
  Rule-2: [300-301] 0 → 77 (00 00 → 00 4D)

处理摘要:
  修改记录数: 2 / 100
  Rule-1 命中次数: 1
  Rule-2 命中次数: 1
```

## 📄 License

MIT License
