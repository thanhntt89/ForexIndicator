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

$MT5TerminalIDs = @(
    "D3966AA92A61BDC959A1092A330FDFD3"  # TF Global Markets MT5
)

$IndicatorName = "QuantEdge_RSI"
$EAName = "QuantEdge_EA_Template"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path  # Thư mục gốc project
$BuildDir = Join-Path $ProjectRoot "Build"
$SourceFile = Join-Path $ProjectRoot "$IndicatorName.mq4"
$SourceFile5 = Join-Path $ProjectRoot "$IndicatorName.mq5"
$EASourceFile = Join-Path $ProjectRoot "Experts\$EAName.mq4"
$EASourceFile5 = Join-Path $ProjectRoot "Experts\$EAName.mq5"
$DefinesFile = Join-Path $ProjectRoot "Include\QuantEdge\Core\Config.mqh"
$LogFile = Join-Path $BuildDir "compile.log"
$TempLogFile = Join-Path $BuildDir "temp_compile.log"
$TempLogFile5 = Join-Path $BuildDir "temp_compile5.log"
$EATempLogFile = Join-Path $BuildDir "temp_ea_compile.log"
$EATempLogFile5 = Join-Path $BuildDir "temp_ea_compile5.log"

$MetaEditor = "C:\Program Files (x86)\MetaTrader 4 EXNESS\metaeditor.exe"
$MetaEditor5 = "C:\Program Files\TF Global Markets MetaTrader 5 Terminal\MetaEditor64.exe"
$AppDataPath = "$env:USERPROFILE\AppData\Roaming\MetaQuotes\Terminal"

# ============================================
# 2. SYNC INCLUDES TO ALL TERMINALS
# ============================================
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SYNCING INCLUDES TO TERMINALS"
Write-Host "=========================================="

$SourceInclude = Join-Path $ProjectRoot "Include\QuantEdge"

# Sync to all MT4 terminals
foreach ($ID in $MT4TerminalIDs) {
    $TargetIncDir = Join-Path (Join-Path $AppDataPath $ID) "MQL4\Include"
    if (Test-Path $TargetIncDir) {
        $TargetQE = Join-Path $TargetIncDir "QuantEdge"
        # Remove old flat files or stale folder
        if (Test-Path $TargetQE) {
            $item = Get-Item $TargetQE -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                cmd /c rmdir "$TargetQE" 2>$null
            } else {
                Remove-Item $TargetQE -Recurse -Force -Confirm:$false
            }
        }
        # Create junction (symlink) — changes in repo auto-visible
        cmd /c mklink /J "$TargetQE" "$SourceInclude" 2>$null | Out-Null
        if (Test-Path $TargetQE) {
            Write-Host "  [MT4] Include synced -> $ID" -ForegroundColor Green
        } else {
            # Fallback: copy
            Copy-Item $SourceInclude $TargetQE -Recurse -Force
            Write-Host "  [MT4] Include copied -> $ID" -ForegroundColor Yellow
        }
    }
}

# Sync to all MT5 terminals
foreach ($ID in $MT5TerminalIDs) {
    $TargetIncDir = Join-Path (Join-Path $AppDataPath $ID) "MQL5\Include"
    if (Test-Path $TargetIncDir) {
        $TargetQE = Join-Path $TargetIncDir "QuantEdge"
        if (Test-Path $TargetQE) {
            $item = Get-Item $TargetQE -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                cmd /c rmdir "$TargetQE" 2>$null
            } else {
                Remove-Item $TargetQE -Recurse -Force -Confirm:$false
            }
        }
        cmd /c mklink /J "$TargetQE" "$SourceInclude" 2>$null | Out-Null
        if (Test-Path $TargetQE) {
            Write-Host "  [MT5] Include synced -> $ID" -ForegroundColor Green
        } else {
            Copy-Item $SourceInclude $TargetQE -Recurse -Force
            Write-Host "  [MT5] Include copied -> $ID" -ForegroundColor Yellow
        }
    }
}

# ============================================
# 3. VALIDATION
# ============================================
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "VALIDATING ENVIRONMENT"
Write-Host "Project Root: $ProjectRoot"
Write-Host "Build Dir   : $BuildDir"
Write-Host "=========================================="

