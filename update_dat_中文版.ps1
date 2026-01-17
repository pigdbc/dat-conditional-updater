# ============================================
# DAT文件条件更新脚本 (中文版 - BigEndianUnicode)
# 功能：类似SQL UPDATE，根据条件匹配并修改字段值
# 支持：多条件AND | UTF-16BE编码 | 流式读写
# ============================================

param(
    [string]$FileName = "data.dat"
)

# ==================== 文件夹配置 ====================
$InFolder  = "in"
$OutFolder = "out"
$LogFolder = "log"

# ==================== 配置文件加载 ====================
$ConfigFile = "config.ini"
if ($args.Count -gt 1) { $ConfigFile = $args[1] }

if (-not (Test-Path $ConfigFile)) {
    Write-Host "错误: 配置文件 '$ConfigFile' 不存在！" -ForegroundColor Red
    exit 1
}

# 简单的INI解析函数
function Parse-IniFile {
    param([string]$FilePath)
    $ini = @{}
    $section = "Global"
    
    Get-Content $FilePath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith(";") -or $line.StartsWith("#")) { return }
        
        if ($line -match "^\[(.*)\]$") {
            $section = $matches[1]
            $ini[$section] = @{}
        } elseif ($line -match "^(.*?)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if (-not $ini.ContainsKey($section)) { $ini[$section] = @{} }
            $ini[$section][$key] = $value
        }
    }
    return $ini
}

$ConfigData = Parse-IniFile -FilePath $ConfigFile

# ==================== 记录配置 (从INI加载) ====================
if ($ConfigData.ContainsKey("Settings")) {
    $RecordSize   = if ($ConfigData["Settings"]["RecordSize"]) { [int]$ConfigData["Settings"]["RecordSize"] } else { 1300 }
    $HeaderMarker = if ($ConfigData["Settings"]["HeaderMarker"]) { [int]$ConfigData["Settings"]["HeaderMarker"] + 0x30 } else { 0x31 }
    $DataMarker   = if ($ConfigData["Settings"]["DataMarker"]) { [int]$ConfigData["Settings"]["DataMarker"] + 0x30 } else { 0x32 }
} else {
    # 默认值
    $RecordSize   = 1300
    $HeaderMarker = 0x31
    $DataMarker   = 0x32
}

# ==================== 更新规则配置 (从INI加载) ====================
$UpdateRules = @()

foreach ($key in $ConfigData.Keys) {
    if ($key -like "Rule-*") {
        $section = $ConfigData[$key]
        
        # 解析条件: "50:02, 78:534"
        $conditions = @()
        if ($section["Conditions"]) {
            $section["Conditions"].Split(",") | ForEach-Object {
                $parts = $_.Split(":")
                if ($parts.Count -eq 2) {
                    $conditions += @{
                        StartByte = [int]$parts[0].Trim()
                        Value     = $parts[1].Trim()
                    }
                }
            }
        }
        
        # 解析更新: "70:056"
        $updates = @()
        if ($section["Updates"]) {
            $section["Updates"].Split(",") | ForEach-Object {
                $parts = $_.Split(":")
                if ($parts.Count -eq 2) {
                    $updates += @{
                        StartByte = [int]$parts[0].Trim()
                        Value     = $parts[1].Trim()
                    }
                }
            }
        }
        
        if ($conditions.Count -gt 0 -and $updates.Count -gt 0) {
            $UpdateRules += @{
                Name       = $key
                Conditions = $conditions
                Updates    = $updates
            }
        }
    }
}

# ==================== 辅助函数 ====================

# 将字符串转换为BigEndianUnicode字节数组
function ConvertTo-BigEndianUnicodeBytes {
    param([string]$Text)
    return [System.Text.Encoding]::BigEndianUnicode.GetBytes($Text)
}

# 将BigEndianUnicode字节数组转换为字符串
function ConvertFrom-BigEndianUnicodeBytes {
    param([byte[]]$Bytes)
    return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes)
}

# 将字节数组格式化为十六进制字符串
function Format-HexBytes {
    param([byte[]]$Bytes)
    return ($Bytes | ForEach-Object { $_.ToString("X2") }) -join " "
}

# ==================== 脚本逻辑 ====================

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$InputFile  = Join-Path $InFolder $FileName
$OutputFile = Join-Path $OutFolder $FileName
$LogFile    = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"

