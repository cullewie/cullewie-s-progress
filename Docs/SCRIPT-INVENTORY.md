# Araç listesi

Bu projede 11 PowerShell aracı vardır.

## Sürücüler

- `Scripts/Drivers/NVIDIA/NVIDIA-Driver-Updater.ps1` — Ana NVIDIA sürücü güncelleyici. Üretim tabanı budur.
- `Scripts/Drivers/Multi-GPU/Driver-Downloader.ps1` — NVIDIA, AMD ve Intel sürücü indiricisi.
- `Scripts/Drivers/DDU/DDU.ps1` - DDU otomatik/el ile araci. Rehberli NVIDIA akisi normal Windows modunda temizler; yeniden baslatma veya geri yukleme noktasi olusturmaz.
- `Scripts/Drivers/Debloated-Installer/Driver-Installer.ps1` — Sade sürücü kurucusu.

## NVIDIA

- `Scripts/NVIDIA/Settings-GitHub.ps1` — GitHub dağıtımlı NVIDIA Settings aracı.
- `Scripts/NVIDIA/Digital-Vibrance.ps1` — NVIDIA Digital Vibrance ayarı.

NVIDIA Settings aracı GitHub üzerinden kurulur.

## Windows

- `Scripts/Windows/Widgets.ps1` — Widgets'ı kapatır.
- `Scripts/Windows/Services.ps1` — Hizmet ayarlarını değiştirir.
- `Scripts/Windows/Power-Plan.ps1` — Güç planı ayarlarını değiştirir.
- `Scripts/Windows/Copilot-Off.ps1` — Copilot'ı kapatır ve kaldırma adımlarını çalıştırır.
- `Scripts/Windows/Timer-Resolution.ps1` — Zamanlayıcı çözünürlüğü hizmetini kurar.

Kaynak betiklerdeki geri alma ve varsayılan ayara döndürme menüleri kaldırılmıştır. Teknik çalışma ayrıntıları için `HOW-IT-WORKS.md` dosyasına bak.
