# 创建测试用DAT文件 (二进制大端存储)
# 用于验证 update_dat_中文版.ps1 功能

$RecordSize = 1300
$RecordCount = 10
$OutputFile = "in/test_data.dat"

# 确保目录存在
if (-not (Test-Path "in")) { New-Item -ItemType Directory -Path "in" -Force | Out-Null }

$outputStream = [System.IO.File]::Create($OutputFile)

try {
    for ($i = 0; $i -lt $RecordCount; $i++) {
        $buffer = New-Object byte[] $RecordSize
        
        if ($i -eq 0) {
            # Header记录
            $buffer[0] = 0x31  # '1'
        } else {
            # 数据记录
            $buffer[0] = 0x32  # '2'
            
            # 设置一些测试数据 (大端存储)
            if ($i -eq 2 -or $i -eq 5) {
                # 第50~51位 = 02 (大端: 00 02)
                $buffer[49] = 0x00
                $buffer[50] = 0x02
                
                # 第78~80位 = 534 (大端: 00 02 16)
                $buffer[77] = 0x00
                $buffer[78] = 0x02
                $buffer[79] = 0x16
            }
            
            if ($i -eq 3 -or $i -eq 7) {
                # 第234~235位 = 99 (大端: 00 63)
                $buffer[233] = 0x00
                $buffer[234] = 0x63
            }
        }
        
        $outputStream.Write($buffer, 0, $RecordSize)
    }
}
finally {
    $outputStream.Close()
}

Write-Host "✓ 已创建测试文件: $OutputFile" -ForegroundColor Green
Write-Host "  - 记录数: $RecordCount"
Write-Host "  - 记录#3, #6: 满足 Rule-1 条件 (50~51=02 AND 78~80=534)"
Write-Host "  - 记录#4, #8: 满足 Rule-2 条件 (234~235=99)"
