# cullewie's-progress

Windows 11'i formatladıktan sonra bilgisayarı oyun için hazırlayan, tek komutla çalışan açık kaynak bir kurulum aracı.

Başlat menüsünde **PowerShell**'e sağ tıkla, **Yönetici olarak çalıştır**'ı seç ve aşağıdaki seçeneklerden birinin komutunu yapıştır: **All-in**, **Xbox & Store**, **Only Store Mode** ya da hepsini geri almak için **Vanilla Mode**.

## All-in

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Başta gelen soruda **1 = All-in**'i seç. Bilgisayarı oyun için en sade haline getirir:

- Eski ekran kartı sürücüsünü güvenli modda DDU ile siler, NVIDIA'nın ya da AMD'nin (Radeon RX 5000–9000) sitesinden en yenisini kurar. Sürücünün dijital imzası kontrol edilir.
- NVIDIA veya AMD ayarlarını yapar, monitörü en yüksek yenileme hızına (Hz) alır. Sonda Digital Vibrance ya da AMD'de Color Saturation için bir değer sorar.
- Gereksiz uygulamaları ve Windows hizmetlerini kapatır, Windows'u oyun için ayarlar.
- Windows Update, Microsoft Store, Xbox ve oyun dışı bazı Windows özellikleri bu seçenekte çalışmaz.

Kurulum sırasında bilgisayar üç kez kendiliğinden yeniden başlar. Her açılışta Windows'a giriş yapman yeterli.

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

Soruyu atlamak için:

Xbox & Store

```powershell
$env:CULLEWIE_APPS = 'xbox'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Only Store Mode

```powershell
$env:CULLEWIE_APPS = 'store'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

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