if (!(Test-Path $MetaEditor)) { Write-Error "MetaEditor (MT4) not found at $MetaEditor"; exit 1 }
if (!(Test-Path $MetaEditor5)) { Write-Error "MetaEditor (MT5) not found at $MetaEditor5"; exit 1 }
if (!(Test-Path $SourceFile)) { Write-Error "Indicator Source file (MT4) not found."; exit 2 }
if (!(Test-Path $SourceFile5)) { Write-Error "Indicator Source file (MT5) not found."; exit 2 }
if (!(Test-Path $EASourceFile)) { Write-Error "EA Source file (MT4) not found."; exit 2 }
if (!(Test-Path $EASourceFile5)) { Write-Error "EA Source file (MT5) not found."; exit 2 }
if (!(Test-Path $DefinesFile)) { Write-Error "Config file (containing version) not found."; exit 3 }
if (!(Test-Path $BuildDir)) { New-Item -ItemType Directory -Path $BuildDir | Out-Null }

# ============================================
# 4. VERSION MANAGEMENT
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

# Sync version into .mq5 property
$Source5Content = Get-Content $SourceFile5
$Updated5Content = $Source5Content -replace '#property\s+version\s+".*?"', "#property version `"$Version`""
Set-Content -Path $SourceFile5 -Value $Updated5Content -Encoding UTF8

# ============================================
# 5. COMPILATION
# ============================================
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# --- 5.1 COMPILE MT4 ---
$BuildName = "${IndicatorName}_v${Version}_$Timestamp.ex4"
$BuildOutput = Join-Path $BuildDir $BuildName

Write-Host "Compiling $IndicatorName (MT4)..." -ForegroundColor Yellow
& "$MetaEditor" /compile:"$SourceFile" /log:"$TempLogFile" | Out-Null
Start-Sleep -Seconds 5

if (!(Test-Path $TempLogFile)) { Write-Error "MT4 Compiler did not produce a log."; exit 7 }
$LogContent = Get-Content $TempLogFile -Raw

# Parse MT4 Results
if ($LogContent -match "Result:\s+([0-9]+)\s+errors,\s+([0-9]+)\s+warnings") {
    $ErrorCount = [int]$Matches[1]
    $WarningCount = [int]$Matches[2]

    if ($ErrorCount -gt 0) {
        Write-Host "MT4 BUILD FAILED - $ErrorCount ERRORS" -ForegroundColor Red
        Add-Content -Path $LogFile -Value "[$(Get-Date)] MT4 FAILED: $BuildName`n$LogContent"
        Write-Host "Please check the detailed log at: $LogFile" -ForegroundColor Cyan
        exit 7
    }
}

# Log successful MT4 session
$SessionHeader = "`n==========================================`n[MT4 Build: $BuildName] @ $(Get-Date)`n==========================================`n"
Add-Content -Path $LogFile -Value "$SessionHeader$LogContent"
if (Test-Path $TempLogFile) { Remove-Item $TempLogFile -Force }

$GeneratedEX4 = Join-Path $ProjectRoot "$IndicatorName.ex4"
if (!(Test-Path $GeneratedEX4)) { Write-Error "EX4 not found after compilation."; exit 8 }
Move-Item -Path $GeneratedEX4 -Destination $BuildOutput -Force


# --- 5.2 COMPILE MT5 ---
$BuildName5 = "${IndicatorName}_v${Version}_$Timestamp.ex5"
$BuildOutput5 = Join-Path $BuildDir $BuildName5

Write-Host "Compiling $IndicatorName (MT5)..." -ForegroundColor Yellow
& "$MetaEditor5" /compile:"$SourceFile5" /log:"$TempLogFile5" | Out-Null
Start-Sleep -Seconds 5

if (!(Test-Path $TempLogFile5)) { Write-Error "MT5 Compiler did not produce a log."; exit 7 }
$LogContent5 = Get-Content $TempLogFile5 -Raw

