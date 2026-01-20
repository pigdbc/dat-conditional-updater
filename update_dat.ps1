# ============================================
# DATファイル条件更新スクリプト (日本語版 - BigEndianUnicode)
# 機能：SQL UPDATEのように、条件に一致するフィールドを更新
# 対応：複数条件AND | UTF-16BEエンコード | ストリーム処理
# ============================================

param(
    [string]$FileName = "data.dat"
)

# ==================== フォルダ設定 ====================
$BaseDir = $PSScriptRoot
$InFolder = Join-Path $BaseDir "in"
$OutFolder = Join-Path $BaseDir "out"
$LogFolder = Join-Path $BaseDir "log"

# ==================== 設定ファイル読込 ====================
$ConfigFile = Join-Path $BaseDir "config.ini"
if ($args.Count -gt 0) { $ConfigFile = Join-Path $BaseDir $args[0] }

if (-not (Test-Path $ConfigFile)) {
    Write-Host "エラー: 設定ファイル '$ConfigFile' が見つかりません！" -ForegroundColor Red
    exit 1
}

# INI解析関数
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
        }
        elseif ($line -match "^(.*?)=(.*)$") {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if (-not $ini.ContainsKey($section)) { $ini[$section] = @{} }
            $ini[$section][$key] = $value
        }
    }
    return $ini
}

$ConfigData = Parse-IniFile -FilePath $ConfigFile

# ==================== レコード設定 (INIから読込, 文字数) ====================
if ($ConfigData.ContainsKey("Settings")) {
    $RecordSizeChars = if ($ConfigData["Settings"]["RecordSize"]) { [int]$ConfigData["Settings"]["RecordSize"] } else { 1300 }
    $HeaderMarker = if ($ConfigData["Settings"]["HeaderMarker"]) { [int]$ConfigData["Settings"]["HeaderMarker"] + 0x30 } else { 0x31 }
    $DataMarker = if ($ConfigData["Settings"]["DataMarker"]) { [int]$ConfigData["Settings"]["DataMarker"] + 0x30 } else { 0x32 }
}
else {
    # デフォルト
    $RecordSizeChars = 1300
    $HeaderMarker = 0x31
    $DataMarker = 0x32
}

# ==================== 更新ルール設定 (INIから読込) ====================
$UpdateRules = @()
$ruleKeys = $ConfigData.Keys | Where-Object { $_ -like "Rule-*" } | Sort-Object {
    $num = $_ -replace '^Rule-', ''
    if ($num -match '^\d+$') { [int]$num } else { [int]::MaxValue }
}, {
    $_
}

