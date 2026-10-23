# web3j-installer
Command line installer for Web3j

### How to (Linux/macOS):
In a terminal, run the following command:

```sh
curl -L https://get.web3j.io | sh
```

The installer handles HTTPS-only downloads and checksum verification automatically. Failed downloads stop installation before extraction. Keep the OS/curl CA bundle current; HTTPS downloads do not replace certificate-trust updates.

This script will not work if Web3j has been installed using Homebrew on macOS.

### How to (Windows):
In PowerShell, run the following command:

`Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/hyperledger-web3j/web3j-installer/main/installer.ps1'))`
