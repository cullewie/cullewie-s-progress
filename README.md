# cullewie's-progress

Windows 11'i formatladıktan sonra bilgisayarı oyun için hazırlayan, tek komutla çalışan açık kaynak bir kurulum aracı.

## Bu proje nedir?

Yeni kurulmuş bir Windows'ta oyun oynamadan önce genelde aynı işler elle yapılır: ekran kartı sürücüsü temiz kurulur, gereksiz uygulamalar silinir, arka planda çalışan Windows parçaları kapatılır, ekran ayarları yapılır. Bu araç bu işlerin hepsini sırayla ve kendisi yapar.

Açık kaynaktır (MIT lisansı). Yaptığı her şey bu depodaki PowerShell dosyalarında yazılıdır. Çalıştırmadan önce okuyabilirsin. Dosyaların nerede olduğu ["Dosya yapısı"](#dosya-yapısı) bölümünde anlatılıyor.

> **Ne vaat etmez:** Bu araç FPS artışı ya da daha düşük gecikme **garanti etmez**. Değişikliklerin etkisi donanıma, oyuna ve sürücüye göre değişir; bazı bilgisayarlarda hiçbir fark olmayabilir. Araç bir dizi ayarı uygular. Bu ayarların senin bilgisayarında işe yarayıp yaramadığını kendin ölçmelisin.

**Birkaç terim:**

| Terim | Anlamı |
|---|---|
| **FPS** | Bilgisayarın bir saniyede çizdiği görüntü (kare) sayısı. |
| **Frametime** | Tek bir karenin hazırlanması için geçen süre. Ortalama FPS yüksek olsa bile kareler düzensiz gelirse oyun takılıyormuş gibi görünür; bu yüzden sürelerin tutarlı olması önemlidir. |
| **Input latency (giriş gecikmesi)** | Fareye tıklamanla bunun ekranda görünmesi arasındaki süre. |
| **Refresh Rate (Hz)** | Monitörün görüntüyü saniyede kaç kez yenilediği. 144 Hz, saniyede 144 yenileme demektir. |
| **Sürücü** | Windows'un ekran kartıyla konuşmasını sağlayan yazılım. |
| **Hizmet (servis)** | Windows'ta arka planda çalışan küçük programlar. Örneğin yazıcı hizmeti, yazdırmayı yönetir. |

## Ne yapar?

Kısaca:

1. Eski ekran kartı sürücüsünü tamamen siler, üreticinin sitesinden en yenisini kurar.
2. NVIDIA veya AMD ayarlarını yapar, monitörü desteklediği en yüksek yenileme hızına alır.
3. Hazır gelen gereksiz uygulamaları, telemetriyi (Microsoft'a giden kullanım verileri), Widgets'ı ve Copilot'u kaldırır.
4. Oyunla ilgili Windows ayarlarını değiştirir, güç planını en yüksek performansa alır.
5. Yaklaşık 200 Windows hizmetini kapatır.
6. İstersen Microsoft Store ve Xbox / Game Pass'i çalışır halde bırakır.

Bunun bir bedeli var: bazı Windows özellikleri çalışmaz. Kurmadan önce ["Kurmadan önce bilmen gerekenler"](#kurmadan-önce-bilmen-gerekenler) bölümünü mutlaka oku.

## Kurulum

Gerekenler: Windows 11 (sürüm 22000 veya üstü), 64 bit, internet bağlantısı ve yönetici hesabı.

1. Başlat menüsünde **PowerShell** yaz, çıkan sonuca sağ tıkla ve **Yönetici olarak çalıştır**'ı seç.
2. Şu komutu kopyala, PowerShell penceresine yapıştır ve **Enter**'a bas:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

3. Gelen soruyu cevapla (aşağıda anlatılıyor) ve bilgisayarı kendi haline bırak. Arada üç kez kendiliğinden yeniden başlar. Her açılışta Windows'a normal şekilde giriş yap; kurulum kaldığı yerden devam eder.

Bu komut, depodaki `IWR.ps1` dosyasını indirip çalıştırır. `IWR.ps1` de geri kalan her dosyayı indirir ve bozulmadığını kontrol eder (["Güvenlik"](#güvenlik-ve-doğrulama) bölümü).

## Kurulum nasıl ilerler?

Kurulum üç aşamadan oluşur. Bazı işler Windows normal açıkken yapılamaz; bu yüzden araç bilgisayarı bir kez **güvenli moda** (Windows'un yalnızca en temel parçalarla açıldığı mod) alır.

| Aşama | Nerede | Ne olur |
|---|---|---|
| **1. Hazırlık** | Normal Windows | Bekleyen güncellemeyi kontrol eder, Store/Xbox sorusunu sorar, ekran kartının adını kaydeder, sonraki aşamaları hazırlar, güvenli modda yeniden başlatır. |
| **2. Temizlik** | Güvenli mod | Eski sürücüyü siler (DDU), Windows Defender ayarlarını uygular, normal şekilde yeniden başlatır. |
| **3. Kurulum ve ayarlar** | Normal Windows | Sürücüyü ve ayarları kurar, Windows ayarlarını yapar, Digital Vibrance sorusunu sorar, hizmetleri kapatır, son kez yeniden başlatır. |

**1. aşamada ayrıca:**

- **Bekleyen güncelleme kontrolü.** Windows bir güncellemeyi bitirmek için yeniden başlatma bekliyorsa kurulum başlamaz ve önce bir kez yeniden başlatmanı ister. Bekleyen bir güncelleme güvenli modda uygulanmaya çalışılırsa başarısız olur ve Windows "değişiklikler geri alınıyor" döngüsüne girer.
- **Windows Update sürücü engeli.** Eski sürücü silindikten sonra Windows Update'in araya girip kendi sürücüsünü kurmasını engeller. Bu engel 3. aşamada sürücü kurulunca kaldırılır. "Cihaz sürücülerini otomatik indir" ayarı ise kapalı kalır.
- **BitLocker.** Açıksa duraklatılır. Yoksa açılış ayarları değiştiğinde Windows kurtarma anahtarı ister. (3. aşamada BitLocker tamamen kapatılır, ["Kurmadan önce bilmen gerekenler"](#kurmadan-önce-bilmen-gerekenler).)
- 1. aşamada bir şey hata verirse araç yaptığı hazırlıkları geri alır ve durur.

**Sorulan sorular:** Başta bir (Store/Xbox), sonda bir (Digital Vibrance). Bir adım hata verirse, devam etmeden önce bir de onay ister.

## Bilgisayarda neler değişir?

### Ekran kartı sürücüsü

Desteklenen kartlar:
- **NVIDIA:** NVIDIA'nın sürücü sitesinde modeli bulunan kartlar (GeForce ve diğerleri). Model bulunamazsa sürücü adımı hata verir.
- **AMD:** Radeon **RX 5000, 6000, 7000 ve 9000** serisi ayrı ekran kartları. Dahili Radeon grafikler ve daha eski kartlar atlanır.

- **DDU ile temizlik.** DDU (Display Driver Uninstaller), mevcut ekran kartı sürücüsünü dosyaları ve ayarlarıyla birlikte siler, böylece yeni sürücü temiz kurulur. Güvenli modda çalışır.
  - NVIDIA'da PhysX, GeForce Experience, NVIDIA Broadcast ve Control Panel kalıntıları da silinir.
  - AMD'de eski sürücü, yalnızca yenisi bulunabildiyse silinir. Bulunamazsa mevcut sürücü kalır.
- **Yeni sürücü.** Sürücü NVIDIA'nın ya da AMD'nin kendi sitesinden indirilir ve kurulmadan önce **dijital imzası** kontrol edilir. İmza "NVIDIA Corporation" ya da "Advanced Micro Devices" adına değilse kurulmaz.
- **NVIDIA:**
  - Yalnızca sürücünün kendisi kurulur (`Display.Driver`); NVIDIA App ve NVIDIA Control Panel kurulmaz.
  - Windows'un Control Panel'i Store'dan kendi kendine indirmesi de engellenir.
  - Aynı sürüm zaten kuruluysa indirme atlanır.
- **AMD:** AMD Software (Adrenalin) sürücüsü kurulur. Sürüm kontrolü yoktur; her çalıştırmada yeniden kurulur.

### NVIDIA ayarları

NVIDIA Profile Inspector (NVIDIA'nın gizli ayarlarını da açan bir araç) ile tüm oyunlara uygulanan bir profile **30 ayar** yazılır. Öne çıkanlar:

| Ayar | Değer | Açıklama |
|---|---|---|
| Vertical Sync (V-Sync) | Kapalı (zorla) | Kareleri monitörün yenilemesiyle eşlemek için bekletmez. Ekranda yırtılma görülebilir. |
| G-SYNC | Kapalı | Değişken yenileme hızı kullanılmaz. |
| Low Latency Mode | Kapalı | NVIDIA'nın sürücü tarafındaki gecikme modu kullanılmaz. |
| Max Pre-Rendered Frames | Uygulamaya bırakılır | Oyun kendi ayarını kullanır. |
| Power Management Mode | Maksimum performans | Kart güç tasarrufuna geçmez. |
| Texture Filtering – Quality | Yüksek performans | Doku filtrelemede kalite yerine hız seçilir. |
| Preferred Refresh Rate | En yüksek | Monitörün en yüksek yenileme hızı kullanılır. |
| Frame Rate Limiter | Kapalı | Sürücü FPS sınırı koymaz. |
| Shader Cache | Sınırsız | Derlenen gölgelendiriciler (shader) için disk sınırı yok. |
| Threaded Optimization | Açık | Sürücü işini birden çok işlemci çekirdeğine dağıtır. |

Ayrıca:
- **P0 durumu.** P0, NVIDIA kartın en yüksek performans durumudur. Kart boştayken bile bu durumda kalır; bu yüzden boşta daha fazla güç çeker ve daha sıcak çalışabilir.
- **MSI modu** (kartın işlemciyle haberleşme yöntemi) ve **HDCP kapatma** Windows ayarları adımında yapılır (aşağıda).

### AMD ayarları

AMD Software (Adrenalin) ayarları yalnızca AMD ekran kartlarına yazılır:
- Otomatik güncelleme, hata bildirme aracı, kayıt kısayol tuşları, oyun içi kaplama (overlay), sistem tepsisi simgesi, tarayıcı içeriği, bildirimler ve animasyonlar kapanır.
- Kurulum sihirbazı ve sözleşme ekranları "görüldü" olarak işaretlenir.

### Monitör ve yenileme hızı

Yeni kurulan sürücü monitörü çoğu zaman 60 Hz'de başlatır. Araç, monitörün desteklediği en yüksek yenileme hızını seçer. Örneğin 240 Hz bir monitör 60 Hz'de kalmaz.

### Ekran ayarları ve Digital Vibrance (Dijital Canlılık)

Kurulumun son adımı:
- **Tam ekran ölçekleme.** Ekran kartının ölçeklemesi sorulmadan açılır. 4:3 gibi düşük çözünürlükler tüm ekrana yayılır (siyah kenar kalmaz). Ekrana bununla ilgili bir not yazılır.
- **Renk ayarı.** Tek soru sorulur:
  - **NVIDIA:** Digital Vibrance (Dijital Canlılık) yüzde kaç olsun? 50 varsayılan, 100 en yüksek.
  - **AMD:** Color Saturation (Renk Doygunluğu) yüzde kaç olsun? 100 varsayılan, 200 en yüksek.
  - Boş bırakırsan değişmez.
- NVIDIA bu değeri yeniden başlatınca unuttuğu için, varsayılandan farklı bir değer seçersen her oturum açılışında yeniden uygulayan bir zamanlanmış görev kurulur.

### Güç planı

- High Performance planından kopyalanan **"cullewie powerplan"** adlı bir plan oluşturulur ve etkinleştirilir. High Performance planı olmayan dizüstülerde Balanced'dan kopyalanır. Diğer güç planları silinir.
- Ekran ve disk kapanmaz, uyku ve hazırda bekletme kapalıdır, hızlı başlatma kapalıdır. Windows'un uygulamaları yavaşlatarak güç tasarrufu yapması (power throttling) kapanır.
- Güç menüsünde **Kilitle** ve **Uyku** seçenekleri gizlenir.

### Timer Resolution (0,5 ms)

Windows, zamanı belirli aralıklarla sayar; bu aralık normalde 15,6 ms'dir ve programlar daha kısa bir aralık isteyebilir. Araç, `Set Timer Resolution Service` adlı küçük bir arka plan hizmeti kurar. Bu hizmet, aralığı bilgisayarın desteklediği en kısa değere ayarlar; bu çoğu bilgisayarda **0,5 ms**'dir. Ayar, `GlobalTimerResolutionRequests` ile tüm sisteme uygulanır.

- Bu, Windows'un zamanlama adımlarını küçültür. FPS'i ya da gecikmeyi kendi başına iyileştireceği **garanti değildir**. İşlemcinin daha sık uyanmasına yol açtığı için, özellikle dizüstü bilgisayarlarda güç tüketimini artırabilir.
- Görev Yöneticisi'nde "Timer Resolution 0.5 ms (cullewie)" adıyla görünür.
- Hizmet, kaynak koddan bilgisayarında derlenir. Yeni bir indirme yapılmaz.

### Windows ayarları

**Gizlilik ve öneriler**
- Telemetri, reklam kimliği, etkinlik geçmişi, kişiselleştirilmiş öneriler ve "tüketici özellikleri" (önerilen uygulamaların kendiliğinden kurulması) kapanır.
- Telefon bağlantısı ve "kaldığın yerden devam et" kapanır. Uygulamaların konum, kişiler, takvim, e-posta, sohbet, telefon araması ve arama geçmişi, hesap bilgisi, bildirim okuma ve radyo (Bluetooth/Wi-Fi düğmesi) izinleri kapatılır.

**Oyun**

| Ayar | Ne yapar |
|---|---|
| Oyun Modu | Açılır. Windows, oyun açıkken arka plan işlerini azaltır. |
| Game DVR, Game Bar | Kapanır. Arka planda oyun kaydı yapılmaz. |
| HAGS | Açılır. Hardware-Accelerated GPU Scheduling (donanım hızlandırmalı GPU zamanlaması): ekran kartının iş sırasını işlemci yerine kartın kendisi yönetir. Etkisi karta ve oyuna göre değişir. |
| Tam ekran ayarları | Windows'un tam ekran oyunlara uyguladığı uyumluluk davranışları değiştirilir. |
| Pencereli oyunlar | Değişken yenileme hızı optimizasyonu kapanır, pencereli oyunlar için daha yeni sunum yöntemi açılır. |
| Oyun önceliği | Windows'un multimedya zamanlayıcısında oyunlara daha yüksek işlemci ve GPU önceliği verilir, ağ kısıtlaması kaldırılır. Ön plandaki programa daha fazla işlemci zamanı ayrılır (`Win32PrioritySeparation`). |

**Fare ve klavye**
- Fare ivmesi kapanır: imleç, elinin hareketini hızdan bağımsız olarak birebir izler.
- **Alt+Shift** ve **Ctrl+Shift** ile klavye dili değiştirme kısayolları kapanır.

**Ağ**
- **Nagle algoritması** kapanır: küçük ağ paketleri birleştirilmeden hemen gönderilir.
- Yalnızca IPv4 kullanılır. IPv6 ve diğer bağlamalar ağ kartlarından kaldırılır (["Kurmadan önce bilmen gerekenler"](#kurmadan-önce-bilmen-gerekenler)).
- Ağ kartlarının güç tasarrufu ve ağdan uyandırma (Wake-on-LAN) kapanır.
- Delivery Optimization yalnızca HTTP kullanır: güncellemeler başka bilgisayarlarla paylaşılmaz.

**Cihazlar ve donanım**
- USB, HID ve PCI cihazlarının güç tasarrufu ve uyandırma özelliği kapanır. Bu yüzden **klavye ve fare bilgisayarı uykudan uyandıramaz.**
- Ekran kartı **MSI modu**na alınır (Message Signaled Interrupts: kartın işlemciye haber verme yöntemi).
- **HDCP** kapanır (NVIDIA kartlarda, aşağıya bak).
- **Disk yazma önbelleği boşaltma kapanır.** Diske yazılacak veriler daha uzun süre bellekte bekleyebilir; elektrik aniden kesilirse veri kaybı riski artar.
- **Bellek sıkıştırma** kapanır.
- Kesme yönlendirme (interrupt steering) ayarı değiştirilir.

**Görünüm ve kullanım**
- Koyu tema, klasik sağ tık menüsü, dosya uzantıları görünür. Başlat menüsü liste görünümünde açılır.
- Duvar kâğıdın ve görev çubuğunun sağ köşesindeki "masaüstünü göster" düğmesi yerinde kalır.
- **Ekran ölçekleme %100'e sabitlenir.** Yüksek çözünürlüklü küçük ekranlarda (4K, dizüstü) yazılar çok küçük görünebilir; Ayarlar'dan elle değiştirebilirsin.
- **Tüm Windows bildirimleri (toast) kapanır.** Defender uyarıları, Windows Update ve uygulama davetleri açılır pencere olarak gelmez.
- Ses cihazlarında "Geliştirmeler" sekmesi görünür hale gelir. Uygulamaların ses kısma (ducking) ve açılış sesi kapanır.

**Bakım ve depolama**
- **Sistem Geri Yükleme** kapanır.
- **Otomatik Bakım** ve zamanlanmış **disk optimizasyonu** (SSD'lerde TRIM) kapanır.
- Ayrılmış depolama (Reserved Storage) kapatılır.
- Yalnızca C: sürücüsündeki geçici dosyalar silinir; USB belleklere ve diğer disklere dokunulmaz.
- **Visual C++ çalışma dosyaları** (2015 ve sonrası, x64 ve x86) kurulur; birçok oyunun açılması için gereklidir. Eski DirectX paketi kurulmaz: Windows 11'de DirectX 12 vardır, eski dosyalara ihtiyaç duyan oyunlar onları kendileri kurar.

**Microsoft Edge**
- Edge silinmez, çünkü Başlat menüsündeki arama kutusu Edge'in WebView2 bileşeniyle çizilir.
- Edge'in güncelleme hizmetleri kapanır, donanım hızlandırması kapatılır, arka planda çalışması ve öneri pencereleri kapanır.

**Uygulama izinleri**
- Uygulamaların Belgeler, İndirilenler, Resimler, Müzik ve Videolar klasörlerine erişimi kapatılır. Bu, Store uygulamalarını (örneğin Fotoğraflar) etkiler. Masaüstü programlar etkilenmez.
- Passkey (geçiş anahtarı) izinleri kapatılır.
- Arka plan uygulamaları kapatılır (Store/Xbox seçilirse açık kalır).

### Uygulamalar

**Kaldırılanlar** (yalnızca adı listede yazılı olanlar):

- **Uygulamalar:** Bing Haberler, Hava Durumu, Finans ve Spor; Yardım Al; İpuçları; Office Hub; Solitaire; Kişiler; Power Automate; To Do; Alarmlar; Geri Bildirim Merkezi; Haritalar; Ses Kaydedici; Groove/Medya Oynatıcı ve Filmler; Telefon Bağlantısı; Outlook ve Posta/Takvim; Teams; Clipchamp; Cortana; Copilot; Dev Home; Hızlı Yardım; Microsoft Family; Mixed Reality Portal; Skype; Mesajlaşma; 3D Viewer ve 3D Builder; OneNote; Cüzdan; Cihazlar arası deneyim paketi. Ayrıca Widgets ve Game Bar kaldırılır.
- **İsteğe bağlı Windows özellikleri:** Adım Kaydedici, Hızlı Yardım, Internet Explorer, Matematik Tanıma, WordPad, OneSync, Faks ve Tarama, Yazdırma Yönetimi konsolu, **Windows Hello yüz tanıma**.
- **Eski Windows bileşenleri:** Internet Explorer, **SMB1**, PowerShell 2.0, Work Folders, XPS hizmetleri, **Recall**.
- **Programlar:** OneDrive, Uzak Masaüstü Bağlantısı, braille sürücüsü, Microsoft GameInput, Update Health Tools ve KB5001716 (Windows Update onarım bileşenleri).

**Kalanlar:** Senin kurduğun her uygulama; Microsoft Store, App Installer (winget), Xbox uygulaması, Gaming Services, WSL ve Hyper-V. Ama hizmetler kapalı olduğu için Store ve Xbox, Store/Xbox seçeneği seçilmezse çalışmaz.

Zaten kaldırılmış bir uygulama hata sayılmaz.

### Windows hizmetleri

Listedeki **248 hizmetten 200'ü kapatılır**, diğerleri "manuel" ya da "otomatik" başlatmaya ayarlanır.

**Dokunulmayanlar:** Ağ ve Wi-Fi, güvenlik duvarı (BFE, Windows Firewall), oturum açma ve hesaplar, parola kasası, ses, aygıt kurulumu, Microsoft Store kurulum ve lisans hizmetleri, Windows Modül Yükleyicisi (TrustedInstaller).

**Bağımlılık kontrolü.** Hizmetler birbirine bağlıdır. Örneğin Wi-Fi hizmeti, bağlantı yöneticisi hizmetine ihtiyaç duyar. Araç, değişiklik yapmadan önce açık kalacak her hizmetin, kapatılacak bir hizmete bağlı olup olmadığını kontrol eder:
- Kendiliğinden başlayan bir hizmet veya sürücü kapalı bir hizmete bağlıysa **hiçbir şeyi değiştirmeden durur**.
- İstek üzerine başlayan bir hizmet bağlıysa uyarı yazar.

Hizmetler önce Windows'un en yetkili hesabıyla (TrustedInstaller), sonra yönetici olarak yazılır. Sonra her değer tek tek geri okunur, uygulanmayan varsa listelenir (`C:\ProgramData\Cullewie\Work\services-not-applied.txt`).

Kapatılan hizmetlerin ne anlama geldiği bir sonraki bölümde.

## Kurmadan önce bilmen gerekenler

Bu araç, bazı Windows özelliklerini bilerek kapatır. Kurmadan önce bunlara bak:

| Özellik | Durum | Neden / sonuç |
|---|---|---|
| **Windows Update** | Kapalı | Güncelleme gelmez. Store/Xbox seçilirse yalnızca aylık güncelleme alır ([aşağıda](#microsoft-store-xbox-ve-game-pass)). |
| **Microsoft Store, Xbox** | Çalışmaz | Store/Xbox seçeneği seçilmezse. |
| **Yazdırma** | Çalışmaz | Yazıcı hizmeti (Print Spooler) kapalı. |
| **Tarayıcı ve bazı kameralar** | Çalışmaz | Windows görüntü alma hizmetleri (WIA) kapalı. |
| **Dosya ve yazıcı paylaşımı** | Çalışmaz | SMB istemci/sunucu bağlamaları kaldırılır, sunucu hizmeti ve ağ keşfi kapalı. Ağdaki diğer bilgisayarlar ve NAS görünmez. |
| **IPv6** | Kapalı | Ağ kartlarından kaldırılır, yalnızca IPv4 kullanılır. Yalnızca IPv6 veren internet bağlantılarında internet çalışmayabilir. |
| **Bluetooth** | Çalışmaz | Bluetooth hizmeti kapalı (Xbox seçeneğinde açılır). |
| **Windows'un kendi VPN'i, mobil sıcak nokta** | Çalışmaz | Uzaktan erişim ve internet paylaşımı hizmetleri kapalı. Kendi sürücüsünü kuran VPN programları ayrıca denenmeli. |
| **Windows Hello** | Yüz tanıma kaldırılır, parmak izi çalışmaz | Biyometrik hizmet kapalı. PIN ve şifre çalışır. |
| **Konum, sensörler, dokunmatik klavye/kalem** | Kapalı | İlgili hizmetler kapalı. |
| **Bildirimler** | Kapalı | Bildirim hizmeti ve tüm açılır bildirimler kapalı. |
| **Başlat'taki arama** | Dosya içeriği aranmaz | Arama dizini (Windows Search) kapalı. Uygulama ve dosya adları yine bulunur. |
| **HDCP** | Kapalı (NVIDIA) | Kopya korumalı yayınlar (örneğin Netflix'te 4K) oynatılmayabilir. |
| **Sistem Geri Yükleme** | Kapalı | Geri yükleme noktası oluşturulmaz. Bir şey bozulursa geri dönüş noktası olmaz. |
| **BitLocker** | Kapatılır | Disk şifrelemesi çözülür. Bilgisayar çalınırsa disk okunabilir. |
| **Uyku, kilitleme** | Menüden gizlenir | Güç menüsünde görünmez; klavye ve fare bilgisayarı uyandırmaz. |
| **Hata raporlama, sorun gidericiler, Dosya Geçmişi** | Kapalı | İlgili hizmetler kapalı. |

**Windows Defender**

| Açık kalan | Kapatılan |
|---|---|
| Gerçek zamanlı virüs koruması | SmartScreen (bilinmeyen dosya, uygulama ve site uyarıları; Edge ve Store uygulamaları dahil) |
| Güvenlik duvarı | Bulut tabanlı koruma ve otomatik örnek gönderme |
| | Akıllı Uygulama Denetimi (bir kez kapatılınca genelde Windows yeniden kurulmadan açılamaz) |
| | İstenmeyebilecek uygulama (PUA) koruması, kimlik avı koruması |
| | Dev Drive koruması, Defender ve güvenlik duvarı bildirimleri |
| | Zamanlanmış Defender taramaları ve bakım görevleri |
| | Kurcalama Koruması (Windows bazı durumlarda bunu yeniden açabilir) |

Defender ayarları yalnızca güvenli modda yazılabildiği için 2. aşamada uygulanır.

## Microsoft Store, Xbox ve Game Pass

Kurulumun başında şu soru sorulur:

```
Microsoft Store / Xbox kullaniyor musunuz? 1 = Hayir, 2 = Sadece Microsoft Store, 3 = Xbox ve Game Pass (Store dahil)
```

| Seçim | Ne çalışır |
|---|---|
| **1 = Hayır** | Yukarıda anlatılan her şey. Store ve Xbox çalışmaz. |
| **2 = Sadece Microsoft Store** | Store'dan indirme, kurma ve güncelleme. Store'un otomatik güncellemesi ve arka plan uygulamaları açık kalır. |
| **3 = Xbox ve Game Pass** | 2'deki her şey, artı Xbox uygulaması, Gaming Services, Xbox oturum açma ve bulut kayıtları, kumanda (kablolu, adaptör ve Bluetooth), Xbox ağ hizmetleri, GameInput ve Game Bar. |

2 veya 3 seçilince:
- **Hizmetler.** Gereken hizmetler Windows'un varsayılan ayarlarına yazılır. Bilgisayar daha önce bu araçla kurulduysa, kapatılmış hizmetler ve ayarlar da geri açılır.
- **Eksik uygulamalar** kurulum sırasında, yeniden başlatma beklemeden kurulur: Microsoft Store; 3'te ayrıca Xbox, Gaming Services, Xbox Identity Provider, Game Bar ve GameInput.
- **Xbox ağı (3'te).** IPv6 açık kalır. Teredo (Xbox parti sohbeti ve çok oyunculu bağlantılar için kullanılan IPv6 tüneli), ev ağlarında da çalışması için "enterprise client" moduna alınır.
- **Windows Update** açık kalır ama **yalnızca aylık güncellemeyi** alır:
  - Yeni Windows sürümü, sürücü güncellemesi ve önizleme güncellemeleri gelmez.
  - Windows 11'de "yalnızca güvenlik" diye ayrı bir güncelleme yoktur; güvenlik düzeltmeleri bu aylık pakette gelir.
  - Windows sürümü kurulumdaki sürüme sabitlenir. O sürümün desteği bitince aylık güncellemeler de durur; o zaman Windows'u elle yeni sürüme yükseltip kurulumu bir kez daha çalıştır.
  - Windows 11 Home'da sürüm sabitleme her zaman işlemeyebilir.

Soruyu atlamak için komutun başına seçimini ekle:

```powershell
$env:CULLEWIE_APPS = 'xbox'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

(`'store'` da yazılabilir.) Bu değişken aynı PowerShell penceresi açık kaldığı sürece geçerlidir ve sonraki kurulumlar da soruyu sormadan bunu kullanır.

## Yeniden başlatmadan çalıştırma (live mod)

Zaten kurulu bir bilgisayarı yeniden başlatmadan, güvenli moda geçmeden ve soru sormadan güncel ayarlara getirmek için:

```powershell
$env:CULLEWIE_MODE = 'live'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Bu modda:
- **Atlananlar:** sürücü temizliği (DDU, güvenli mod gerektirir), Windows Defender ayarları (güvenli mod dışında yazılamaz) ve ekran soruları (tam ekran ölçekleme, Digital Vibrance).
- **Yine çalışanlar:** sürücü kurulumu, NVIDIA/AMD ayarları, güç planı, Timer Resolution, Windows ayarları ve hizmetler.
- **Store/Xbox sorusu sorulmaz.** Seçim yalnızca `CULLEWIE_APPS` ile yapılır, yoksa "1 = Hayır" sayılır. İkisi birlikte: `$env:CULLEWIE_MODE = 'live'; $env:CULLEWIE_APPS = 'xbox'; iwr ...`
- **Hizmet ayarları** yazılır ama **bir sonraki yeniden başlatmada** devreye girer.
- **Sonuç.** Her adımın sonucu ekranda özetlenir ve şu dosyaya kaydedilir:

```text
C:\ProgramData\User\Work\live-setup-*.log
```

## Windows varsayılanlarına dönüş (vanilla)

Bu aracın Windows'ta yaptığı değişiklikleri geri almak için:

```powershell
$env:CULLEWIE_MODE = 'vanilla'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Soru sormaz, güvenli moda geçmez. IPv6 ve dosya paylaşımı yeniden açılırken ağ kartı yeniden başlar; internet birkaç saniye kesilir. Bitince bilgisayarı **yeniden başlatman** gerekir.

**Geri gelenler:**
- **Hizmetler:** Aracın dokunduğu her hizmet Windows 11'deki varsayılan başlatma türüne döner. Bazı hizmetler Windows'ta varsayılan olarak otomatik başlar (ses, ağ, yazdırma, arama, Windows Update düzenleyicisi gibi), bazıları varsayılan olarak kapalıdır (örneğin Remote Registry). Diğerleri "manuel" olur; Windows onları gerektiğinde kendisi başlatır. Önceki kurulumların, bilgisayarda olmayan hizmetler için bıraktığı boş kayıtlar silinir.
- **Ağ:** IPv6, dosya ve yazıcı paylaşımı, QoS ve ağ keşfi yeniden açılır. Teredo ve IPv4 tercihi Windows varsayılanına döner.
- **Politikalar:** Aracın yazdığı politika değerleri silinir. Bunlar telemetri, Copilot, Widgets, Game DVR, Windows Update kısıtları, Sistem Geri Yükleme kapatma gibi ayarlardır. Silinecek değerler betiklerin kendisinden okunur. UAC ve oturum açma ile ilgili Windows değerlerine dokunulmaz.
- **Windows Defender:** SmartScreen, bulut koruması, örnek gönderme, PUA ve kimlik avı koruması, Akıllı Uygulama Denetimi durum değerleri ve bildirim ayarları Windows varsayılanına döner. Zamanlanmış Defender taramaları yeniden açılır. (Akıllı Uygulama Denetimi bir kez kapatıldıysa Windows yeniden kurulmadan açılmayabilir.)
- **Güç:** Windows'un varsayılan güç planları geri gelir. Hazırda bekletme ve hızlı başlatma açılır, güç menüsünde Kilitle ve Uyku yeniden görünür.
- **Diğer:** Timer Resolution hizmeti kaldırılır. Sistem Geri Yükleme açılır. Store otomatik güncellemesi ve arka plan uygulamaları açılır. Windows Update yeniden sürücü indirebilir.
- **Uygulamalar:** Microsoft Store ve Xbox uygulamaları kurulur (3 = Xbox ve Game Pass seçeneğindeki gibi).

**Geri gelmeyenler (bilerek):**
- **Ekran kartı sürücüsü ve GPU ayarları:** NVIDIA/AMD sürücüsü, NVIDIA profili, P0 ve Digital Vibrance olduğu gibi kalır.
- **BitLocker:** Şifresi çözülen disk kendiliğinden yeniden şifrelenmez. İstersen Ayarlar'dan aç.
- **Defender'ın iki ayarı:** Kurcalama Koruması ve Dev Drive için eşzamansız tarama ayarı Defender tarafından korunur ve betikle geri alınamaz. Kurcalama Korumasını Windows Güvenliği > Virüs ve tehdit koruması ayarlarından açabilirsin.
- **Kaldırılan diğer uygulamalar ve özellikler:** Hava Durumu, Haritalar, Solitaire, Outlook, Teams gibi kaldırılmış uygulamalar ve Windows özellikleri (WordPad, Hello yüz tanıma vb.) geri gelmez. Uygulamalar Store'dan tek tek kurulabilir.
- **Kişisel ayarlar:** Koyu tema, %100 ölçekleme, Gezgin ve Başlat menüsü ayarları, fare ivmesi, Nagle gibi politika olmayan ayarlar kalır. Bunların "varsayılanı" bilgisayara göre değiştiği için tahminle değiştirilmez.

Değiştirmeden önce mevcut hizmet değerleri ve politikalar `C:\ProgramData\Cullewie\Work\vanilla-*-backup*.reg` dosyalarına yedeklenir. Ne yapıldığı `C:\ProgramData\Cullewie\Work\vanilla-*.log` dosyasına yazılır.

## Bir şey bozulursa

- **Eski bir sürümün bozduğu hizmetler.** Bu aracın eski bir sürümü Wi-Fi'yi, güvenlik duvarını, Microsoft Store'u ya da uygulamalarda oturum açmayı bozduysa, Yönetici PowerShell'de şunu çalıştırıp bilgisayarı yeniden başlat:

  ```powershell
  .\Scripts\Windows\Services-Restore.ps1
  ```

  Bu betik ağ, güvenlik duvarı, aygıt, Microsoft Store kurulumu, hesap ve masaüstü hizmetlerini Windows 11 varsayılanlarına döndürür. Değiştirmeden önce mevcut ayarları `C:\ProgramData\Cullewie\Work\services-restore-*-backup.reg` dosyasına yedekler.
- **Hizmet kontrolü durdurduysa.** Kurulum "Services: stopped, nothing was changed" der ve durursa, hiçbir hizmet değiştirilmemiştir. Ekranda hangi hizmetin hangisine bağlı olduğu yazar. Önce `Services-Restore.ps1`'i çalıştırıp yeniden başlat, sonra kurulumu tekrar dene.
- **Her şeyi geri almak için** ["Windows varsayılanlarına dönüş"](#windows-varsayılanlarına-dönüş-vanilla) bölümündeki vanilla modunu kullan.
- **Sistem Geri Yükleme kapalı olduğu için** geri yükleme noktası yoktur. Kurmadan önce önemli dosyalarını yedekle.

## Dosya yapısı

Her betik, işini yaptığı şeyin klasöründe durur:

```text
IWR.ps1                  tek satırlık komutun indirdiği başlangıç dosyası: her dosyayı indirip doğrular, Launcher'ı başlatır
Launcher.ps1             kurulumun sırasını yöneten ana dosya (tam kurulum ve live mod)
manifest.json            her dosyanın boyutu ve SHA-256 parmak izi
Scripts/
├── GPU/                 ekran kartı
│   ├── NVIDIA/
│   │   ├── Driver.ps1   en yeni NVIDIA sürücüsünü bulur, indirir, imzasını kontrol eder, kurar
│   │   └── Settings.ps1 NVIDIA profili (30 ayar), P0 durumu, en yüksek yenileme hızı
│   ├── AMD/
│   │   ├── Driver.ps1   en yeni AMD sürücüsünü (RX 5000–9000) bulur, indirir, imzasını kontrol eder, kurar
│   │   └── Settings.ps1 AMD Software ayarları, en yüksek yenileme hızı
│   ├── DDU.ps1          eski sürücüyü güvenli modda siler (iki marka için ortak)
│   ├── Refresh-Rate.ps1 monitörü en yüksek yenileme hızına alır (NVIDIA ve AMD Settings de çağırır)
│   └── Display-Options.ps1  tam ekran ölçekleme ve Digital Vibrance / Color Saturation (son adım)
└── Windows/
    ├── Tweaks.ps1       uygulama kaldırma, Widgets, Copilot ve Windows ayarları
    ├── Power-Plan.ps1   güç planı
    ├── Timer-Resolution.ps1  0,5 ms Timer Resolution hizmeti
    ├── Defender.ps1     Windows Defender ayarları (güvenli modda)
    ├── Store-Xbox.ps1   Store / Xbox seçilince eksik uygulamaları kurar
    ├── Services.ps1     hizmetleri kapatır (bağımlılık kontrolüyle)
    ├── Vanilla.ps1      Windows değişikliklerini geri alır (vanilla modu)
    └── Services-Restore.ps1  eski bir sürümün bozduğu hizmetleri onarır
```

Kurulum sırasında oluşan çalışma dosyaları ve kayıtlar `C:\ProgramData\Cullewie\Work\` klasöründe tutulur. Live mod kaydı ise `C:\ProgramData\User\Work\` klasöründedir.

## Güvenlik ve doğrulama

- **Sabitlenmiş sürüm.** `IWR.ps1`, kodu belirli bir GitHub commit'inden (`$PayloadCommit`) indirir, `main` dalının o anki halinden değil. Depoda sonradan yapılan bir değişiklik, IWR güncellenmeden kurulumlara gelmez.
- **SHA-256 kontrolü.** `manifest.json` indirilir ve parmak izi IWR'nin içinde yazan değerle (`$ExpectedManifestSha256`) karşılaştırılır. Sonra her dosyanın boyutu ve SHA-256 parmak izi manifest ile karşılaştırılır. Tek bir bayt bile farklıysa kurulum başlamaz.
- **Klasör izinleri.** İndirilen dosyalar yalnızca yöneticilerin ve sistemin yazabildiği bir klasöre (`C:\ProgramData\Cullewie`) konur. Böylece yönetici olmayan bir program, kurulum yönetici olarak çalışmadan önce dosyaları değiştiremez.
- **Yardımcı araçlar.** 7-Zip, DDU ve NVIDIA Profile Inspector, bu deponun GitHub sürümlerinden indirilir ve SHA-256 parmak izleriyle doğrulanır.
- **Sürücüler.** Üretici, sürücüler için sabit bir parmak izi yayınlamadığı için sürücüler **dijital imzayla** (Authenticode) doğrulanır: imza geçerli olmalı ve NVIDIA Corporation ya da Advanced Micro Devices adına olmalıdır.

## Açık kaynak ve katkı

Bu proje [MIT lisansı](LICENSE) ile yayınlanır: kodu okuyabilir, kopyalayabilir ve değiştirebilirsin.

Bir hata bulursan ya da bir öneri yapmak istersen GitHub'da bir *issue* aç veya değişikliğini bir *pull request* olarak gönder. Değişiklik yaparken:
- Dosyalar bayt bayt doğrulandığı için satır sonları korunmalıdır (`.gitattributes`: `* -text`).
- Bir dosya değişince `manifest.json`'daki boyut ve SHA-256 değeri, ardından `IWR.ps1`'deki sabitlenmiş commit ve manifest parmak izi güncellenmelidir.
