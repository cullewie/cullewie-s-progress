# Nasıl çalışır?

1. `IWR.ps1` sabitlenmiş dosyaları indirir.
2. Her dosyanın boyunu ve SHA-256 değerini manifest ile karşılaştırır. Bir değer uyuşmazsa devam etmez.
3. Dosyaları `ProgramData` içindeki sürüm klasörüne koyar.
4. `Launcher.ps1` menüsünü açar.
5. Launcher yalnızca seçtiğin aracı ayrı bir PowerShell penceresinde çalıştırır.

SHA-256, dosyanın parmak izi gibi çalışır. Dosyanın içeriği değişirse değer de değişir.

## NVIDIA güncelleme aracı

Ana NVIDIA Driver Updater kaynaktaki haliyle korunur. Kaynak, daha büyük bir menüden alınmış `1 { ... }` bölümüdür. Launcher bu bölümü geçici bir `switch (1)` bloğuna koyarak çalıştırır; kaynak dosyanın içeriğini değiştirmez.

NVIDIA Settings aracı GitHub üzerinden kurulur.

## Rehberli NVIDIA kurulumu

Launcher kurulu NVIDIA görüntü sürücüsünü denetler. Sürücü yoksa DDU kullanılmadan kurulum yapılır. Sürücü varsa DDU normal Windows modunda NVIDIA sürücüsü ve NVIDIA bileşenlerini temizler. Windows iki kez yeniden başlatılır; her açılışta işlem kaldığı yerden sürer. İkinci temizliğin ardından NVIDIA Driver Updater çalışır ve NVIDIA Settings GitHub üzerinden kurulur. Bu akış Safe Mode kullanmaz ve AMD/Intel sürücülerini temizlemez. DDU üreticisinin normal mod yönergesi temizliği yeniden başlatma ile iki kez yapmayı önerir.

## Sistem ayarları

Menü, Windows ayarlarını kendiliğinden değiştirmez. Bir araç seçildiğinde kendi akışını başlatır. Araçların sunduğu geri alma ve varsayılan ayara dönme seçenekleri menüden çıkarılmıştır.

IWR yalnızca dosyaları indirir, doğrular ve launcher'ı açar. Yönetici PowerShell penceresi gerekir. Kalıcı ExecutionPolicy ayarı değiştirilmez; alt PowerShell sürecine özel `Bypass` kullanılır.
