# Windows SSH

別の Windows 開発端末へ SSH 接続するための設定です。
LAN や VPN など、信頼できるネットワーク内だけで使ってください。

実行する前に、スクリプト本体を開いて確認してください。

## クライアント側

接続元の PowerShell で、引数なしで実行します。

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/nuitsjp/run/main/windows-ssh/Enable-OpenSshClient.ps1)))
```

```text
cmdlet  at command pipeline position 1
Supply values for the following parameters:
HostName: 192.168.1.100
HostAlias: dev-pc
SSH鍵を作成します: C:\Users\nuits\.ssh\id_ed25519_dev-pc
Generating public/private ed25519 key pair.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:

クライアント側のSSH設定が完了しました。
  Host     : dev-pc
  HostName : 192.168.1.100
  User     : nuits
  Identity : C:\Users\nuits\.ssh\id_ed25519_dev-pc

公開鍵:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExamplePublicKeyData nuits@CLIENT

この公開鍵をコピーし、サーバー側の PublicKey へ貼り付けてください。
接続例: ssh dev-pc
```

`HostName` は接続先の IP アドレスまたはホスト名、`HostAlias` は `ssh` で使う名前です。未指定の鍵ファイル名は `HostAlias` から決めます。表示された公開鍵をコピーしてください。

## サーバー側

接続先の管理者 PowerShell で、引数なしで実行します。

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/nuitsjp/run/main/windows-ssh/Enable-OpenSshServer.ps1)))
```

```text
cmdlet  at command pipeline position 1
Supply values for the following parameters:
PublicKey: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExamplePublicKeyData nuits@CLIENT
OpenSSH Server をインストールします。
ファイアウォールで TCP/22 を許可します。
公開鍵を登録しました: C:\ProgramData\ssh\administrators_authorized_keys

OpenSSH Server の設定が完了しました。
  Computer : DEVPC
  User     : nuits
  sshd     : Running / Automatic
  Port     : 22
  Firewall : TCP/22 Allow
  Password : Disabled

接続例: ssh nuits@DEVPC
```

`PublicKey` に、クライアント側で表示された公開鍵を貼り付けます。

## 接続

```powershell
ssh dev-pc
```
