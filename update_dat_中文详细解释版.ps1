# ============================================
# DAT文件条件更新脚本 (中文详细解释版 - BigEndianUnicode)
# 功能：类似SQL UPDATE语句，根据条件匹配并更新指定字段
# 特点：支持多条件AND匹配 | UTF-16BE编码 | 流式处理大文件
# ============================================
#
# 【脚本原理说明】
# 本脚本的工作方式类似于数据库的UPDATE语句：
#   UPDATE table SET 字段=新值 WHERE 条件1 AND 条件2 AND ...
# 
# DAT文件是一种固定长度记录的二进制文件，每条记录占用固定的字节数。
# 本脚本逐条读取记录，检查是否满足指定条件，若满足则更新指定位置的值。
#
# 【编码说明】
# BigEndianUnicode（大端序UTF-16）是一种字符编码：
# - 每个字符占用2个字节（16位）
# - 大端序意味着高位字节在前，例如字符"A"编码为 0x00 0x41
# - 这与Windows常用的LittleEndianUnicode（0x41 0x00）相反
# ============================================

# ==================== 脚本参数 ====================
# 使用param块定义脚本参数，允许用户在运行时指定文件名
# 用法示例：.\update_dat_中文详细解释版.ps1 -FileName "mydata.dat"
# 如果不指定，默认使用"data.dat"
param(
    [string]$FileName = "data.dat"    # 要处理的DAT文件名（不含路径）
)

# ==================== 文件夹设置 ====================
# 定义输入、输出、日志三个文件夹的名称
# 这种结构便于管理文件：原始文件、处理后文件、处理日志分开存放
$BaseDir = $PSScriptRoot   # 脚本所在目录作为基础目录
$InFolder = Join-Path $BaseDir "in"     # 输入文件夹：存放待处理的原始DAT文件
$OutFolder = Join-Path $BaseDir "out"    # 输出文件夹：存放处理后的DAT文件
$LogFolder = Join-Path $BaseDir "log"    # 日志文件夹：存放处理日志，记录每次修改的详细信息

# ==================== 记录格式设置 ====================
# DAT文件由多条固定长度的记录组成，这里定义记录的格式参数
$RecordSize = 1300       # 每条记录的字节数（固定长度）
# 文件总大小 ÷ RecordSize = 记录总数

$HeaderMarker = 0x31       # 头部记录标识符，ASCII码0x31对应字符'1'
# 第一个字节为'1'的记录被视为头部记录，会被跳过

$DataMarker = 0x32       # 数据记录标识符，ASCII码0x32对应字符'2'
# 第一个字节为'2'的记录被视为数据记录，会被处理

# ==================== 更新规则配置（核心配置区）====================
# 这是脚本的核心配置部分，定义了"在什么条件下更新什么值"
# 
# 【规则结构说明】
# 每条规则包含三个部分：
#   1. Name（名称）    - 规则的标识名，用于日志记录
#   2. Conditions（条件）- 需要满足的所有条件（AND关系）
#   3. Updates（更新）  - 条件满足时要执行的更新操作
#
# 【字节位置说明】
#   StartByte 是从1开始计数的（1-indexed）
#   例如：StartByte = 50 表示记录的第50个字节位置
#   实际在数组中的索引是 StartByte - 1 = 49
#
# 【字符与字节的关系】
#   因为使用BigEndianUnicode编码，每个字符占2个字节
#   所以字符串"02"占4个字节，"534"占6个字节
#
# 【规则示例解读】
#   Rule-1的含义：
#   如果 第50字节处的值="02" 并且 第78字节处的值="534"
#   则 将第70字节处的值改为"056"

