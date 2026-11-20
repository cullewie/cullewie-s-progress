# Kaynak ve dosya karmaları

Kaynak paket 12 PowerShell dosyası içeriyordu; WinGet sürümü bu repodan çıkarıldı. Aşağıdaki değerler repoda kalan 11 dosyayı tanımlar. Her dosyanın boyu bayt cinsindendir.

| Dosya | Bayt | SHA-256 |
|---|---:|---|
| Scripts/Drivers/DDU/DDU.ps1 | 10520 | 564657374be33107ae7c69e61825cf8b2b7eb6ff668d40654908524a4d3ce9b5 |
| Scripts/Drivers/Debloated-Installer/Driver-Installer.ps1 | 37285 | adf2e6121a6fa2171e7b917c59a58af575c68366342cf173f7e542c8dd1b2d24 |
| Scripts/Drivers/Multi-GPU/Driver-Downloader.ps1 | 3574 | 7fa16789d9b81c8baeebd71d972b1c5b117f15f5791399f46fcf18d6d0017ef5 |
| Scripts/Drivers/NVIDIA/NVIDIA-Driver-Updater.ps1 | 5464 | e171d50e5a2f732c79ab18f3f89b28c8f546dd711a29542b0c71afb75fa93302 |
| Scripts/NVIDIA/Digital-Vibrance.ps1 | 10551 | e3ba8e46b90f3b353245cf67e83b7b4bcccee804304e97cbe575345572b9506f |
| Scripts/NVIDIA/Settings-GitHub.ps1 | 13108 | 1e5bfa1fa88d9db3ec7255db78f1f973505a764bec7694befcafb7a900337063 |
| Scripts/Windows/Copilot-Off.ps1 | 1962 | c8868bf2fc7a8ea99018fd113caf1e08b87182482a4d8c3ef772a3b91a5a3186 |
| Scripts/Windows/Power-Plan.ps1 | 16651 | 4e2afa2805834b27ec3d19a02a3479e2cf08807666fb7d21f1993f9c6d1c39cc |
| Scripts/Windows/Services.ps1 | 29059 | 3913edf9c362c34b180a77817e3349ab6e3a8d910b7b0577ee1adc79d06f9181 |
| Scripts/Windows/Timer-Resolution.ps1 | 10532 | 6e27741fa54afdba7ace528f218b8cdcb7d93767da8c6856b747a977f7c18c3a |
| Scripts/Windows/Widgets.ps1 | 1459 | 23ee08ec83771922c513761beabf671198ac4f9728eb0c3eb190acd0721c6595 |

Ana NVIDIA Driver Updater ayni GPU bulma, NVIDIA katalog arama, indirme ve imza dogrulama mantigini kullanir. Kurucu bitene kadar beklemesi icin Start-Process satirina -Wait eklendi.


The guided DDU path uses NVIDIA-only cleanup flags in normal Windows mode; the standalone DDU Auto/Manual path keeps its original Safe Mode behavior.
