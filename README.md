# cullewie's-progress

Windows 11'i formatladıktan sonra bilgisayarı oyun için hazırlayan, tek komutla çalışan açık kaynak bir kurulum aracı. Yaptığı her şey bu depodaki dosyalarda yazılıdır.

Başlat menüsünde **PowerShell**'e sağ tıkla, **Yönetici olarak çalıştır**'ı seç ve şunu yapıştır:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Kurulumun başında üç seçenekten biri sorulur: **1 = All-in**, **2 = Only Store Mode**, **3 = Xbox & Store**. Hepsini geri almak için **Vanilla Mode** kullanılır.

FPS artışı ya da daha düşük gecikme garanti edilmez; sonuç donanıma ve oyuna göre değişir.

## All-in

Bilgisayarı oyun için en sade haline getirir:

- Eski ekran kartı sürücüsünü güvenli modda DDU ile siler, NVIDIA'nın ya da AMD'nin (Radeon RX 5000–9000) sitesinden en yenisini kurar. Sürücünün dijital imzası kontrol edilir.
- NVIDIA veya AMD ayarlarını yapar, monitörü en yüksek yenileme hızına (Hz) alır. Sonda Digital Vibrance (Dijital Canlılık) ya da AMD'de Color Saturation (Renk Doygunluğu) için bir değer sorar.
- Hazır gelen gereksiz uygulamaları, Widgets'ı ve Copilot'u kaldırır. Telemetriyi kapatır, Windows'u koyu temaya alır, güç planını en yüksek performansa ayarlar, Timer Resolution'ı 0,5 ms'ye ayarlar.
- Yaklaşık 200 Windows hizmetini kapatır. Kapatmadan önce açık kalacak hizmetlerin bunlara bağlı olup olmadığını kontrol eder.

Kurulum sırasında bilgisayar üç kez kendiliğinden yeniden başlar. Her açılışta Windows'a giriş yapman yeterli.

**Bu seçenekte çalışmayanlar:** Windows Update, Microsoft Store ve Xbox, yazıcı, Bluetooth, dosya ve yazıcı paylaşımı, IPv6, Başlat aramasında dosya içeriği, Windows bildirimleri. Sistem Geri Yükleme kapanır, BitLocker şifrelemesi kaldırılır. Windows Defender'ın gerçek zamanlı koruması açık kalır; SmartScreen ve bulut koruması kapanır.

**Yeniden başlatmadan çalıştırmak için** (güvenli mod, sürücü temizliği, Defender ayarları ve ekran sorusu atlanır; hizmetler bir sonraki yeniden başlatmada değişir):

```powershell
$env:CULLEWIE_MODE = 'live'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Sonuç şu dosyaya yazılır: `C:\ProgramData\User\Work\live-setup-*.log`

## Xbox & Store / Only Store Mode

İkisi de All-in'in yaptığı her şeyi yapar, ama seçilen uygulamaların çalışması için gereken hizmetleri ve ayarları açık bırakır. Eksik olan uygulamaları kurulum kendisi kurar. İkisinde de Windows Update açık kalır ama **yalnızca aylık güncellemeyi** alır; yeni Windows sürümü, sürücü ve önizleme güncellemeleri gelmez.

### Xbox & Store

Game Pass oynuyorsan, Xbox uygulamasını ya da Xbox kumandası kullanıyorsan bunu seç.

Microsoft Store, Xbox uygulaması, Gaming Services, Xbox oturumu ve bulut kayıtları, kumanda (kablolu, adaptör, Bluetooth), Xbox parti sohbeti ve çok oyunculu bağlantılar (IPv6, Teredo), GameInput ve Game Bar çalışır.

### Only Store Mode

Microsoft Store'dan uygulama indiriyorsan ama Xbox ve Game Pass kullanmıyorsan bunu seç.

Store'dan indirme, kurma ve güncelleme çalışır. Xbox hizmetleri, Game Bar ve IPv6 All-in'deki gibi kapalı kalır.

Soruyu atlamak için komutun başına `$env:CULLEWIE_APPS = 'xbox';` (Xbox & Store) ya da `$env:CULLEWIE_APPS = 'store';` (Only Store Mode) ekle.

## Vanilla Mode

Aracın Windows'ta yaptığı değişiklikleri geri alır ve Windows'u normal davranışına döndürür:

```powershell
$env:CULLEWIE_MODE = 'vanilla'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

- **Hizmetler:** Windows 11'in varsayılan ayarlarına döner.
- **Ağ ve politikalar:** IPv6 ve dosya paylaşımı yeniden açılır, aracın yazdığı politika ayarları silinir.
- **Defender ve güç:** Defender ayarları ve Windows'un güç planları geri gelir. Timer Resolution hizmeti kaldırılır, Sistem Geri Yükleme açılır.
- **Uygulamalar:** Microsoft Store ve Xbox uygulamaları kurulur.
- **Görünüm:** All-in, görünümü değiştirmeden önce senin o anki tema, renk, görsel efekt, ölçekleme, görev çubuğu, Başlat menüsü ve Gezgin ayarlarını kaydeder. Vanilla Mode bunları geri yükler. Bu kayıt sadece aracın bu sürümüyle yapılan All-in kurulumlarında vardır; kayıt yoksa görünüm olduğu gibi kalır.

**Geri gelmeyenler:**
- Ekran kartı sürücüsü ve GPU ayarları
- BitLocker şifrelemesi
- Kaldırılan uygulamalar ve Windows özellikleri (Store'dan kurulabilir)
- Akıllı Uygulama Denetimi ve Kurcalama Koruması

Ağ ayarları açılırken internet birkaç saniye kesilir. Bitince bilgisayarı yeniden başlat.

---

Sorun olursa GitHub'da bir *issue* aç ya da X'ten yaz: [@cullewie](https://x.com/cullewie). Lisans: [MIT](LICENSE).
