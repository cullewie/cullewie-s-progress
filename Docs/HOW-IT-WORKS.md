# Nasıl çalışır?

1. `IWR.ps1` sabitlenmiş dosyaları indirir.
2. Her dosyanın boyunu ve SHA-256 değerini manifest ile karşılaştırır. Bir değer uyuşmazsa devam etmez.
3. Dosyaları `ProgramData` içindeki sürüm klasörüne koyar.
4. `Launcher.ps1` tam otomatik kurulumu başlatır; menü yoktur.
5. Launcher her aracı sırayla ayrı bir PowerShell sürecinde çalıştırır.

SHA-256, dosyanın parmak izi gibi çalışır. Dosyanın içeriği değişirse değer de değişir.

## NVIDIA güncelleme aracı

Ana NVIDIA Driver Updater kaynaktaki haliyle korunur. Kaynak, daha büyük bir menüden alınmış `1 { ... }` bölümüdür. Launcher bu bölümü geçici bir `switch (1)` bloğuna koyarak çalıştırır; kaynak dosyanın içeriğini değiştirmez.

NVIDIA Settings aracı ayrı bir seçenektir; rehberli kurulum bunu çağırmaz.

## Tam otomatik kurulum

FR33THY WinSux gibi dört aşamada çalışır; UAC kapatılmaz.

1. **Normal mod (komut çalışınca):** Ekran kartının adı saklanır, DDU ve Defender hazırlanır, oturum açma şifresi seçeneği açılır. Bilgisayar Güvenli Mod'da yeniden başlar.
2. **Güvenli Mod:** DDU NVIDIA sürücüsünü kaldırır, Defender ayarları uygulanır. Güvenli Mod kapatılır ve bilgisayar yeniden başlar.
3. **Normal mod (oturum açınca kendiliğinden):** En yüksek yetkiyle çalışan bir zamanlanmış görev NVIDIA sürücüsünü, NVIDIA Settings ve NIP ayarlarını, P0 State'i, ardından Widgets, Copilot, güç planı, zamanlayıcı ve Tweaks araçlarını çalıştırır. Görev başlarken kendini siler. NVIDIA adımlarından biri başarısız olursa Windows adımları yine çalışır; başarısız adımlar en sonda listelenir.
4. **Güvenli Mod:** Services ayarları uygulanır, bilgisayar normal modda yeniden başlar.

Güvenli Mod'da Windows Hello PIN'i çalışmaz; her aşamada hesabın şifresiyle oturum açılır.

Sorun çıkarmaması için:

- BitLocker açıksa 1. aşamada askıya alınır; önyükleme ayarı değişince kurtarma anahtarı sorulmaz. Tweaks daha sonra BitLocker'ı kapatır.
- Windows Update'in DDU ile yeni sürücü arasında kendi NVIDIA sürücüsünü kurması engellenir.
- 3. aşama internet gelene kadar en fazla 5 dakika bekler.
- Kartta NVIDIA sürücüsü yoksa Windows kartı "Microsoft Basic Display Adapter" diye gösterir. Bu durumda kartın PCI kimliği `pci-ids.ucw.cz` listesinde aranır ve NVIDIA'nın kullandığı model adı bulunur.

## Rehberli NVIDIA kurulumu

Kurulu NVIDIA sürücüsü varsa DDU normal Windows modunda bir kez çalışır. Safe Mode açılmaz; DDU yeniden başlatma komutu vermez ve geri yükleme noktası oluşturmaz. DDU bittikten sonra aynı launcher oturumu NVIDIA paketinden yalnızca `Display.Driver` bileşenini kurar. NVIDIA App ve NVIDIA Control Panel kurulumu başlatılmaz. Ekran kartının model adı temizlikten önce saklanıp kurucuya aktarılır. İndirme akışı yüzdeyi saniyede birkaç kez günceller; PowerShell 5.1'in yavaş yerleşik ilerleme göstergesini kullanmaz.

## Sistem ayarları

Araçların geri alma ve varsayılan ayara dönme seçenekleri çıkarılmıştır.

IWR dosyaları indirir, doğrular ve tam otomatik kurulumu başlatır. Test için `CULLEWIE_MODE=guided` ortam değişkeniyle yalnızca DDU ve NVIDIA sürücüsü, yeniden başlatmadan çalıştırılabilir. Yönetici PowerShell penceresi gerekir. Kalıcı ExecutionPolicy ayarı değiştirilmez; alt PowerShell sürecine özel `Bypass` kullanılır.

Services Off, Windows ekran yakalama işlevlerinin kullanabilmesi için `CaptureService` hizmetini Disabled yerine Manual bırakır.
