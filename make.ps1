# ============================================
# 1. CONFIGURATION
# ============================================
# Cách dùng: Thêm ID của các sàn khác vào mảng bên dưới, cách nhau bằng dấu phẩy.
$MT4TerminalIDs = @(
    "3773AE10556A00F3D812544D7EDDAB90", # Exness (Primary)
    "2191F4A3D14D7B4B1EBB84F924777883", # Sàn thứ 2
    "6F841180CC7A5B4E481813CAFF4002B0", # Sàn thứ 3
    "199CEC8D3EDFD7196CB34026FC926413"
)

$IndicatorName = "RSI_Advanced"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path  # Thư mục gốc project
$BuildDir = Join-Path $ProjectRoot "Build"
$SourceFile = Join-Path $ProjectRoot "$IndicatorName.mq4"
$DefinesFile = Join-Path $ProjectRoot "Include\RSI_Advanced\Config.mqh"
$LogFile = Join-Path $BuildDir "compile.log"
$TempLogFile = Join-Path $BuildDir "temp_compile.log"

$MetaEditor = "C:\Program Files (x86)\MetaTrader 4 EXNESS\metaeditor.exe"
$AppDataPath = "$env:USERPROFILE\AppData\Roaming\MetaQuotes\Terminal"

# ============================================
# 2. VALIDATION
# ============================================
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "VALIDATING ENVIRONMENT"
Write-Host "Project Root: $ProjectRoot"
Write-Host "Build Dir   : $BuildDir"
Write-Host "=========================================="

if (!(Test-Path $MetaEditor)) { Write-Error "MetaEditor not found at $MetaEditor"; exit 1 }
if (!(Test-Path $SourceFile)) { Write-Error "Indicator Source file not found."; exit 2 }
if (!(Test-Path $DefinesFile)) { Write-Error "Config file (containing version) not found."; exit 3 }
if (!(Test-Path $BuildDir)) { New-Item -ItemType Directory -Path $BuildDir | Out-Null }

# ============================================
# 3. VERSION MANAGEMENT
# ============================================
Write-Host "Reading version from Config.mqh..."
$DefinesContent = Get-Content $DefinesFile
$VersionLine = $DefinesContent | Where-Object { $_ -match '#define\s+VERSION' }
if (!$VersionLine) { Write-Error "Cannot find VERSION in Config.mqh"; exit 5 }

$Version = ($VersionLine -replace '.*"(.+?)".*', '$1')
Write-Host "Current version: $Version" -ForegroundColor Green

# Sync version into .mq4 property
$SourceContent = Get-Content $SourceFile
$UpdatedContent = $SourceContent -replace '#property\s+version\s+".*?"', "#property version `"$Version`""
Set-Content -Path $SourceFile -Value $UpdatedContent -Encoding UTF8

# ============================================
# 4. COMPILATION
# ============================================
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BuildName = "${IndicatorName}_v${Version}_$Timestamp.ex4"
$BuildOutput = Join-Path $BuildDir $BuildName

Write-Host "Compiling $IndicatorName..." -ForegroundColor Yellow
& "$MetaEditor" /compile:"$SourceFile" /log:"$TempLogFile" | Out-Null
Start-Sleep -Seconds 5

if (!(Test-Path $TempLogFile)) { Write-Error "Compiler did not produce a log."; exit 7 }
$LogContent = Get-Content $TempLogFile -Raw

# Parse Results
if ($LogContent -match "Result:\s+([0-9]+)\s+errors,\s+([0-9]+)\s+warnings") {
    $ErrorCount = [int]$Matches[1]
    $WarningCount = [int]$Matches[2]

    if ($ErrorCount -gt 0) {
        Write-Host "BUILD FAILED - $ErrorCount ERRORS" -ForegroundColor Red
        Add-Content -Path $LogFile -Value "[$(Get-Date)] FAILED: $BuildName`n$LogContent"
        
        # Show the log file path clearly for debugging
        Write-Host "Please check the detailed log at:" -ForegroundColor Gray
        Write-Host ">> $LogFile" -ForegroundColor Cyan
        Write-Host "------------------------------------------" -ForegroundColor Red

        exit 7
    }
}

# Log successful session
$SessionHeader = "`n==========================================`n[Build: $BuildName] @ $(Get-Date)`n==========================================`n"
Add-Content -Path $LogFile -Value "$SessionHeader$LogContent"
if (Test-Path $TempLogFile) { Remove-Item $TempLogFile -Force }

# ============================================
# 5. ARTIFACT MANAGEMENT
# ============================================
$GeneratedEX4 = Join-Path $ProjectRoot "$IndicatorName.ex4"
if (!(Test-Path $GeneratedEX4)) { Write-Error "EX4 not found after compilation."; exit 8 }

# Move to Build folder with versioned name
Move-Item -Path $GeneratedEX4 -Destination $BuildOutput -Force

# ============================================
# 6. MULTI-TERMINAL DEPLOYMENT
# ============================================
Write-Host ""
Write-Host "DEPLOYING TO TERMINALS..." -ForegroundColor Cyan

foreach ($ID in $MT4TerminalIDs) {
    # Indicator được copy vào thư mục MQL4\Indicators của từng Terminal
    $TargetDir = Join-Path (Join-Path $AppDataPath $ID) "MQL4\Indicators"
    $DeployPath = Join-Path $TargetDir "$IndicatorName.ex4"

    if (Test-Path $TargetDir) {
        Copy-Item -Path $BuildOutput -Destination $DeployPath -Force
        Write-Host "  [OK] Deployed -> $ID" -ForegroundColor Green
    }
    else {
        Write-Host "  [SKIP] Terminal folder not found: $ID" -ForegroundColor Yellow
    }
}


Write-Host ""
Write-Host "=========================================="
Write-Host "BUILD & DEPLOY SUCCESS" -ForegroundColor Green
Write-Host "Artifact: $BuildOutput"
Write-Host "=========================================="
