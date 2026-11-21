# cullewie-s-progress

Windows sürücü ve ayar araçlarını tek menüde toplar.

## Başlat

Yönetici olarak açılmış PowerShell'e şu komutu yapıştır:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Komut, araç dosyalarını indirir, dosyaları kontrol eder ve menüyü açar. Bir araç, menüden seçilene kadar çalışmaz.

## Menüde neler var?

- **Tam otomatik kurulum (1):** Güvenli Mod'da DDU ile NVIDIA sürücüsünü kaldırır ve Defender ayarlarını uygular. Normal modda yeni ekran sürücüsünü kurar, NVIDIA Settings ve NIP ayarlarını uygular, P0 State'i açar, ardından Widgets, Copilot, güç planı, zamanlayıcı ve Windows ayarlarını (Tweaks) çalıştırır. En sonda hizmet ayarlarını Güvenli Mod'da uygular. Bilgisayar dört kez kendiliğinden yeniden başlar; her açılışta şifrenizle oturum açmanız yeterli, kurulum kaldığı yerden devam eder. Ayrıntılar `Docs/HOW-IT-WORKS.md` içinde.
- **Sürücüler:** NVIDIA güncelleme aracı, çoklu ekran kartı sürücü indiricisi, DDU ve sade sürücü kurucusu.
- **NVIDIA:** GitHub üzerinden kurulan NVIDIA Settings, P0 State ve Digital Vibrance aracı.
- **Windows:** Widgets, hizmetler, güç planı, Copilot ve zamanlayıcı araçları, Windows ayarları (Tweaks), Defender.

Ana NVIDIA Driver Updater üretim sürümü olarak korunur. Rehberli NVIDIA kurulumu yalnızca ekran sürücüsünü kurar; NVIDIA App ve NVIDIA Control Panel için ayrı kurulum başlatmaz.

Rehberli NVIDIA kurulumu kurulu sürücüyü bir kez DDU ile temizler. DDU normal Windows modunda çalışır; bilgisayarı yeniden başlatmaz ve geri yükleme noktası oluşturmaz. DDU bitince NVIDIA kurulum paketi yalnızca `Display.Driver` bileşenini kurar. Yeniden başlatma gerekse bile toolkit bilgisayarı otomatik yeniden başlatmaz. Büyük sürücü indirmeleri yüzde göstergesi kullanır ve PowerShell 5.1'in yavaş yerleşik indirme göstergesini devre dışı bırakır.

Services Off seçeneği `CaptureService` hizmetini `Manual` durumda bırakır; böylece Snipping Tool gerektiğinde bu hizmeti başlatabilir. Wi-Fi (`WlanSvc`) ve olay günlüğü (`EventLog`) açık kalır.

## Davranış

Menüde geri alma veya varsayılan ayara döndürme seçeneği yoktur. Seçilen araç kendi işini yapar. Bazı araçların işi bitirmek için Windows'u yeniden başlatması gerekir.

IWR yalnızca dosyaları indirir, SHA-256 değerlerini kontrol eder ve menüyü açar. Windows ayarlarını kendi başına değiştirmez.

## Dosyalar

`Scripts/` klasöründe 14 PowerShell aracı bulunur. `manifest.json`, indirilen dosyaların boyut ve SHA-256 değerlerini listeler. `Docs/PROVENANCE.md` kaynak dosyaların kimliğini kaydeder.
