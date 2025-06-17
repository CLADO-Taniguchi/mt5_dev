# NSSM Direct Conda Environment Setup (No Batch Files)

param(
    [string]$Environment = "production"
)

$NSSM_PATH = "C:\Program Files\nssm\win64\nssm.exe"
$SERVICE_NAME = "FlaskTradingAPI"

# mt5env environment paths
$MT5ENV_PYTHON = "C:\Users\Administrator\miniconda3\envs\mt5env\python.exe"
$MT5ENV_SCRIPTS = "C:\Users\Administrator\miniconda3\envs\mt5env\Scripts"
$MT5ENV_LIB = "C:\Users\Administrator\miniconda3\envs\mt5env\Lib\site-packages"
$CONDA_BASE = "C:\Users\Administrator\miniconda3"
$WORK_DIR = "C:\MT5_portable\MQL5\src\trading_system"
$SCRIPT_PATH = "$WORK_DIR\flask_trading_api.py"

Write-Host "=== NSSM Direct Conda Environment Setup ===" -ForegroundColor Green

# Administrator check
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Administrator privileges required" -ForegroundColor Red
    exit 1
}

# Verify mt5env environment
Write-Host "`n[1] Verify mt5env Environment" -ForegroundColor Cyan

$pathsToCheck = @(
    @{name="mt5env Python"; path=$MT5ENV_PYTHON},
    @{name="mt5env Scripts"; path=$MT5ENV_SCRIPTS},
    @{name="mt5env site-packages"; path=$MT5ENV_LIB},
    @{name="Flask Script"; path=$SCRIPT_PATH},
    @{name="Work Directory"; path=$WORK_DIR}
)

foreach ($pathCheck in $pathsToCheck) {
    if (Test-Path $pathCheck.path) {
        Write-Host "SUCCESS: $($pathCheck.name)" -ForegroundColor Green
    } else {
        Write-Host "ERROR: $($pathCheck.name) not found at $($pathCheck.path)" -ForegroundColor Red
        exit 1
    }
}

# Test Flask in mt5env
Write-Host "`n[2] Test Flask in mt5env" -ForegroundColor Cyan
try {
    $flaskTest = & $MT5ENV_PYTHON -c "import flask, pandas, numpy; print('All packages OK')" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: All packages available in mt5env" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Packages not available in mt5env" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "ERROR: Cannot test mt5env packages" -ForegroundColor Red
    exit 1
}

# Remove existing service
Write-Host "`n[3] Remove Existing Service" -ForegroundColor Cyan

Write-Host "Stopping service..." -ForegroundColor Yellow
& $NSSM_PATH stop $SERVICE_NAME 2>$null
Start-Sleep -Seconds 5

Write-Host "Removing service..." -ForegroundColor Yellow
& $NSSM_PATH remove $SERVICE_NAME confirm 2>$null
Start-Sleep -Seconds 3

