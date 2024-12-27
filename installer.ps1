Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction']='Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

# URL to the checksum file
$ChecksumUrl = "https://raw.githubusercontent.com/hyperledger-web3j/web3j-installer/main/checksum-windows.txt"
$ScriptUrl = "https://raw.githubusercontent.com/hyperledger-web3j/web3j-installer/main/installer.ps1"

# Function to fetch the pre-calculated checksum
function Fetch-Checksum {
    try {
        return (Invoke-WebRequest -Uri $ChecksumUrl).Content.Trim()
    } catch {
        Write-Output "Error fetching checksum from GitHub."
        exit 1
    }
}

# Function to get the script content (handle both file and in-memory execution)
function Get-ScriptContent {
    if ($PSScriptRoot) {
        # Running from a file
        $scriptPath = Join-Path $PSScriptRoot "installer.ps1"
        return Get-Content $scriptPath | ForEach-Object { $_ -replace "`r", "" } | Where-Object { $_ -notmatch '^[\s]*\$ChecksumUrl' } | Out-String
    } else {
        # Running from memory
        return (Invoke-WebRequest -Uri $ScriptUrl).Content -split "`n" | ForEach-Object { $_ -replace "`r", "" } | Where-Object { $_ -notmatch '^[\s]*\$ChecksumUrl' } | Out-String
    }
}

# Function to calculate the current checksum of the script
function Calculate-Checksum {
    $scriptContent = Get-ScriptContent
    $scriptContent = $scriptContent.Trim()
    $scriptBytes = [System.Text.Encoding]::UTF8.GetBytes($scriptContent)
    $hash = (New-Object Security.Cryptography.SHA256Managed).ComputeHash($scriptBytes)
    return -join ($hash | ForEach-Object { $_.ToString("x2") })
}

# Verify the integrity of the script
function Verify-Checksum {
    $fetchedChecksum = Fetch-Checksum
    $currentChecksum = Calculate-Checksum

    if ($currentChecksum -eq $fetchedChecksum) {
        Write-Output "Script checksum verification passed."
    } else {
        Write-Output "Script checksum verification failed."
        exit 1
    }
}

# Run checksum verification
Verify-Checksum

$web3j_version = (Invoke-WebRequest -Uri "https://api.github.com/repos/hyperledger-web3j/web3j-cli/releases/latest").Content | ConvertFrom-Json | Select-Object -ExpandProperty tag_name | ForEach-Object { $_.Substring(1) }

New-Item -Force -ItemType directory -Path "${env:USERPROFILE}\.web3j" | Out-Null
$url = "https://github.com/hyperledger-web3j/web3j-cli/releases/download/v${web3j_version}/web3j-cli-shadow-${web3j_version}.zip"
$output = "${env:USERPROFILE}\.web3j\web3j.zip"
Write-Output "Downloading Web3j version ${web3j_version}..."
Invoke-WebRequest -Uri $url -OutFile $output
Write-Output "Extracting Web3j..."
Expand-Archive -Path "${env:USERPROFILE}\.web3j\web3j.zip" -DestinationPath "${env:USERPROFILE}\.web3j\" -Force
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)

if (!($CurrentPath -match $web3j_version)) {
    [Environment]::SetEnvironmentVariable(
            "Path",
            $CurrentPath + ";${env:USERPROFILE}\.web3j\web3j-cli-shadow-${web3j_version}\bin",
            [EnvironmentVariableTarget]::User)
    Write-Output "Web3j has been added to your PATH variable. You will need to open a new CMD/PowerShell instance to use it."
}

Write-Output "Web3j has been successfully installed (assuming errors were printed to your console)."
