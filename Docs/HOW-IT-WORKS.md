# Nasıl çalışır?

1. `IWR.ps1` sabitlenmiş dosyaları indirir.
2. Her dosyanın boyunu ve SHA-256 değerini manifest ile karşılaştırır. Bir değer uyuşmazsa devam etmez.
3. Dosyaları `ProgramData` içindeki sürüm klasörüne koyar.
4. `Launcher.ps1` menüsünü açar.
5. Launcher yalnızca seçtiğin aracı ayrı bir PowerShell penceresinde çalıştırır.

SHA-256, dosyanın parmak izi gibi çalışır. Dosyanın içeriği değişirse değer de değişir.

## NVIDIA güncelleme aracı

Ana NVIDIA Driver Updater kaynaktaki haliyle korunur. Kaynak, daha büyük bir menüden alınmış `1 { ... }` bölümüdür. Launcher bu bölümü geçici bir `switch (1)` bloğuna koyarak çalıştırır; kaynak dosyanın içeriğini değiştirmez.

NVIDIA Settings aracı ayrı bir seçenektir; rehberli kurulum bunu çağırmaz.

## Rehberli NVIDIA kurulumu

Kurulu NVIDIA sürücüsü varsa DDU normal Windows modunda bir kez çalışır. Safe Mode açılmaz; DDU yeniden başlatma komutu vermez ve geri yükleme noktası oluşturmaz. DDU bittikten sonra aynı launcher oturumu NVIDIA paketinden yalnızca `Display.Driver` bileşenini kurar. NVIDIA App ve NVIDIA Control Panel kurulumu başlatılmaz. Ekran kartının model adı temizlikten önce saklanıp kurucuya aktarılır. İndirme akışı yüzdeyi saniyede birkaç kez günceller; PowerShell 5.1'in yavaş yerleşik ilerleme göstergesini kullanmaz.

## Sistem ayarları

Menü, Windows ayarlarını kendiliğinden değiştirmez. Bir araç seçildiğinde kendi akışını başlatır. Araçların sunduğu geri alma ve varsayılan ayara dönme seçenekleri menüden çıkarılmıştır.

IWR yalnızca dosyaları indirir, doğrular ve launcher'ı açar. Yönetici PowerShell penceresi gerekir. Kalıcı ExecutionPolicy ayarı değiştirilmez; alt PowerShell sürecine özel `Bypass` kullanılır.

Services Off, Windows ekran yakalama işlevlerinin kullanabilmesi için `CaptureService` hizmetini Disabled yerine Manual bırakır.
