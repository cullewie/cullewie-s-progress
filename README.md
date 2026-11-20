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

Ana NVIDIA Driver Updater üretim sürümü olarak korunur. NVIDIA Settings GitHub üzerinden kurulur.

Rehberli NVIDIA kurulumu kurulu surucuyu bir kez DDU ile temizler. DDU normal Windows modunda calisir; bilgisayari yeniden baslatmaz ve geri yukleme noktasi olusturmaz. DDU bitince launcher NVIDIA surucusunu ve GitHub NVIDIA Settings uygulamasini kurar.

## Davranış

Menüde geri alma veya varsayılan ayara döndürme seçeneği yoktur. Seçilen araç kendi işini yapar. Bazı araçların işi bitirmek için Windows'u yeniden başlatması gerekir.

IWR yalnızca dosyaları indirir, SHA-256 değerlerini kontrol eder ve menüyü açar. Windows ayarlarını kendi başına değiştirmez.

## Dosyalar

`Scripts/` klasöründe 11 PowerShell aracı bulunur. `manifest.json`, indirilen dosyaların boyut ve SHA-256 değerlerini listeler. `Docs/PROVENANCE.md` kaynak dosyaların kimliğini kaydeder.
