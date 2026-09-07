[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PublicKey,

    [switch]$KeepPasswordAuthentication
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '管理者権限で実行してください。'
    }
}

function Install-OpenSshCapability {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$DisplayName
    )

    # PowerShell 7 の Get-WindowsCapability は COM エラーになるため DISM を使う
    $dism = Join-Path $env:WINDIR 'System32\dism.exe'
    $PSNativeCommandUseErrorActionPreference = $false

    $info = & $dism /English /Online /Get-CapabilityInfo "/CapabilityName:$Name" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "$DisplayName capability が見つかりません。対応するWindowsで実行してください。"
    }

    if ($info -match '(?im)^\s*State\s*:\s*Installed\s*$') {
        Write-Host "$DisplayName はインストール済みです。"
        return
    }

    Write-Host "$DisplayName をインストールします。"
    & $dism /English /Online /Add-Capability "/CapabilityName:$Name"
    if ($LASTEXITCODE -ne 0) {
        throw "$DisplayName のインストールに失敗しました。"
    }
}

function Set-SshdConfigValue {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Value
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $pattern = "(?im)^\s*#?\s*$([regex]::Escape($Name))\s+.*$"
    $replacement = "$Name $Value"

    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, $replacement, 1)
    }
    else {
        $content = $content.TrimEnd() + "`r`n$replacement`r`n"
    }

    Set-Content -LiteralPath $Path -Value $content -Encoding ascii -NoNewline
}

function Add-AdministratorAuthorizedKey {
    param(
        [Parameter(Mandatory)] [string]$Key
    )

    if ($Key -notmatch '^ssh-(ed25519|rsa|ecdsa-[^\s]+)\s+') {
        throw '公開鍵の形式を確認してください。OpenSSH形式の公開鍵を指定してください。'
    }

    $authorizedKeys = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    New-Item -ItemType File -Path $authorizedKeys -Force | Out-Null

    $existing = @(Get-Content -LiteralPath $authorizedKeys -ErrorAction SilentlyContinue)
    if ($existing -notcontains $Key) {
        Add-Content -LiteralPath $authorizedKeys -Value $Key -Encoding ascii
    }

    & icacls.exe $authorizedKeys /inheritance:r | Out-Null
    & icacls.exe $authorizedKeys /grant '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'administrators_authorized_keys のACL設定に失敗しました。'
    }

    Write-Host "公開鍵を登録しました: $authorizedKeys"
}

Assert-Administrator

$keyText = $PublicKey.Trim()
if (-not $keyText) {
    throw '公開鍵を入力してください。'
}

Install-OpenSshCapability -Name 'OpenSSH.Server~~~~0.0.1.0' -DisplayName 'OpenSSH Server'

Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd

$firewallRuleName = 'OpenSSH-Server-In-TCP'
if (-not (Get-NetFirewallRule -Name $firewallRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule `
        -Name $firewallRuleName `
        -DisplayName 'OpenSSH SSH Server (sshd)' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 | Out-Null
}
else {
    Enable-NetFirewallRule -Name $firewallRuleName
}

Add-AdministratorAuthorizedKey -Key $keyText

$sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
if (-not (Test-Path -LiteralPath $sshdConfig -PathType Leaf)) {
    throw "sshd_config が見つかりません: $sshdConfig"
}

$backup = "$sshdConfig.bak"
Copy-Item -LiteralPath $sshdConfig -Destination $backup -Force

Set-SshdConfigValue -Path $sshdConfig -Name 'PubkeyAuthentication' -Value 'yes'
if (-not $KeepPasswordAuthentication) {
    Set-SshdConfigValue -Path $sshdConfig -Name 'PasswordAuthentication' -Value 'no'
}

$sshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
& $sshdExe -t -f $sshdConfig
if ($LASTEXITCODE -ne 0) {
    Copy-Item -LiteralPath $backup -Destination $sshdConfig -Force
    throw "sshd_config の検証に失敗しました。変更前の設定へ戻しました: $backup"
}

Restart-Service -Name sshd

$service = Get-Service -Name sshd
Write-Host ''
Write-Host 'OpenSSH Server の設定が完了しました。'
Write-Host "  Computer : $env:COMPUTERNAME"
Write-Host "  User     : $env:USERNAME"
Write-Host "  sshd     : $($service.Status) / Automatic"
Write-Host '  Port     : 22'
Write-Host "  Password : $(if ($KeepPasswordAuthentication) { '既存設定を維持' } else { 'Disabled' })"
Write-Host ''
Write-Host "接続例: ssh $env:USERNAME@$env:COMPUTERNAME"