# Parse MT5 Results
if ($LogContent5 -match "Result:\s+([0-9]+)\s+errors,\s+([0-9]+)\s+warnings") {
    $ErrorCount5 = [int]$Matches[1]
    $WarningCount5 = [int]$Matches[2]

    if ($ErrorCount5 -gt 0) {
        Write-Host "MT5 BUILD FAILED - $ErrorCount5 ERRORS" -ForegroundColor Red
        Add-Content -Path $LogFile -Value "[$(Get-Date)] MT5 FAILED: $BuildName5`n$LogContent5"
        Write-Host "Please check the detailed log at: $LogFile" -ForegroundColor Cyan
        exit 7
    }
}

# Log successful MT5 session
$SessionHeader5 = "`n==========================================`n[MT5 Build: $BuildName5] @ $(Get-Date)`n==========================================`n"
Add-Content -Path $LogFile -Value "$SessionHeader5$LogContent5"
if (Test-Path $TempLogFile5) { Remove-Item $TempLogFile5 -Force }

$GeneratedEX5 = Join-Path $ProjectRoot "$IndicatorName.ex5"
if (!(Test-Path $GeneratedEX5)) { Write-Error "EX5 not found after compilation."; exit 8 }
Move-Item -Path $GeneratedEX5 -Destination $BuildOutput5 -Force


# --- 5.3 COMPILE EA (MT4) ---
$EABuildName = "${EAName}_v${Version}_$Timestamp.ex4"
$EABuildOutput = Join-Path $BuildDir $EABuildName

Write-Host "Compiling $EAName (MT4)..." -ForegroundColor Yellow
& "$MetaEditor" /compile:"$EASourceFile" /log:"$EATempLogFile" | Out-Null
Start-Sleep -Seconds 5

if (!(Test-Path $EATempLogFile)) { Write-Error "MT4 Compiler did not produce a log for EA."; exit 7 }
$EALogContent = Get-Content $EATempLogFile -Raw

# Parse MT4 EA Results
if ($EALogContent -match "Result:\s+([0-9]+)\s+errors,\s+([0-9]+)\s+warnings") {
    $EAErrorCount = [int]$Matches[1]
    $EAWarningCount = [int]$Matches[2]

    if ($EAErrorCount -gt 0) {
        Write-Host "MT4 EA BUILD FAILED - $EAErrorCount ERRORS" -ForegroundColor Red
        Add-Content -Path $LogFile -Value "[$(Get-Date)] MT4 EA FAILED: $EABuildName`n$EALogContent"
        Write-Host "Please check the detailed log at: $LogFile" -ForegroundColor Cyan
        exit 7
    }
}

# Log successful MT4 EA session
$EASessionHeader = "`n==========================================`n[MT4 EA Build: $EABuildName] @ $(Get-Date)`n==========================================`n"
Add-Content -Path $LogFile -Value "$EASessionHeader$EALogContent"
if (Test-Path $EATempLogFile) { Remove-Item $EATempLogFile -Force }

$GeneratedEAEX4 = Join-Path $ProjectRoot "Experts\$EAName.ex4"
if (!(Test-Path $GeneratedEAEX4)) { Write-Error "EA EX4 not found after compilation."; exit 8 }
Move-Item -Path $GeneratedEAEX4 -Destination $EABuildOutput -Force


# --- 5.4 COMPILE EA (MT5) ---
$EABuildName5 = "${EAName}_v${Version}_$Timestamp.ex5"
$EABuildOutput5 = Join-Path $BuildDir $EABuildName5

Write-Host "Compiling $EAName (MT5)..." -ForegroundColor Yellow
& "$MetaEditor5" /compile:"$EASourceFile5" /log:"$EATempLogFile5" | Out-Null
Start-Sleep -Seconds 5

if (!(Test-Path $EATempLogFile5)) { Write-Error "MT5 Compiler did not produce a log for EA."; exit 7 }
$EALogContent5 = Get-Content $EATempLogFile5 -Raw

