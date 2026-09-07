[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$HostName,

    [Parameter(Mandatory)]
    [string]$HostAlias,

    [string]$User = $env:USERNAME,

    [string]$IdentityName
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

function Assert-SshKeygen {
    if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
        return
    }

    Write-Host 'OpenSSH Client が見つからないため、インストールします。'
    Assert-Administrator

    $capability = Get-WindowsCapability -Online | Where-Object Name -Like 'OpenSSH.Client*'
    if (-not $capability) {
        throw 'OpenSSH.Client capability が見つかりません。対応するWindowsで実行してください。'
    }

    if ($capability.State -ne 'Installed') {
        Add-WindowsCapability -Online -Name $capability.Name | Out-Null
    }

    if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        throw 'ssh-keygen が見つかりません。ターミナルを開き直してから再実行してください。'
    }
}

function Set-SshHostConfig {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Alias,
        [Parameter(Mandatory)] [string]$HostName,
        [Parameter(Mandatory)] [string]$User,
        [Parameter(Mandatory)] [string]$IdentityFile
    )

    $blockLines = @(
        "Host $Alias"
        "    HostName $HostName"
        "    User $User"
        "    IdentityFile $IdentityFile"
        "    IdentitiesOnly yes"
    )

    $lines = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $lines = @(Get-Content -LiteralPath $Path)
        if ($lines.Count -gt 0) {
            $lines[0] = $lines[0].TrimStart([char]0xFEFF)
        }
    }

    $out = @()
    $inBlock = $false
    $replaced = $false
    $escapedAlias = [regex]::Escape($Alias)

    foreach ($line in $lines) {
        if ($line -match '^(Host|Match)[ \t]+') {
            $inBlock = $false
            if ($line -match "^Host[ \t]+$escapedAlias([ \t].*)?$") {
                if (-not $replaced) {
                    $out += $blockLines
                    $replaced = $true
                }
                $inBlock = $true
                continue
            }
        }

        if (-not $inBlock) {
            $out += $line
        }
    }

    if (-not $replaced) {
        if ($out.Count -gt 0 -and $out[-1] -ne '') {
            $out += ''
        }
        $out += $blockLines
    }

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($Path, $out, $utf8)
}

function Get-DefaultIdentityName {
    param(
        [Parameter(Mandatory)] [string]$HostAlias
    )

    $safe = $HostAlias -replace '[<>:"/\\|?*]', '_'
    if ([string]::IsNullOrWhiteSpace($safe) -or $safe -in @('.', '..')) {
        throw 'HostAlias から鍵ファイル名を作れません。'
    }

    return "id_ed25519_$safe"
}

if ([string]::IsNullOrWhiteSpace($HostName)) {
    throw 'HostName を入力してください。'
}

if ([string]::IsNullOrWhiteSpace($HostAlias)) {
    throw 'HostAlias を入力してください。'
}

$HostName = $HostName.Trim()
$HostAlias = $HostAlias.Trim()

if ([string]::IsNullOrWhiteSpace($IdentityName)) {
    $IdentityName = Get-DefaultIdentityName -HostAlias $HostAlias
}

if ($HostAlias -notmatch '^[A-Za-z0-9._-]+$') {
    throw 'HostAlias は英数字、ドット、アンダースコア、ハイフンのみ使えます。'
}

if ($IdentityName -match '[\\/:]' -or $IdentityName -in @('.', '..')) {
    throw 'IdentityName はファイル名を指定してください。'
}

Assert-SshKeygen

$sshDirectory = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null

$identityFile = Join-Path $sshDirectory $IdentityName
$publicKeyFile = "$identityFile.pub"

if (-not (Test-Path -LiteralPath $identityFile -PathType Leaf)) {
    Write-Host "SSH鍵を作成します: $identityFile"
    & ssh-keygen -t ed25519 -a 64 -f $identityFile
    if ($LASTEXITCODE -ne 0) {
        throw 'ssh-keygen に失敗しました。'
    }
}
else {
    Write-Host "既存のSSH鍵を使います: $identityFile"
}

if (-not (Test-Path -LiteralPath $publicKeyFile -PathType Leaf)) {
    throw "公開鍵が見つかりません: $publicKeyFile"
}

$publicKey = (Get-Content -LiteralPath $publicKeyFile -Raw).Trim()
$configPath = Join-Path $sshDirectory 'config'
$configIdentityFile = "~/.ssh/$IdentityName"

Set-SshHostConfig `
    -Path $configPath `
    -Alias $HostAlias `
    -HostName $HostName `
    -User $User `
    -IdentityFile $configIdentityFile

Write-Host ''
Write-Host 'クライアント側のSSH設定が完了しました。'
Write-Host "  Host     : $HostAlias"
Write-Host "  HostName : $HostName"
Write-Host "  User     : $User"
Write-Host "  Identity : $identityFile"
Write-Host ''
Write-Host '公開鍵:'
Write-Host $publicKey
Write-Host ''
Write-Host 'この公開鍵をコピーし、サーバー側の PublicKey へ貼り付けてください。'
Write-Host "接続例: ssh $HostAlias"