# Force kill processes
$processesToKill = @("python", "cmd")
foreach ($processName in $processesToKill) {
    $processes = Get-Process $processName* -ErrorAction SilentlyContinue
    if ($processes) {
        Stop-Process -Name $processName -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 3

$serviceStatus = & $NSSM_PATH status $SERVICE_NAME 2>$null
if ($serviceStatus -eq "SERVICE_NOT_FOUND") {
    Write-Host "SUCCESS: Service removed" -ForegroundColor Green
} else {
    Write-Host "WARNING: Service removal incomplete: $serviceStatus" -ForegroundColor Yellow
}

# Install new service (direct Python)
Write-Host "`n[4] Install New Service (Direct Python)" -ForegroundColor Cyan

Write-Host "Installing service..." -ForegroundColor Yellow
$installResult = & $NSSM_PATH install $SERVICE_NAME $MT5ENV_PYTHON $SCRIPT_PATH 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Service installed" -ForegroundColor Green
} else {
    Write-Host "ERROR: Service installation failed: $installResult" -ForegroundColor Red
    exit 1
}

# Configure service with comprehensive environment variables
Write-Host "`n[5] Configure Service Environment" -ForegroundColor Cyan

# Set working directory
& $NSSM_PATH set $SERVICE_NAME AppDirectory $WORK_DIR
Write-Host "SUCCESS: Working directory set" -ForegroundColor Green

# Create comprehensive PATH for conda environment
$fullPath = @(
    $MT5ENV_SCRIPTS,
    $MT5ENV_PYTHON.Replace('\python.exe', ''),
    "$CONDA_BASE\Scripts",
    $CONDA_BASE,
    "$CONDA_BASE\Library\bin",
    "$CONDA_BASE\Library\mingw-w64\bin",
    "$CONDA_BASE\Library\usr\bin",
    "C:\Windows\System32",
    "C:\Windows"
) -join ";"

# Set comprehensive environment variables
$envVariables = @(
    "PATH=$fullPath",
    "PYTHONPATH=$MT5ENV_LIB;$WORK_DIR",
    "PYTHONHOME=$($MT5ENV_PYTHON.Replace('\python.exe', ''))",
    "CONDA_DEFAULT_ENV=mt5env",
    "CONDA_PREFIX=$($MT5ENV_PYTHON.Replace('\python.exe', ''))",
    "CONDA_PYTHON_EXE=$CONDA_BASE\python.exe",
    "CONDA_EXE=$CONDA_BASE\Scripts\conda.exe",
    "PYTHONUNBUFFERED=1",
    "FLASK_ENV=production"
)

$envString = $envVariables -join "`r`n"
& $NSSM_PATH set $SERVICE_NAME AppEnvironmentExtra $envString
Write-Host "SUCCESS: Environment variables configured" -ForegroundColor Green

# Log configuration
$logDir = Join-Path $WORK_DIR "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

& $NSSM_PATH set $SERVICE_NAME AppStdout "$logDir\flask_stdout.log"
& $NSSM_PATH set $SERVICE_NAME AppStderr "$logDir\flask_stderr.log"
Write-Host "SUCCESS: Logging configured" -ForegroundColor Green

# Restart configuration
& $NSSM_PATH set $SERVICE_NAME AppExit Default Restart
& $NSSM_PATH set $SERVICE_NAME AppRestartDelay 10000
& $NSSM_PATH set $SERVICE_NAME AppThrottle 5000
Write-Host "SUCCESS: Restart behavior configured" -ForegroundColor Green

# Process priority
& $NSSM_PATH set $SERVICE_NAME AppPriority NORMAL_PRIORITY_CLASS
Write-Host "SUCCESS: Process priority configured" -ForegroundColor Green

# Start service
Write-Host "`n[6] Start Service" -ForegroundColor Cyan

Write-Host "Starting service..." -ForegroundColor Yellow
$startResult = & $NSSM_PATH start $SERVICE_NAME 2>&1
Start-Sleep -Seconds 10

# Check status
$finalStatus = & $NSSM_PATH status $SERVICE_NAME
Write-Host "Service Status: $finalStatus" -ForegroundColor $(if($finalStatus -eq "SERVICE_RUNNING"){"Green"}else{"Red"})

if ($finalStatus -eq "SERVICE_RUNNING") {
    Write-Host "SUCCESS: Service running!" -ForegroundColor Green
    
    # Test API
    Write-Host "`n[7] API Test" -ForegroundColor Cyan
    Start-Sleep -Seconds 5
    
    for ($i = 1; $i -le 3; $i++) {
        Write-Host "API test attempt $i..." -ForegroundColor Yellow
        try {
            $healthCheck = Invoke-WebRequest -Uri "http://localhost:5000/health" -TimeoutSec 10
            if ($healthCheck.StatusCode -eq 200) {
                Write-Host "SUCCESS: API is responding!" -ForegroundColor Green
                $healthData = $healthCheck.Content | ConvertFrom-Json
                Write-Host "   Status: $($healthData.status)" -ForegroundColor Gray
                Write-Host "   Symbols: $($healthData.active_symbols -join ', ')" -ForegroundColor Gray
                Write-Host "   Models: $($healthData.symbols_with_models)" -ForegroundColor Gray
                break
            }
        }
        catch {
            if ($i -eq 3) {
                Write-Host "WARNING: API not responding after 3 attempts" -ForegroundColor Yellow
            } else {
                Write-Host "Retrying in 5 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            }
        }
    }
} else {
    Write-Host "ERROR: Service failed to start" -ForegroundColor Red
    
    # Show logs
    $errorLogPath = "$logDir\flask_stderr.log"
    if (Test-Path $errorLogPath) {
        Write-Host "`n--- Error Log (Last 15 lines) ---" -ForegroundColor Yellow
        Get-Content $errorLogPath -Tail 15 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    }
    
    $stdoutLogPath = "$logDir\flask_stdout.log"
    if (Test-Path $stdoutLogPath) {
        Write-Host "`n--- Stdout Log (Last 10 lines) ---" -ForegroundColor Yellow
        Get-Content $stdoutLogPath -Tail 10 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    }
}

# Summary
Write-Host "`n[8] Configuration Summary" -ForegroundColor Cyan
Write-Host "Service Name: $SERVICE_NAME" -ForegroundColor Gray
Write-Host "Python: $MT5ENV_PYTHON" -ForegroundColor Gray
Write-Host "Script: $SCRIPT_PATH" -ForegroundColor Gray
Write-Host "Environment: mt5env (direct)" -ForegroundColor Gray
Write-Host "Method: Direct Python execution with full environment" -ForegroundColor Gray
Write-Host "Logs: $logDir" -ForegroundColor Gray

# Manual verification commands
Write-Host "`nManual verification commands:" -ForegroundColor Yellow
Write-Host "Service status: & '$NSSM_PATH' status $SERVICE_NAME" -ForegroundColor White
Write-Host "API health: curl http://localhost:5000/health" -ForegroundColor White
Write-Host "View logs: Get-Content '$logDir\flask_stderr.log' -Tail 20" -ForegroundColor White

Write-Host "`n=== Direct Conda Setup Complete ===" -ForegroundColor Green