# Parse MT5 EA Results
if ($EALogContent5 -match "Result:\s+([0-9]+)\s+errors,\s+([0-9]+)\s+warnings") {
    $EAErrorCount5 = [int]$Matches[1]
    $EAWarningCount5 = [int]$Matches[2]

    if ($EAErrorCount5 -gt 0) {
        Write-Host "MT5 EA BUILD FAILED - $EAErrorCount5 ERRORS" -ForegroundColor Red
        Add-Content -Path $LogFile -Value "[$(Get-Date)] MT5 EA FAILED: $EABuildName5`n$EALogContent5"
        Write-Host "Please check the detailed log at: $LogFile" -ForegroundColor Cyan
        exit 7
    }
}

# Log successful MT5 EA session
$EASessionHeader5 = "`n==========================================`n[MT5 EA Build: $EABuildName5] @ $(Get-Date)`n==========================================`n"
Add-Content -Path $LogFile -Value "$EASessionHeader5$EALogContent5"
if (Test-Path $EATempLogFile5) { Remove-Item $EATempLogFile5 -Force }

$GeneratedEAEX5 = Join-Path $ProjectRoot "Experts\$EAName.ex5"
if (!(Test-Path $GeneratedEAEX5)) { Write-Error "EA EX5 not found after compilation."; exit 8 }
Move-Item -Path $GeneratedEAEX5 -Destination $EABuildOutput5 -Force


# ============================================
# 6. MULTI-TERMINAL DEPLOYMENT
# ============================================
Write-Host ""
Write-Host "DEPLOYING TO TERMINALS..." -ForegroundColor Cyan

# Deploy MT4
foreach ($ID in $MT4TerminalIDs) {
    $TargetDir = Join-Path (Join-Path $AppDataPath $ID) "MQL4\Indicators"
    $DeployPath = Join-Path $TargetDir "$IndicatorName.ex4"

    if (Test-Path $TargetDir) {
        Copy-Item -Path $BuildOutput -Destination $DeployPath -Force
        Write-Host "  [MT4 OK] Deployed -> $ID" -ForegroundColor Green
    }
    else {
        Write-Host "  [MT4 SKIP] Terminal folder not found: $ID" -ForegroundColor Yellow
    }
}

# Deploy MT5
foreach ($ID in $MT5TerminalIDs) {
    $TargetDir = Join-Path (Join-Path $AppDataPath $ID) "MQL5\Indicators"
    $DeployPath = Join-Path $TargetDir "$IndicatorName.ex5"

    if (Test-Path $TargetDir) {
        Copy-Item -Path $BuildOutput5 -Destination $DeployPath -Force
        Write-Host "  [MT5 OK] Deployed -> $ID" -ForegroundColor Green
    }
    else {
        Write-Host "  [MT5 SKIP] Terminal folder not found: $ID" -ForegroundColor Yellow
    }
}

# Deploy EA MT4
foreach ($ID in $MT4TerminalIDs) {
    $TargetDir = Join-Path (Join-Path $AppDataPath $ID) "MQL4\Experts"
    $DeployPath = Join-Path $TargetDir "$EAName.ex4"

    if (Test-Path $TargetDir) {
        Copy-Item -Path $EABuildOutput -Destination $DeployPath -Force
        Write-Host "  [MT4 EA OK] Deployed -> $ID" -ForegroundColor Green
    }
    else {
        Write-Host "  [MT4 EA SKIP] Terminal folder not found: $ID" -ForegroundColor Yellow
    }
}

# Deploy EA MT5
foreach ($ID in $MT5TerminalIDs) {
    $TargetDir = Join-Path (Join-Path $AppDataPath $ID) "MQL5\Experts"
    $DeployPath = Join-Path $TargetDir "$EAName.ex5"

    if (Test-Path $TargetDir) {
        Copy-Item -Path $EABuildOutput5 -Destination $DeployPath -Force
        Write-Host "  [MT5 EA OK] Deployed -> $ID" -ForegroundColor Green
    }
    else {
        Write-Host "  [MT5 EA SKIP] Terminal folder not found: $ID" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=========================================="
Write-Host "BUILD & DEPLOY SUCCESS" -ForegroundColor Green
Write-Host "MT4 Artifact: $BuildOutput"
Write-Host "MT5 Artifact: $BuildOutput5"
Write-Host "MT4 EA Artifact: $EABuildOutput"
Write-Host "MT5 EA Artifact: $EABuildOutput5"
Write-Host "=========================================="
