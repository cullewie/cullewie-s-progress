# Kaynak ve dosya karmaları

Kaynak paketteki 12 PowerShell dosyası SHA-256 ile doğrulanmıştır. Aşağıdaki değerler bu sürümdeki dosyaları tanımlar. Her dosyanın boyu bayt cinsindendir.

| Dosya | Bayt | SHA-256 |
|---|---:|---|
| Scripts/Drivers/DDU/DDU.ps1 | 10520 | 564657374be33107ae7c69e61825cf8b2b7eb6ff668d40654908524a4d3ce9b5 |
| Scripts/Drivers/Debloated-Installer/Driver-Installer.ps1 | 37285 | adf2e6121a6fa2171e7b917c59a58af575c68366342cf173f7e542c8dd1b2d24 |
| Scripts/Drivers/Multi-GPU/Driver-Downloader.ps1 | 3533 | 25890bc50f2abb4a1a6d80f5c626a295abcd7fd3e08c82396cad3e123f320987 |
| Scripts/Drivers/NVIDIA/NVIDIA-Driver-Updater.ps1 | 5406 | 955de18efb9af0d06c14565156dbe426ba2c2f78d64b149d82d65855b88ddded |
| Scripts/NVIDIA/Digital-Vibrance.ps1 | 10400 | 97bbc19629baa336c8ffafdd598c82a9419d039c2ede0ff46ff1750b63008bba |
| Scripts/NVIDIA/Settings-GitHub.ps1 | 13108 | 1e5bfa1fa88d9db3ec7255db78f1f973505a764bec7694befcafb7a900337063 |
| Scripts/NVIDIA/Settings-WinGet.ps1 | 12331 | d552d93222d5ddc3a4511887c4efaa00373e2591ac5c44015905439d701f84ee |
| Scripts/Windows/Copilot-Off.ps1 | 1962 | c8868bf2fc7a8ea99018fd113caf1e08b87182482a4d8c3ef772a3b91a5a3186 |
| Scripts/Windows/Power-Plan.ps1 | 16651 | 4e2afa2805834b27ec3d19a02a3479e2cf08807666fb7d21f1993f9c6d1c39cc |
| Scripts/Windows/Services.ps1 | 29059 | 3913edf9c362c34b180a77817e3349ab6e3a8d910b7b0577ee1adc79d06f9181 |
| Scripts/Windows/Timer-Resolution.ps1 | 10532 | 6e27741fa54afdba7ace528f218b8cdcb7d93767da8c6856b747a977f7c18c3a |
| Scripts/Windows/Widgets.ps1 | 1459 | 23ee08ec83771922c513761beabf671198ac4f9728eb0c3eb190acd0721c6595 |

Ana NVIDIA Driver Updater dosyası bu değişiklikte aynen korunmuştur. Diğer listelenen dosyalarda yalnızca kullanıcıya sunulan varsayılan/geri alma seçenekleri kaldırılmıştır. `manifest.json`, indirilen tüm dosyaların boyunu ve karmasını ayrıca kontrol eder.
