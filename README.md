# cullewie's-progress

Windows'u formatladıktan sonra bilgisayarı oyuna hazırlayan açık kaynak bir kurulum aracı. Tek komutla çalışır; en sonda tek bir soru sorar.

Açık kaynaktır: yaptığı her şey bu depodaki dosyalarda yazılıdır ve herkes okuyabilir.

## Kurulum

1. Başlat menüsünde PowerShell'i bul, sağ tıkla ve Yönetici olarak çalıştır'ı seç.
2. Şu komutu yapıştır ve Enter'a bas:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

## Ne yapar?

Kısaca: eski ekran kartı sürücüsünü söküp en yenisini takar, oyunu yavaşlatan ya da rahatsız eden Windows parçalarını kapatır, bilgisayarı en yüksek performansta çalışacak şekilde ayarlar.

Kurulum üç aşamada ilerler. Bilgisayar arada üç kez kendiliğinden yeniden başlar; her açılışta şifrenle giriş yapman yeterli, kurulum kaldığı yerden devam eder.

### 1. Hazırlık (normal Windows)

- **Önce bekleyen güncellemeye bakar.** Windows bir güncellemeyi bitirmek için yeniden başlatma bekliyorsa kurulum başlamaz ve önce bilgisayarı bir kez yeniden başlatmanı ister. (Bekleyen güncelleme güvenli modda uygulanmaya çalışılırsa başarısız olur ve Windows "değişiklikler geri alınıyor" döngüsüne girer.)
- **Ekran kartının adını not eder**, eski sürücü silinince de hangi kart olduğunu bilsin diye.
- **Windows Update'in araya girip kendi sürücüsünü kurmasını engeller.** Güncellemelerdeki sürücü engeli kurulum bitince kalkar; "cihaz sürücülerini Windows Update'ten otomatik indir" ayarı ise kapalı kalır.
- **BitLocker açıksa duraklatır**, böylece yeniden başlatmalarda kurtarma anahtarı sorulmaz.

### 2. Temizlik (güvenli mod)