foreach ($key in $ruleKeys) {
    $section = $ConfigData[$key]
        
        # 条件解析: "Name:50:02, Field78:78:534"
        $conditions = @()
        if ($section["Conditions"]) {
            $section["Conditions"].Split(",") | ForEach-Object {
                $parts = $_.Split(":")
                if ($parts.Count -ge 3) {
                    $conditions += @{
                        Name      = $parts[0].Trim()
                        StartByte = [int]$parts[1].Trim()
                        Value     = $parts[2].Trim()
                        CharLength = $parts[2].Trim().Length
                    }
                }
                elseif ($parts.Count -ge 2) {
                    $conditions += @{
                        Name      = ""
                        StartByte = [int]$parts[0].Trim()
                        Value     = $parts[1].Trim()
                        CharLength = $parts[1].Trim().Length
                    }
                }
            }
        }
        
        # 更新解析: "Field70:70:056"
        $updates = @()
        if ($section["Updates"]) {
            $section["Updates"].Split(",") | ForEach-Object {
                $parts = $_.Split(":")
                if ($parts.Count -ge 3) {
                    $updates += @{
                        Name      = $parts[0].Trim()
                        StartByte = [int]$parts[1].Trim()
                        Value     = $parts[2].Trim()
                        CharLength = $parts[2].Trim().Length
                    }
                }
                elseif ($parts.Count -ge 2) {
                    $updates += @{
                        Name      = ""
                        StartByte = [int]$parts[0].Trim()
                        Value     = $parts[1].Trim()
                        CharLength = $parts[1].Trim().Length
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

# ==================== ヘルパー関数 ====================

# 文字列をBigEndianUnicodeバイト配列に変換
function ConvertTo-BigEndianUnicodeBytes {
    param([string]$Text)
    return [System.Text.Encoding]::BigEndianUnicode.GetBytes($Text)
}

# BigEndianUnicodeバイト配列を文字列に変換
function ConvertFrom-BigEndianUnicodeBytes {
    param([byte[]]$Bytes)
    return [System.Text.Encoding]::BigEndianUnicode.GetString($Bytes)
}

# バイト配列を16進数文字列にフォーマット
function Format-HexBytes {
    param([byte[]]$Bytes)
    return ($Bytes | ForEach-Object { $_.ToString("X2") }) -join " "
}

# ==================== スクリプトロジック ====================

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$InputFile = Join-Path $InFolder $FileName
$OutputFile = Join-Path $OutFolder $FileName
$LogFile = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"

foreach ($folder in @($OutFolder, $LogFolder)) {
    if (-not (Test-Path $folder)) { 
        New-Item -ItemType Directory -Path $folder -Force | Out-Null 
    }
}

if (-not (Test-Path $InputFile)) {
    Write-Host "エラー: ファイル '$InputFile' が存在しません！" -ForegroundColor Red
    exit 1
}

# ログ関数
$logContent = [System.Text.StringBuilder]::new()
function Log($msg) {
    [void]$logContent.AppendLine($msg)
    Write-Host $msg
}

# 処理開始
Log "╔══════════════════════════════════════════════════════════════╗"
Log "║  DAT Conditional Updater (BigEndianUnicode) - 日本語版       ║"
Log "╠══════════════════════════════════════════════════════════════╣"
Log "║  時刻: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                               ║"
Log "║  入力: $($InputFile.PadRight(50))║"
Log "║  出力: $($OutputFile.PadRight(50))║"
Log "╚══════════════════════════════════════════════════════════════╝"
Log ""

$fileInfo = Get-Item $InputFile
$fileLength = $fileInfo.Length
$recordCount = [Math]::Floor($fileLength / ($RecordSizeChars * 2))

Log "ファイルサイズ: $fileLength バイト"
Log "レコード数: $recordCount | ルール数: $($UpdateRules.Count)"
Log ""

# ルール概要を表示
foreach ($rule in $UpdateRules) {
    $condStr = ($rule.Conditions | ForEach-Object {
        $label = if ($_.Name) { $_.Name } else { "Char$($_.StartByte)" }
        "$label = '$($_.Value)'"
    }) -join " AND "
    $updStr = ($rule.Updates | ForEach-Object { 
        if ($_.Name) { "$($_.Name) = '$($_.Value)'" } else { "[Char$($_.StartByte)] = '$($_.Value)'" }
    }) -join ", "
    Log "  $($rule.Name): IF $condStr THEN SET $updStr"
}
Log ""
Log ("─" * 64)
Log ""

$modifiedCount = 0
$ruleHitCount = @{}
foreach ($rule in $UpdateRules) { $ruleHitCount[$rule.Name] = 0 }

$RecordSizeBytes = $RecordSizeChars * 2
$recordBuffer = New-Object byte[] $RecordSizeBytes

# FileStreamでストリーム処理
$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $recordCount; $i++) {
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSizeBytes)
        
        if ($bytesRead -ne $RecordSizeBytes) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] エラー - 読取バイト不足: $bytesRead / $RecordSizeBytes"
            continue
        }
        
        $recordNum = $i + 1
        $firstByte = $recordBuffer[0]
        
        if ($firstByte -eq $HeaderMarker) {
            Log "[#$($recordNum.ToString().PadLeft(4))] HEADER - スキップ"
        }
        elseif ($firstByte -eq $DataMarker) {
            $changes = @()
            $hasChange = $false
            
            foreach ($rule in $UpdateRules) {
                # すべての条件を確認 (AND関係)
                $allConditionsMet = $true
                $conditionDetails = @()
                
                foreach ($cond in $rule.Conditions) {
                    $offset = ($cond.StartByte - 1) * 2
                    $expectedBytes = ConvertTo-BigEndianUnicodeBytes -Text $cond.Value
                    $len = $expectedBytes.Length
                    
                    # 現在の値を読取
                    $currentBytes = New-Object byte[] $len
                    [Array]::Copy($recordBuffer, $offset, $currentBytes, 0, $len)
                    $currentValue = ConvertFrom-BigEndianUnicodeBytes -Bytes $currentBytes
                    
                    # バイト比較
                    $match = $true
                    for ($j = 0; $j -lt $len; $j++) {
                        if ($currentBytes[$j] -ne $expectedBytes[$j]) { $match = $false; break }
                    }
                    if (-not $match) { $allConditionsMet = $false }
                    
                    $conditionDetails += "[Char$($cond.StartByte)]='$currentValue'(期待'$($cond.Value)')"
                }
                
                if ($allConditionsMet) {
                    # 更新実行
                    foreach ($upd in $rule.Updates) {
                        $offset = ($upd.StartByte - 1) * 2
                        $newBytes = ConvertTo-BigEndianUnicodeBytes -Text $upd.Value
                        $len = $newBytes.Length
                        
                        # 旧値を読取
                        $oldBytes = New-Object byte[] $len
                        [Array]::Copy($recordBuffer, $offset, $oldBytes, 0, $len)
                        $oldValue = ConvertFrom-BigEndianUnicodeBytes -Bytes $oldBytes
                        
                        # 新値を書込
                        [Array]::Copy($newBytes, 0, $recordBuffer, $offset, $len)
                        
                        $label = if ($upd.Name) { $upd.Name } else { "Char$($upd.StartByte)" }
                        $changes += "  $($rule.Name): $label '$oldValue' → '$($upd.Value)' ($(Format-HexBytes $oldBytes) → $(Format-HexBytes $newBytes))"
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
            else {
                Log "[#$($recordNum.ToString().PadLeft(4))] 变更なし"
            }
        }
        
        $outputStream.Write($recordBuffer, 0, $RecordSizeBytes)
    }
}
finally {
    $inputStream.Close()
    $outputStream.Close()
}

Log ""
Log ("─" * 64)
Log "処理概要:"
Log "  更新レコード数: $modifiedCount / $recordCount"
foreach ($rule in $UpdateRules) {
    Log "  $($rule.Name) ヒット数: $($ruleHitCount[$rule.Name])"
}
Log ("─" * 64)

[System.IO.File]::WriteAllText($LogFile, $logContent.ToString())

Write-Host ""
Write-Host "✓ 出力ファイル: $OutputFile" -ForegroundColor Green
Write-Host "✓ ログファイル: $LogFile" -ForegroundColor Green