foreach ($folder in @($OutFolder, $LogFolder)) {
    if (-not (Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null 
    }
}

if (-not (Test-Path $InputFile)) {
    Write-Host "错误: 文件 '$InputFile' 不存在！" -ForegroundColor Red
    exit 1
}

# 日志函数
$logContent = [System.Text.StringBuilder]::new()
function Log($msg) {
    [void]$logContent.AppendLine($msg)
    Write-Host $msg
}

# 开始处理
Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  DAT Conditional Updater (BigEndianUnicode)                   ║"
Log "╠══════════════════════════════════════════════════════════════╣"
Log "║  时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                               ║"
Log "║  输入: $($InputFile.PadRight(50))║"
Log "║  输出: $($OutputFile.PadRight(50))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""

$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length
$recordCount = [Math]::Floor($fileLength / $RecordSize)

Log "文件大小: $fileLength 字节"
Log "记录总数: $recordCount | 规则数量: $($UpdateRules.Count)"
Log ""

# 显示规则摘要
foreach ($rule in $UpdateRules) {
    $condStr = ($rule.Conditions | ForEach-Object { "[Byte$($_.StartByte)]='$($_.Value)'" }) -join " AND "
    $updStr = ($rule.Updates | ForEach-Object { "[Byte$($_.StartByte)]='$($_.Value)'" }) -join ", "
    Log "  $($rule.Name): IF $condStr THEN SET $updStr"
}
Log ""
Log ("─" * 64)
Log ""

$modifiedCount = 0
$ruleHitCount = @{}
foreach ($rule in $UpdateRules) { $ruleHitCount[$rule.Name] = 0 }

$recordBuffer = New-Object byte[] $RecordSize

# 使用FileStream流式读写
$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $recordCount; $i++) {
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSize)
        
        if ($bytesRead -ne $RecordSize) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] 错误 - 读取字节不足: $bytesRead / $RecordSize"
            continue
        }
        
        $recordNum = $i + 1
        $firstByte = $recordBuffer[0]
        
        if ($firstByte -eq $HeaderMarker) {
            Log "[#$($recordNum.ToString().PadLeft(4))] HEADER - 已跳过"
        }
        elseif ($firstByte -eq $DataMarker) {
            $changes = @()
            $hasChange = $false
            
            foreach ($rule in $UpdateRules) {
                # 检查所有条件是否满足 (AND关系)
                $allConditionsMet = $true
                $conditionDetails = @()
                
                foreach ($cond in $rule.Conditions) {
                    $offset = $cond.StartByte - 1
                    $expectedBytes = ConvertTo-BigEndianUnicodeBytes -Text $cond.Value
                    $len = $expectedBytes.Length
                    
                    # 读取当前值
                    $currentBytes = New-Object byte[] $len
                    [Array]::Copy($recordBuffer, $offset, $currentBytes, 0, $len)
                    $currentValue = ConvertFrom-BigEndianUnicodeBytes -Bytes $currentBytes
                    
                    # 比较字节
                    $match = $true
                    for ($j = 0; $j -lt $len; $j++) {
                        if ($currentBytes[$j] -ne $expectedBytes[$j]) { $match = $false; break }
                    }
                    if (-not $match) { $allConditionsMet = $false }
                    
                    $conditionDetails += "[Byte$($cond.StartByte)]='$currentValue'(期望'$($cond.Value)')"
                }
                
                if ($allConditionsMet) {
                    # 执行更新
                    foreach ($upd in $rule.Updates) {
                        $offset = $upd.StartByte - 1
                        $newBytes = ConvertTo-BigEndianUnicodeBytes -Text $upd.Value
                        $len = $newBytes.Length
                        
                        # 读取旧值
                        $oldBytes = New-Object byte[] $len
                        [Array]::Copy($recordBuffer, $offset, $oldBytes, 0, $len)
                        $oldValue = ConvertFrom-BigEndianUnicodeBytes -Bytes $oldBytes
                        
                        # 写入新值
                        [Array]::Copy($newBytes, 0, $recordBuffer, $offset, $len)
                        
                        $changes += "  $($rule.Name): [Byte$($upd.StartByte)] '$oldValue' → '$($upd.Value)' ($(Format-HexBytes $oldBytes) → $(Format-HexBytes $newBytes))"
                    }
                    
                    $hasChange = $true
                    $ruleHitCount[$rule.Name]++
                }
            }
            
            if ($hasChange) {
                Log "[#$($recordNum.ToString().PadLeft(4))] UPDATED"
                foreach ($c in $changes) { Log $c }
                $modifiedCount++
            }
            # 不输出未修改的记录，避免日志过大
        }
        
        $outputStream.Write($recordBuffer, 0, $RecordSize)
    }
}
finally {
    $inputStream.Close()
    $outputStream.Close()
}

Log ""
Log ("─" * 64)
Log "处理摘要:"
Log "  修改记录数: $modifiedCount / $recordCount"
foreach ($rule in $UpdateRules) {
    Log "  $($rule.Name) 命中次数: $($ruleHitCount[$rule.Name])"
}
Log ("─" * 64)

[System.IO.File]::WriteAllText($LogFile, $logContent.ToString())

Write-Host ""
Write-Host "✓ 输出文件: $OutputFile" -ForegroundColor Green
Write-Host "✓ 日志文件: $LogFile" -ForegroundColor Green