- **Eski ekran kartı sürücüsünü iz bırakmadan siler.** (Display Driver Uninstaller; NVIDIA kartlarda ve AMD RX 5000–9000'de. Yeni sürücü bulunamazsa eski AMD sürücüsü silinmez.)
- **Windows Defender ayarlarını uygular** (ayrıntısı aşağıda, "Bilmen gerekenler" bölümünde). Bu ayarlar yalnızca güvenli modda yazılabiliyor.

### 3. Kurulum ve ayarlar (normal Windows)

- **En yeni ekran kartı sürücüsünü kurar.** Sürücüyü NVIDIA'nın ya da AMD'nin kendi sitesinden indirir ve dijital imzasını kontrol eder; imza üreticiye ait değilse kurmaz. NVIDIA'da yalnızca sürücünün kendisi kurulur: NVIDIA App ve Control Panel kurulmaz. NVIDIA'da aynı sürüm zaten kuruluysa indirmeyi atlar; AMD'de sürücü her seferinde yeniden kurulur.
- **NVIDIA ayarlarını yapar.** NVIDIA Profile Inspector ile tüm oyunlara 30 ayar uygular: V-Sync kapalı, Low Latency Mode kapalı, güç modu "en yüksek performans", doku filtreleme "yüksek performans", G-SYNC kapalı. Kartı hep en yüksek hızında tutar (P0 durumu). (Ekran kartının MSI modu Windows ayarları adımında açılır.)
- **Ekranı en yüksek yenileme hızına alır.** Örneğin monitörün 240 Hz destekliyorsa 60 Hz'de kalmaz.
- **Widget'ları ve Copilot'u kapatır.**
- **Güç planını en yüksek performansa ayarlar.** Ekran hiç kapanmaz, hazırda bekletme kapalıdır.
- **Zamanlayıcıyı 0,5 ms'ye ayarlar.** Windows zamanı normalde 15,6 ms'lik adımlarla sayar; bu adımı 0,5 ms'ye indiren küçük bir hizmet kurar, böylece kare zamanlaması daha düzgün olur. Görev Yöneticisi'nde "Timer Resolution 0.5 ms (cullewie)" adıyla görünür.
- **Hazır gelen gereksiz uygulamaları kaldırır.** Yalnızca adı listede yazılı olanları siler (Bing Haberler, Solitaire, Teams, Clipchamp, Telefon Bağlantısı ve benzerleri). Senin kurduğun uygulamalar, Microsoft Store, App Installer, Xbox uygulaması ve Gaming Services kalır. Zaten kaldırılmış bir uygulama hata sayılmaz.
- **Windows ayarlarını oyun için düzenler:**
  - Gizlilik ve telemetri: Microsoft'a giden kullanım verileri, reklam kimliği, öneriler ve etkinlik geçmişi kapanır.
  - Oyun: Game Bar ve oyun kaydı (Game DVR) kapanır, Oyun Modu açılır, donanım hızlandırmalı GPU zamanlaması (HAGS) açılır.
  - Fare ivmesi kapanır, fare elinin hareketini birebir izler.
  - Ağ: yalnızca IPv4 kullanılır, Nagle algoritması kapanır, ağ kartının güç tasarrufu kapanır.
  - Cihazlar: USB ve diğer cihazların güç tasarrufu kapanır, uykuya geçip gecikme yaratmazlar.
  - Görünüm: koyu tema, klasik sağ tık menüsü, dosya uzantıları görünür. Duvar kâğıdın ve görev çubuğunun sağ köşesindeki "masaüstünü göster" düğmesi yerinde kalır.
  - Telefon bağlantısı ve "kaldığın yerden devam et" özelliği kapanır.
  - Visual C++ çalışma dosyalarını kurar (birçok oyun ve programın açılması için gerekli). Eski DirectX paketi kurulmaz: Windows 11'de DirectX 12 zaten var, eski DirectX dosyalarına ihtiyaç duyan oyunlar onları kendileri kurar.
  - Yalnızca C: sürücüsündeki geçici dosyaları siler; takılı USB belleklere dokunmaz.
- **Ekran ayarları (son adım):** Tam ekran ölçekleme sorulmadan açılır ve ekrana not düşülür; 4:3 gibi düşük çözünürlükler tüm ekrana yayılır. Ardından tek soru gelir: **dijital canlılık** (AMD'de doygunluk) yüzde kaç olsun? NVIDIA bu değeri yeniden başlatınca unuttuğu için her oturum açılışında yeniden uygulanır.
- **Gereksiz Windows hizmetlerini kapatır** (yaklaşık 200 hizmet). Ağ, Wi-Fi, güvenlik duvarı, aygıt kurulumu, oturum açma, parola kasası ve Microsoft Store'un ihtiyaç duyduğu hizmetlere dokunmaz. Başlamadan önce açık kalacak her hizmetin, kapatılacak bir hizmete bağlı olup olmadığını kontrol eder; bağlıysa hiçbir şeyi değiştirmeden durur.
- **Son kez normal yeniden başlatır.** Kurulum tamam.

## Dosyalar nerede?

Her betik, işini yaptığı şeyin klasöründe durur:

```
IWR.ps1                  tek satırlık komutun indirdiği başlangıç dosyası: her dosyayı indirip doğrular, Launcher'ı başlatır
Launcher.ps1             kurulumun sırasını yöneten ana dosya
manifest.json            her dosyanın SHA-256 parmak izi
Scripts/
├── NVIDIA/
│   ├── Driver.ps1       en yeni NVIDIA sürücüsünü bulur, indirir, imzasını kontrol eder, kurar
│   └── Settings.ps1     NVIDIA profili (30 ayar), P0 durumu, en yüksek yenileme hızı
├── AMD/
│   ├── Driver.ps1       en yeni AMD sürücüsünü (RX 5000–9000) bulur, indirir, imzasını kontrol eder, kurar
│   └── Settings.ps1     AMD Software ayarları, en yüksek yenileme hızı
├── GPU/                 iki marka için ortak
│   ├── DDU.ps1          eski sürücüyü güvenli modda siler
│   ├── Refresh-Rate.ps1 ekranı en yüksek yenileme hızına alır (NVIDIA ve AMD Settings çağırır)
│   └── Display-Options.ps1  tam ekran ölçekleme ve dijital canlılık (son adım)
└── Windows/
    ├── Tweaks.ps1       gereksiz uygulamalar, Widgets, Copilot ve bütün Windows ayarları
    ├── Power-Plan.ps1   güç planı
    ├── Timer-Resolution.ps1  0,5 ms zamanlayıcı hizmeti
    ├── Defender.ps1     Windows Defender ayarları (güvenli modda)
    ├── Services.ps1     gereksiz hizmetleri kapatır
    └── Services-Restore.ps1  eski bir sürümün bozduğu hizmetleri onarır
```

## Bilmen gerekenler

Bu araç bilgisayarı hızlandırmak için bazı Windows özelliklerinden vazgeçer. Kurmadan önce bunları bil:

- **Windows Update kendiliğinden çalışmaz.** Güncellemeleri ara sıra elle yapman gerekir.
- **Yazıcı çalışmaz** (yazdırma hizmeti kapalı).
- **Ağ üzerinden dosya ve yazıcı paylaşımı çalışmaz**, IPv6 kapalıdır.
- **Başlat'taki arama, dosyaların içini taramaz** (arama dizini kapalı); uygulama ve dosya adlarını yine bulur.
- **Netflix ve benzerlerinde 4K çalışmayabilir.** HDCP kopya koruması kapatılır.
- **Sistem Geri Yükleme kapalıdır**, geri yükleme noktası oluşturulmaz. BitLocker şifrelemesi kaldırılır.
- **Windows Defender:** gerçek zamanlı virüs koruması **açık kalır**. Kapananlar: SmartScreen (bilinmeyen dosya ve site uyarıları), bulut tabanlı koruma, otomatik örnek gönderme, Akıllı Uygulama Denetimi ve Kurcalama Koruması. Akıllı Uygulama Denetimi bir kez kapatılınca genelde yeniden açılamaz.

## Yeniden başlatmadan çalıştırma

Bilgisayarı yeniden başlatmadan, güvenli moda geçmeden ve soru sormadan çalıştırmak için (örneğin zaten kurulu bir bilgisayarı güncel ayarlara getirmek için):

```powershell
$env:CULLEWIE_MODE = 'live'; iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Bu modda sürücü temizliği (DDU), Defender ayarları ve ekran soruları atlanır. Hizmet ayarları yazılır ama bir sonraki yeniden başlatmada devreye girer. Her adımın sonucu ekranda özetlenir ve `C:\ProgramData\Cullewie\Work\live-setup-*.log` dosyasına kaydedilir.

## Microsoft Store ve Xbox (Game Pass)

Kurulum varsayılan olarak Store ve Xbox'ın kullandığı hizmetleri kapatır. Kurulumun başında bir soru sorulur:

- **1 = Hayır:** her şey yukarıda anlatıldığı gibi.
- **2 = Sadece Microsoft Store:** Store'dan indirme, kurma ve güncelleme çalışır. Store'un otomatik güncellemesi ve arka plan uygulamaları açık kalır.
- **3 = Xbox ve Game Pass:** Store'a ek olarak Xbox uygulaması, Gaming Services, kumanda (kablolu, adaptör ve Bluetooth), Xbox ağ hizmetleri (Teredo, IPv6), GameInput ve Game Bar da çalışır.

Eksik olan uygulamaları (Microsoft Store; 3'te ayrıca Xbox, Gaming Services, Xbox Identity Provider, Game Bar ve GameInput) kurulum kendisi indirip kurar, yeniden başlatma beklemeden. Daha önce kurulum yapılmış bir bilgisayarda da kapatılmış hizmetler ve ayarlar geri açılır.

2 ve 3'te Windows Update açık kalır ama **yalnızca aylık güncellemeyi** alır: yeni Windows sürümü, sürücü güncellemesi ve önizleme güncellemeleri gelmez. (Windows 11'de "yalnızca güvenlik" diye ayrı bir güncelleme yoktur; güvenlik düzeltmeleri bu aylık pakette gelir.) Windows sürümü kurulumdaki sürüme sabitlenir; o sürümün desteği bitince aylık güncellemeler de durur, o zaman Windows'u elle yeni sürüme yükseltip kurulumu bir kez daha çalıştır. Windows 11 Home'da sürüm sabitleme her zaman işlemeyebilir.

Soru sorulmadan seçmek için komutun başına ekle (yeniden başlatmadan çalıştırırken de böyle seçilir): `$env:CULLEWIE_APPS = 'xbox'` (ya da `'store'`). Bu değişken açık kaldığı sürece aynı penceredeki sonraki kurulumlar da soruyu sormadan bunu kullanır.

## Bir şey bozulursa

Eski bir sürüm Wi-Fi'yi, Microsoft Store'u ya da uygulamalarda oturum açmayı bozduysa, Yönetici PowerShell'de `Scripts\Windows\Services-Restore.ps1` dosyasını çalıştırıp bilgisayarı yeniden başlat. Betik değiştirmeden önce mevcut ayarları yedekler.

## Güvenlik

İndirilen her dosyanın bozulmadığı ve değiştirilmediği SHA-256 ile kontrol edilir. Sürücüler yalnızca üreticinin kendi sitesinden, dijital imzası doğrulanarak kurulur.
