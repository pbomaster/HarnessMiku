param([string]$Source, [string]$Model, [switch]$Speech)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$logging = $false
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    try {
        $logDir = Join-Path $env:LOCALAPPDATA 'Harness Miku\InstallLogs'
        [void][IO.Directory]::CreateDirectory($logDir)
        $logFile = Join-Path $logDir ("setup-" + (Get-Date -Format yyyyMMdd-HHmmss) + "-" + $PID + ".log")
        Start-Transcript -LiteralPath $logFile | Out-Null
        $logging = $true
    } catch {
        Write-Host "Could not start the installation log. Continuing in the console."
    }
    if ($Source -eq "--speech") { $Speech = $true; $Source = "" }
    $installed = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'
    $destination = Join-Path $env:LOCALAPPDATA 'Programs\Harness Miku'
    if (!$Source) {
        $Source = $installed
        if ($Speech -and (Test-Path $destination)) { $Source = $destination }
    }
    if (!$Speech -and (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $destination 'DeepSeek Harness.exe') })) {
        throw "Exit Harness Miku, including its desktop pet, then run setup again."
    }
    if (!(Test-Path (Join-Path $Source 'DeepSeek Harness.exe'))) {
        if ($Source -ne $installed) { throw "Could not find DeepSeek Harness in the selected folder." }
        Write-Host 'Downloading the official DeepSeek Harness installer...'
        $dir = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        New-Item -ItemType Directory $dir | Out-Null
        try {
            $setup = Join-Path $dir 'DeepSeekSetup.exe'
            Invoke-WebRequest -UseBasicParsing -Uri 'https://download.deepseek.com/dsh-desk/bin/win-x64/deepseek-harness-0.2.1-rc.5-win-x64.exe' -OutFile $setup
            if ((Get-FileHash $setup).Hash -ne '50a2fedf234199e3319cdd6b89c4f0aea601a19fe48259c6e3000883f0d2c6f0') { throw 'Official installer checksum mismatch.' }
            Write-Host 'Installing DeepSeek Harness for the current user...'
            $process = Start-Process $setup -ArgumentList '/S' -PassThru -Wait
            if ($process.ExitCode -ne 0) { throw "DeepSeek setup exited with code $($process.ExitCode)." }
        } finally { Remove-Item -LiteralPath $dir -Recurse -Force }
    }
    $python = Join-Path $Source 'resources\runtime\primary-runtime\dependencies\python\python.exe'
    if (!(Test-Path $python) -or (Get-FileHash $python).Hash -ne '44c9b2d0019ad16e09acf9cb8f8fd96bf02c0e4e81de540087a02b3a3160b502') { throw 'The official Windows x64 0.2.1-rc.5 runtime is required.' }
    $script = Join-Path $PSScriptRoot 'install_windows.py'
    if (!(Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Extract the entire ZIP into one folder, then run Install-Windows.cmd there.' }
    if ($Speech) { & $python -B -E -s -X utf8 $script --speech }
    else {
        if (!$Model) { $Model = Join-Path $PSScriptRoot 'New1007-RetrynowMiku.zip' }
        if (!(Test-Path -LiteralPath $Model -PathType Leaf)) {
            Add-Type -AssemblyName System.Windows.Forms
            $picker = New-Object System.Windows.Forms.OpenFileDialog
            try {
                $picker.Title = 'Select New1007-RetrynowMiku.zip'
                $picker.Filter = 'ZIP (*.zip)|*.zip'
                if ($picker.ShowDialog() -ne 'OK') { exit 0 }
                $Model = $picker.FileName
            } finally { $picker.Dispose() }
        }
        & $python -B -E -s -X utf8 $script $Source $Model
    }
    if ($LASTEXITCODE -ne 0) { throw 'Harness Miku installation did not complete.' }
    if (!$Speech) {
        $exe = Join-Path $destination 'DeepSeek Harness.exe'
        $menu = [Environment]::GetFolderPath('Programs')
        $link = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $menu 'Harness Miku.lnk'))
        $link.TargetPath = $exe
        $link.WorkingDirectory = $destination
        $link.Save()
        Start-Process -FilePath $exe
    }
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($logging) { Write-Host "Installation log: $logFile" }
    exit 1
} finally {
    if ($logging) { Stop-Transcript | Out-Null }
}
