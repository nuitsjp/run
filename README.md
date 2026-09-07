# run

個人用の便利スクリプトを、URL 指定のワンライナーで実行するための置き場です。

インストールせず、その場で使いたい小さな処理を置きます。
公開しているのは自分用ですが、中身を確認したうえで使っても構いません。

> **実行する前に、必ずスクリプト本体を開いて確認してください。**
> `irm | iex` や `curl | bash` は、取得した内容をそのまま実行します。

## スクリプト

| 名前 | 環境 | 説明 | 実行例 |
| --- | --- | --- | --- |
| [windows-ssh/Enable-OpenSshClient.ps1](windows-ssh/Enable-OpenSshClient.ps1) | Windows | SSH鍵と `~/.ssh/config` を用意する | `& ([scriptblock]::Create((irm https://raw.githubusercontent.com/nuitsjp/run/main/windows-ssh/Enable-OpenSshClient.ps1)))` |
| [windows-ssh/Enable-OpenSshServer.ps1](windows-ssh/Enable-OpenSshServer.ps1) | Windows | OpenSSH Server を有効化する | `& ([scriptblock]::Create((irm https://raw.githubusercontent.com/nuitsjp/run/main/windows-ssh/Enable-OpenSshServer.ps1)))` |

手順の詳細は [windows-ssh/README.md](windows-ssh/README.md) を参照してください。
