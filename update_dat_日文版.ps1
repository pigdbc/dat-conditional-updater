# ============================================
# DATファイル条件更新スクリプト (日本語版 - BigEndianUnicode)
# 機能：SQL UPDATEのように、条件に一致するフィールドを更新
# 対応：複数条件AND | UTF-16BEエンコード | ストリーム処理
# ============================================

param(
    [string]$FileName = "data.dat"
)

# ==================== フォルダ設定 ====================
$InFolder  = "in"
$OutFolder = "out"
$LogFolder = "log"

# ==================== レコード設定 ====================
$RecordSize   = 1300          # 各レコードのバイト数
$HeaderMarker = 0x31          # ヘッダーレコード識別子 (ASCII '1')
$DataMarker   = 0x32          # データレコード識別子 (ASCII '2')

# ==================== 更新ルール設定 ====================
# SQL形式: UPDATE table SET field=value WHERE condition1 AND condition2
# 
# StartByte: 開始位置 (1-indexed)
# Value: 文字列値（BigEndianUnicodeバイトに自動変換）
# 注意: 各文字は2バイト (UTF-16BE)
#
# ルール例：
# 50バイト目から"02"(4バイト)の場合、70バイト目を"056"に更新

$UpdateRules = @(
    @{
        Name = "Rule-1"
        # WHERE条件 (すべての条件を満たす必要 - AND関係)
        Conditions = @(
            @{ StartByte = 50;  Value = "02" },    # 50バイト目 = "02" (4バイト)
            @{ StartByte = 78;  Value = "534" }    # 78バイト目 = "534" (6バイト)
        )
        # SET更新操作
        Updates = @(
            @{ StartByte = 70;  Value = "056" }    # 70バイト目を"056"に更新 (6バイト)
        )
    },
    @{
        Name = "Rule-2"
        Conditions = @(
            @{ StartByte = 234; Value = "99" }     # 234バイト目 = "99" (4バイト)
        )
        Updates = @(
            @{ StartByte = 300; Value = "77" }     # 300バイト目を"77"に更新 (4バイト)
        )
    }
    # ルールを追加...
)

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
$InputFile  = Join-Path $InFolder $FileName
$OutputFile = Join-Path $OutFolder $FileName
$LogFile    = Join-Path $LogFolder "$($FileName -replace '\.dat$','')_$timestamp.log"

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
$recordCount = [Math]::Floor($fileLength / $RecordSize)

Log "ファイルサイズ: $fileLength バイト"
Log "レコード数: $recordCount | ルール数: $($UpdateRules.Count)"
Log ""

# ルール概要を表示
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

# FileStreamでストリーム処理
$inputStream = [System.IO.File]::OpenRead($InputFile)
$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $recordCount; $i++) {
        $bytesRead = $inputStream.Read($recordBuffer, 0, $RecordSize)
        
        if ($bytesRead -ne $RecordSize) {
            Log "[#$($($i + 1).ToString().PadLeft(4))] エラー - 読取バイト不足: $bytesRead / $RecordSize"
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
                    $offset = $cond.StartByte - 1
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
                    
                    $conditionDetails += "[Byte$($cond.StartByte)]='$currentValue'(期待'$($cond.Value)')"
                }
                
                if ($allConditionsMet) {
                    # 更新実行
                    foreach ($upd in $rule.Updates) {
                        $offset = $upd.StartByte - 1
                        $newBytes = ConvertTo-BigEndianUnicodeBytes -Text $upd.Value
                        $len = $newBytes.Length
                        
                        # 旧値を読取
                        $oldBytes = New-Object byte[] $len
                        [Array]::Copy($recordBuffer, $offset, $oldBytes, 0, $len)
                        $oldValue = ConvertFrom-BigEndianUnicodeBytes -Bytes $oldBytes
                        
                        # 新値を書込
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
