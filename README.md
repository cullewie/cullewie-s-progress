# cullewie-s-progress

Format sonrası Windows'u tek komutla kendiliğinden kurar: NVIDIA sürücüsü, NVIDIA ayarları ve Windows ayarları.

## Başlat

Yönetici olarak açılmış PowerShell'e şu komutu yapıştır:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Menü yoktur, hiçbir şey sorulmaz. Komut dosyaları indirir, SHA-256 ile kontrol eder ve kurulumu başlatır.

## Ne yapar?

1. Güvenli Mod'da DDU ile NVIDIA sürücüsünü kaldırır ve Defender ayarlarını uygular.
2. Normal modda en yeni NVIDIA ekran sürücüsünü kurar (yalnızca `Display.Driver`; NVIDIA App kurulmaz), NVIDIA Settings ve NIP ayarlarını uygular, P0 State'i açar.
3. Widgets, Copilot, güç planı, zamanlayıcı ve Windows ayarlarını (Tweaks) uygular.
4. Hizmet ayarlarını Güvenli Mod'da uygular.

Bilgisayar dört kez kendiliğinden yeniden başlar. Her açılışta şifrenizle oturum açmanız yeterli; kurulum kaldığı yerden devam eder. NVIDIA kartı yoksa NVIDIA adımları atlanır. Geri alma ve geri yükleme noktası yoktur. Ayrıntılar `Docs/HOW-IT-WORKS.md` içinde.

Services Off, `CaptureService` hizmetini `Manual` bırakır; Snipping Tool çalışır. Wi-Fi (`WlanSvc`) ve olay günlüğü (`EventLog`) açık kalır.

## Dosyalar

`Scripts/` klasöründe 11 PowerShell aracı bulunur. `manifest.json`, indirilen dosyaların boyut ve SHA-256 değerlerini listeler. `Docs/PROVENANCE.md` kaynak dosyaların kimliğini kaydeder.
