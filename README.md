# cullewie-s-progress

Windows sürücü ve ayar araçlarını tek menüde toplar.

## Başlat

Yönetici olarak açılmış PowerShell'e şu komutu yapıştır:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Komut, araç dosyalarını indirir, dosyaları kontrol eder ve menüyü açar. Bir araç, menüden seçilene kadar çalışmaz.

## Menüde neler var?

- **Sürücüler:** NVIDIA güncelleme aracı, çoklu ekran kartı sürücü indiricisi, DDU ve sade sürücü kurucusu.
- **NVIDIA:** GitHub üzerinden kurulan NVIDIA Settings ve Digital Vibrance aracı.
- **Windows:** Widgets, hizmetler, güç planı, Copilot ve zamanlayıcı araçları.

Ana NVIDIA Driver Updater üretim sürümü olarak korunur. Rehberli NVIDIA kurulumu yalnızca ekran sürücüsünü kurar; NVIDIA App ve NVIDIA Control Panel için ayrı kurulum başlatmaz.

Rehberli NVIDIA kurulumu kurulu sürücüyü bir kez DDU ile temizler. DDU normal Windows modunda çalışır; bilgisayarı yeniden başlatmaz ve geri yükleme noktası oluşturmaz. DDU bitince NVIDIA kurulum paketi yalnızca `Display.Driver` bileşenini kurar. Yeniden başlatma gerekse bile toolkit bilgisayarı otomatik yeniden başlatmaz. Büyük sürücü indirmeleri yüzde göstergesi kullanır ve PowerShell 5.1'in yavaş yerleşik indirme göstergesini devre dışı bırakır.

Services Off seçeneği `CaptureService` hizmetini `Manual` durumda bırakır; böylece Snipping Tool gerektiğinde bu hizmeti başlatabilir. Wi-Fi (`WlanSvc`) ve olay günlüğü (`EventLog`) açık kalır.

## Davranış

Menüde geri alma veya varsayılan ayara döndürme seçeneği yoktur. Seçilen araç kendi işini yapar. Bazı araçların işi bitirmek için Windows'u yeniden başlatması gerekir.

IWR yalnızca dosyaları indirir, SHA-256 değerlerini kontrol eder ve menüyü açar. Windows ayarlarını kendi başına değiştirmez.

## Dosyalar

`Scripts/` klasöründe 11 PowerShell aracı bulunur. `manifest.json`, indirilen dosyaların boyut ve SHA-256 değerlerini listeler. `Docs/PROVENANCE.md` kaynak dosyaların kimliğini kaydeder.
