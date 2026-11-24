# cullewie's-progress

Windows 11'i formatladıktan sonra bilgisayarı oyun için hazırlayan, tek komutla çalışan açık kaynak bir kurulum aracı.

Başlat menüsünde **PowerShell**'e sağ tıkla, **Yönetici olarak çalıştır**'ı seç ve şu komutu yapıştır:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Bir pencere açılır. **All-in**, **Xbox & Store**, **Only Store Mode** ya da hepsini geri almak için **Vanilla Mode**'u seç ve **Başlat**'a bas. Pencere her adımı ve sonucunu gösterir.

## All-in

Bilgisayarı oyun için en sade haline getirir:

- Önce bekleyen Windows güncellemelerini indirir ve kurar (sürücü, yeni Windows sürümü ve isteğe bağlı güncellemeler hariç). Yeniden başlatma gerekirse bilgisayar kendiliğinden yeniden başlar ve kurulum aynı modda devam eder (en fazla 3 tur).
- Eski ekran kartı sürücüsünü güvenli modda DDU ile siler, NVIDIA'nın ya da AMD'nin (Radeon RX 5000–9000) sitesinden en yenisini kurar. Sürücünün dijital imzası kontrol edilir.
- NVIDIA veya AMD ayarlarını yapar, monitörü en yüksek yenileme hızına (Hz) alır. Her şey bitince pencere Digital Vibrance ya da AMD'de Color Saturation değerini sorar.
- Gereksiz uygulamaları ve Windows hizmetlerini kapatır, Windows'u oyun için ayarlar.
- Microsoft Store kaldırılır. winget (App Installer) önce Windows'un kendi ilkesiyle kilitlenir, kurulumun sonunda da kaldırılır. Store / Xbox ve Vanilla modu winget'i geri kurar. Windows Update, Store'un kurulum hizmeti ve Teslim En İyileştirme (Delivery Optimization) kapatılır.
- Windows Update, Xbox ve oyun dışı bazı Windows özellikleri bu seçenekte çalışmaz. Xbox uygulaması, Gaming Services ve Game Bar kaldırılır (Vanilla Mode hepsini geri kurar, Store ve winget dahil).
- Kurulum sırasında hiçbir pencere (Görev Yöneticisi, Güç Seçenekleri) açılmaz; sonuçlar kurulum penceresinde ve kayıtta görünür.

Kurulum sırasında bilgisayar üç kez kendiliğinden yeniden başlar (bekleyen güncelleme varsa daha fazla). Her açılışta Windows'a giriş yapman yeterli; pencere kaldığı yerden devam eder.

**Yeniden başlatmadan çalıştırmak için** (güvenli mod, sürücü temizliği, Defender ayarları ve ekran sorusu atlanır; hizmetler bir sonraki yeniden başlatmada değişir):

```powershell
$env:CULLEWIE_MODE = 'live'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

## Xbox & Store / Only Store Mode

İkisi de All-in'in yaptığı her şeyi yapar, ama seçilen uygulamaların çalışması için gereken hizmetleri ve ayarları açık bırakır. Microsoft Store ve winget kalır (önceki bir All-in winget'i kilitlediyse kilit açılır). Eksik olan uygulamaları kurulum kendisi kurar. İkisinde de Windows Update açık kalır ama **yalnızca aylık güncellemeyi** alır; yeni Windows sürümü, sürücü ve önizleme güncellemeleri gelmez.

### Xbox & Store

Game Pass oynuyorsan, Xbox uygulamasını ya da Xbox kumandası kullanıyorsan bunu seç.

Microsoft Store, Xbox uygulaması, Gaming Services, Xbox oturumu ve bulut kayıtları, kumanda (kablolu, adaptör, Bluetooth), Xbox parti sohbeti ve çok oyunculu bağlantılar (IPv6, Teredo), GameInput ve Game Bar çalışır.

### Only Store Mode

Microsoft Store'dan uygulama indiriyorsan ama Xbox ve Game Pass kullanmıyorsan bunu seç.

Store'dan indirme, kurma ve güncelleme çalışır. Xbox uygulaması, Gaming Services ve Game Bar All-in'deki gibi kaldırılır; Xbox hizmetleri ve IPv6 kapalı kalır.

Pencere açmadan, terminalde çalıştırmak için:

Xbox & Store

```powershell
$env:CULLEWIE_APPS = 'xbox'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Only Store Mode

```powershell
$env:CULLEWIE_APPS = 'store'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

## Vanilla Mode

Aracın Windows'ta yaptığı değişiklikleri geri alır ve Windows'u normal davranışına döndürür. Pencerede **Vanilla Mode**'u seç ya da terminalde çalıştır. Bu komut da pencereyi açar ve Vanilla Mode'u kendiliğinden başlatır:

```powershell
$env:CULLEWIE_MODE = 'vanilla'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

- **Hizmetler:** Windows 11'in varsayılan ayarlarına döner.
- **Ağ ve politikalar:** IPv6 ve dosya paylaşımı yeniden açılır, aracın yazdığı politika ayarları silinir.
- **Defender ve güç:** Defender ayarları ve Windows'un güç planları geri gelir. Timer Resolution hizmeti kaldırılır, Sistem Geri Yükleme açılır.
- **Uygulamalar:** Kaldırılan uygulamalar ve Windows özellikleri geri kurulur.
- **Görünüm:** Kurulumdan önceki görünüm ayarların (tema, renk, görev çubuğu, Başlat menüsü) geri gelir.

**Geri gelmeyenler:**
- Ekran kartı sürücüsü ve GPU ayarları
- BitLocker şifrelemesi
- Artık hiçbir yerde sunulmayan uygulamalar (Solitaire, Haritalar, Skype gibi) ve Uzak Masaüstü Bağlantısı
- Akıllı Uygulama Denetimi ve Kurcalama Koruması

Ağ ayarları en son açılır ve bilgisayar hemen ardından kendiliğinden yeniden başlar. Microsoft Store, Xbox ve geri gelen uygulamalar, yeniden başladıktan sonra oturum açınca arka planda kurulur.

---

Sorun olursa GitHub'da bir *issue* aç ya da X'ten yaz: [@cullewie](https://x.com/cullewie). Lisans: [MIT](LICENSE).