$UpdateRules = @(
    # ========== 规则1 ==========
    @{
        Name       = "Rule-1"           # 规则名称，会显示在日志中
        
        # WHERE条件部分（所有条件必须同时满足）
        # 多个条件之间是AND的关系，必须全部匹配才会触发更新
        Conditions = @(
            @{
                StartByte = 50    # 从第50字节开始检查
                Value     = "02"      # 期望的值是"02"（占4字节：00 30 00 32）
            },
            @{
                StartByte = 78    # 从第78字节开始检查
                Value     = "534"     # 期望的值是"534"（占6字节）
            }
        )
        
        # SET更新部分（条件满足时执行的更新操作）
        Updates    = @(
            @{
                StartByte = 70    # 更新第70字节开始的位置
                Value     = "056"     # 新值为"056"（占6字节）
            }
        )
    },
    
    # ========== 规则2 ==========
    @{
        Name       = "Rule-2"
        
        # 这条规则只有一个条件（WHERE条件）
        Conditions = @(
            @{
                StartByte = 234   # 从第234字节开始检查
                Value     = "99"      # 期望的值是"99"（占4字节）
            }
        )
        
        # 更新操作
        Updates    = @(
            @{
                StartByte = 300   # 更新第300字节开始的位置
                Value     = "77"      # 新值为"77"（占4字节）
            }
        )
    }
    
    # 【如何添加更多规则】
    # 在上面的大括号后面加逗号，然后按照同样的格式添加新规则
    # 例如：
    # ,
    # @{
    #     Name = "Rule-3"
    #     Conditions = @(
    #         @{ StartByte = 100; Value = "ABC" }
    #     )
    #     Updates = @(
    #         @{ StartByte = 200; Value = "XYZ" }
    #     )
    # }
)

# ==================== 辅助函数定义 ====================
# 这些函数封装了常用的操作，使主程序逻辑更清晰

# 【函数1】将文本字符串转换为BigEndianUnicode字节数组
# 输入："AB" 
# 输出：字节数组 [0x00, 0x41, 0x00, 0x42]（每个字符2字节，高位在前）
function ConvertTo-BigEndianUnicodeBytes {
    param([string]$Text)                                    # 输入参数：要转换的文本
    return [System.Text.Encoding]::BigEndianUnicode.GetBytes($Text)  # 使用.NET内置编码器转换
}

# 【函数2】将BigEndianUnicode字节数组转换回文本字符串
# 输入：字节数组 [0x00, 0x41, 0x00, 0x42]
# 输出："AB"
function ConvertFrom-BigEndianUnicodeBytes {
    param([byte[]]$Bytes)                                   # 输入参数：字节数组
    return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes)  # 使用.NET内置编码器转换
}

# 【函数3】将字节数组格式化为十六进制字符串（用于日志显示）
# 输入：字节数组 [0x00, 0x41, 0x00, 0x42]
# 输出："00 41 00 42"
function Format-HexBytes {
    param([byte[]]$Bytes)                                   # 输入参数：字节数组
    # ForEach-Object 遍历每个字节，ToString("X2")转为2位十六进制
    # -join " " 用空格连接所有十六进制字符串
    return ($Bytes | ForEach-Object { $_.ToString("X2") }) -join " "
}

# ==================== 主程序逻辑开始 ====================

# 生成时间戳，用于日志文件命名（格式：2024-01-15_14-30-25）
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# 构建完整的文件路径
$InputFile = Join-Path $InFolder $FileName                 # 输入文件完整路径
$OutputFile = Join-Path $OutFolder $FileName                # 输出文件完整路径
$LogFile = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"  
# 日志文件名：原文件名（去掉.dat）+ 时间戳 + .log

