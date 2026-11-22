# cullewie's-progress

Windows'u formatladıktan sonra bilgisayarı oyuna hazırlayan açık kaynak bir kurulum aracı. Tek komutla çalışır; sonda yalnızca iki soru sorar.

Açık kaynaktır: yaptığı her şey bu depodaki dosyalarda yazılıdır ve herkes okuyabilir.

## Kurulum

1. Başlat menüsünde PowerShell'i bul, sağ tıkla ve Yönetici olarak çalıştır'ı seç.
2. Şu komutu yapıştır ve Enter'a bas:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

## Ne yapar?

- NVIDIA veya AMD Radeon (RX 5000 ve üstü) ekran kartı sürücüsünü temizler ve en yenisini kurar.
- Ekran kartı ve Windows ayarlarını oyun için düzenler: Game Bar kapanır, gizlilik ve bildirim ayarları sıkılaşır, cihaz ve ağ kartı güç tasarrufu kapanır, ağ yalnızca IPv4 kullanır, tema siyah olur.
- Tam ekran ölçekleme açılsın mı ve dijital canlılık (AMD'de doygunluk) ne olsun diye sorar.
- Gereksiz Windows hizmetlerini ve özelliklerini kapatır. Ağ, Wi-Fi, güvenlik duvarı, aygıt kurulumu, oturum açma ve Microsoft Store'un ihtiyaç duyduğu hizmetlere dokunmaz.
- Yalnızca adı listede yazılı olan hazır uygulamaları kaldırır (Bing Haberler, Solitaire, Teams, Clipchamp vb.). Senin kurduğun uygulamalar, Microsoft Store, App Installer ve Xbox kalır.

Bilgisayar kurulum sırasında dört kez kendiliğinden yeniden başlar. Her açılışta şifrenle giriş yapman yeterli; kurulum kaldığı yerden devam eder.

Eski bir sürüm Wi-Fi'yi, Store'u ya da uygulamalarda oturum açmayı bozduysa, Yönetici PowerShell'de `Scripts\Windows\Services-Restore.ps1` dosyasını çalıştırıp bilgisayarı yeniden başlat.

İndirilen her dosyanın bozulmadığı ve değiştirilmediği SHA-256 ile kontrol edilir.
