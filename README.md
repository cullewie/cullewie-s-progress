# cullewie's-progress

Windows'u formatladıktan sonra bilgisayarı oyuna hazırlayan açık kaynak bir kurulum aracı. Tek komutla çalışır ve hiçbir şey sormaz.

Açık kaynaktır: yaptığı her şey bu depodaki dosyalarda yazılıdır ve herkes okuyabilir.

## Kurulum

1. Başlat menüsünde PowerShell'i bul, sağ tıkla ve Yönetici olarak çalıştır'ı seç.
2. Şu komutu yapıştır ve Enter'a bas:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

## Ne yapar?

- NVIDIA ekran kartı sürücüsünü temizler ve en yenisini kurar.
- Ekran kartı ve Windows ayarlarını oyun için düzenler.
- Gereksiz Windows hizmetlerini ve özelliklerini kapatır.

Bilgisayar kurulum sırasında dört kez kendiliğinden yeniden başlar. Her açılışta şifrenle giriş yapman yeterli; kurulum kaldığı yerden devam eder. Yapılan değişiklikler geri alınamaz.

İndirilen her dosyanın bozulmadığı ve değiştirilmediği SHA-256 ile kontrol edilir.