# 创建输出和日志文件夹（如果不存在）
# -Force 参数使得即使文件夹已存在也不会报错
foreach ($folder in @($OutFolder, $LogFolder)) {
    if (-not (Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null 
        # Out-Null 抑制创建目录时的输出信息
    }
}

# 检查输入文件是否存在
if (-not (Test-Path $InputFile)) {
    Write-Host "错误：文件 '$InputFile' 不存在！" -ForegroundColor Red
    exit 1    # 退出脚本，返回错误码1
}

# 初始化日志记录器
# 使用StringBuilder高效地拼接日志字符串，比反复 += 连接字符串性能更好
$logContent = [System.Text.StringBuilder]::new()

# 定义日志函数：同时输出到控制台和记录到日志变量
function Log($msg) {
    [void]$logContent.AppendLine($msg)    # 添加到日志内容（[void]抑制返回值输出）
    Write-Host $msg                        # 同时显示到控制台
}

# ==================== 显示处理信息头部 ====================
Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  DAT Conditional Updater (BigEndianUnicode) - 中文详细解释版 ║"
Log "╠══════════════════════════════════════════════════════════════╣"
Log "║  时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                               ║"
Log "║  输入: $($InputFile.PadRight(50))║"    # PadRight(50)右填充空格到50字符宽度
Log "║  输出: $($OutputFile.PadRight(50))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""

# 获取文件信息并计算记录数
$fileInfo = Get-Item $InputFile              # 获取文件信息对象
$fileLength = $fileInfo.Length               # 文件大小（字节）
$recordCount = [Math]::Floor($fileLength / $RecordSize)  # 计算记录数（向下取整）

Log "文件大小: $fileLength 字节"
Log "记录总数: $recordCount | 规则数量: $($UpdateRules.Count)"
Log ""

# 显示所有规则的概要（便于用户了解将执行的操作）
foreach ($rule in $UpdateRules) {
    # 拼接条件字符串，格式如：[Byte50]='02' AND [Byte78]='534'
    $condStr = ($rule.Conditions | ForEach-Object { "[Byte$($_.StartByte)]='$($_.Value)'" }) -join " AND "
    # 拼接更新字符串，格式如：[Byte70]='056'
    $updStr = ($rule.Updates | ForEach-Object { "[Byte$($_.StartByte)]='$($_.Value)'" }) -join ", "
    Log "  $($rule.Name): IF $condStr THEN SET $updStr"
}
Log ""
Log ("─" * 64)    # 打印64个短横线作为分隔线
Log ""

# 初始化统计变量
$modifiedCount = 0                           # 被修改的记录总数
$ruleHitCount = @{}                          # 哈希表：记录每条规则被触发的次数
foreach ($rule in $UpdateRules) { 
    $ruleHitCount[$rule.Name] = 0            # 初始化每条规则的计数为0
}

# 创建记录缓冲区（用于存储每条记录的字节数据）
$recordBuffer = New-Object byte[] $RecordSize

# ==================== 使用FileStream进行流式处理 ====================
# 使用FileStream而不是一次性读取整个文件，可以处理任意大小的文件
# OpenRead：以只读方式打开输入文件
# Create：创建输出文件（如果存在则覆盖）
$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    # 循环处理每条记录
    for ($i = 0; $i -lt $recordCount; $i++) {
        # 从输入流读取一条记录到缓冲区
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSize)
        
        # 检查是否完整读取了一条记录
        if ($bytesRead -ne $RecordSize) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] 错误 - 读取字节不足: $bytesRead / $RecordSize"
            continue    # 跳过这条不完整的记录
        }
        
        $recordNum = $i + 1                  # 记录编号（从1开始，便于人类阅读）
        $firstByte = $recordBuffer[0]        # 获取记录的第一个字节（用于判断记录类型）
        
        # 根据第一个字节判断记录类型
        if ($firstByte -eq $HeaderMarker) {
            # 头部记录：只记录日志，不做处理
            Log "[#$($recordNum.ToString().PadLeft(4))] HEADER - 跳过"
        }
        elseif ($firstByte -eq $DataMarker) {
            # 数据记录：检查条件并可能更新
            $changes = @()                   # 存储本条记录的所有变更信息
            $hasChange = $false              # 标记本条记录是否有变更
            
            # 遍历所有规则
            foreach ($rule in $UpdateRules) {
                # ========== 条件检查阶段 ==========
                $allConditionsMet = $true    # 假设所有条件都满足
                $conditionDetails = @()       # 存储条件检查的详细信息
                
                # 检查该规则的所有条件（AND关系）
                foreach ($cond in $rule.Conditions) {
                    $offset = $cond.StartByte - 1    # 转换为0-indexed数组下标
                    
                    # 将期望值转换为字节数组（用于比较）
                    $expectedBytes = ConvertTo-BigEndianUnicodeBytes -Text $cond.Value
                    $len = $expectedBytes.Length     # 获取字节长度
                    
                    # 从记录缓冲区读取当前位置的值
                    $currentBytes = New-Object byte[] $len
                    [Array]::Copy($recordBuffer, $offset, $currentBytes, 0, $len)
                    $currentValue = ConvertFrom-BigEndianUnicodeBytes -Bytes $currentBytes
                    
                    # 逐字节比较当前值和期望值
                    $match = $true
                    for ($j = 0; $j -lt $len; $j++) {
                        if ($currentBytes[$j] -ne $expectedBytes[$j]) { 
                            $match = $false
                            break    # 只要有一个字节不匹配就退出循环
                        }
                    }
                    
                    # 如果这个条件不满足，标记整体条件不满足
                    if (-not $match) { 
                        $allConditionsMet = $false 
                    }
                    
                    # 记录条件检查详情（用于调试）
                    $conditionDetails += "[Byte$($cond.StartByte)]='$currentValue'(期望'$($cond.Value)')"
                }
                
                # ========== 更新执行阶段 ==========
                # 只有当所有条件都满足时才执行更新
                if ($allConditionsMet) {
                    foreach ($upd in $rule.Updates) {
                        $offset = $upd.StartByte - 1     # 转换为0-indexed
                        $newBytes = ConvertTo-BigEndianUnicodeBytes -Text $upd.Value
                        $len = $newBytes.Length
                        
                        # 读取旧值（用于日志记录）
                        $oldBytes = New-Object byte[] $len
                        [Array]::Copy($recordBuffer, $offset, $oldBytes, 0, $len)
                        $oldValue = ConvertFrom-BigEndianUnicodeBytes -Bytes $oldBytes
                        
                        # 将新值写入缓冲区
                        # 这会修改recordBuffer中的对应位置
                        [Array]::Copy($newBytes, 0, $recordBuffer, $offset, $len)
                        
                        # 记录变更信息（包含十六进制显示）
                        $changes += "  $($rule.Name): [Byte$($upd.StartByte)] '$oldValue' → '$($upd.Value)' ($(Format-HexBytes $oldBytes) → $(Format-HexBytes $newBytes))"
                    }
                    
                    $hasChange = $true
                    $ruleHitCount[$rule.Name]++      # 增加该规则的命中计数
                }
            }
            
            # 如果本条记录有变更，输出详细日志
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] UPDATED"
                foreach ($c in $changes) { 
                    Log $c    # 输出每个具体的变更
                }
                $modifiedCount++                     # 增加修改记录计数
            }
        }
        # 注意：如果第一个字节既不是HeaderMarker也不是DataMarker，
        # 记录会被直接写入输出文件而不做任何处理
        
        # 将（可能已修改的）记录写入输出流
        $outputStream.Write($recordBuffer, 0, $RecordSize)
    }
}
finally {
    # finally块确保无论是否发生异常，文件流都会被正确关闭
    # 这是防止文件句柄泄漏的重要实践
    $inputStream.Close()
    $outputStream.Close()
}

