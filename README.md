# web3j-installer
Command line installer for Web3j

### How to (Linux/macOS):
In a terminal, run the following command:

```sh
installer=$(mktemp) &&
curl --disable --proto '=https' --proto-redir '=https' --fail --show-error --silent --location https://get.web3j.io -o "$installer" &&
sh "$installer" && rm -f "$installer"
```

The installer and all its redirects must use HTTPS. Download failures stop installation before extraction. Keep the OS/curl CA bundle current; HTTPS-only downloads do not replace certificate-trust updates.

This script will not work if Web3j has been installed using Homebrew on macOS.

### How to (Windows):
In PowerShell, run the following command:

`Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/hyperledger-web3j/web3j-installer/main/installer.ps1'))`