# ==================== 输出处理结果摘要 ====================
Log ""
Log ("─" * 64)
Log "处理摘要:"
Log "  更新记录数: $modifiedCount / $recordCount"

# 显示每条规则的命中次数
foreach ($rule in $UpdateRules) {
    Log "  $($rule.Name) 命中次数: $($ruleHitCount[$rule.Name])"
}
Log ("─" * 64)

# 将日志内容写入日志文件
[System.IO.File]::WriteAllText($LogFile, $logContent.ToString())

# 显示最终处理结果（绿色文字）
Write-Host ""
Write-Host "✓ 输出文件: $OutputFile" -ForegroundColor Green
Write-Host "✓ 日志文件: $LogFile" -ForegroundColor Green

# ==================== 脚本结束 ====================
# 
# 【使用说明】
# 1. 将待处理的DAT文件放入 in/ 文件夹
# 2. 根据需要修改上方的 $UpdateRules 配置
# 3. 运行脚本：.\update_dat_中文详细解释版.ps1 -FileName "yourfile.dat"
# 4. 处理后的文件在 out/ 文件夹，日志在 log/ 文件夹
#
# 【注意事项】
# - 确保DAT文件确实使用BigEndianUnicode (UTF-16BE) 编码
# - StartByte位置必须准确，否则会读写错误的数据
# - 建议先用测试数据验证规则配置是否正确
# ============================================
