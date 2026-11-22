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
- **Windows Update'in araya girip kendi sürücüsünü kurmasını engeller**, kurulum bitene kadar.
- **BitLocker açıksa duraklatır**, böylece yeniden başlatmalarda kurtarma anahtarı sorulmaz.

### 2. Temizlik (güvenli mod)

- **Eski ekran kartı sürücüsünü iz bırakmadan siler.** (Display Driver Uninstaller; NVIDIA kartlarda ve AMD RX 5000–9000'de. Yeni sürücü bulunamazsa eski AMD sürücüsü silinmez.)
- **Windows Defender ayarlarını uygular** (ayrıntısı aşağıda, "Bilmen gerekenler" bölümünde). Bu ayarlar yalnızca güvenli modda yazılabiliyor.

### 3. Kurulum ve ayarlar (normal Windows)

- **En yeni ekran kartı sürücüsünü kurar.** Sürücüyü NVIDIA'nın ya da AMD'nin kendi sitesinden indirir ve dijital imzasını kontrol eder; imza üreticiye ait değilse kurmaz. NVIDIA'da yalnızca sürücünün kendisi kurulur: NVIDIA App ve Control Panel kurulmaz. Aynı sürüm zaten kuruluysa indirmeyi atlar.
- **NVIDIA ayarlarını yapar.** NVIDIA Profile Inspector ile tüm oyunlara 30 ayar uygular: V-Sync kapalı, Low Latency Mode kapalı, güç modu "en yüksek performans", doku filtreleme "yüksek performans", G-SYNC kapalı. Kartı hep en yüksek hızında tutar (P0 durumu) ve MSI modunu açar.
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
  - DirectX ve Visual C++ çalışma dosyalarını kurar (çoğu oyunun açılması için gerekli).
  - Yalnızca C: sürücüsündeki geçici dosyaları siler; takılı USB belleklere dokunmaz.
- **Ekran ayarları (son adım):** Tam ekran ölçekleme sorulmadan açılır ve ekrana not düşülür; 4:3 gibi düşük çözünürlükler tüm ekrana yayılır. Ardından tek soru gelir: **dijital canlılık** (AMD'de doygunluk) yüzde kaç olsun? NVIDIA bu değeri yeniden başlatınca unuttuğu için her oturum açılışında yeniden uygulanır.
- **Gereksiz Windows hizmetlerini kapatır** (yaklaşık 200 hizmet). Ağ, Wi-Fi, güvenlik duvarı, aygıt kurulumu, oturum açma, parola kasası ve Microsoft Store'un ihtiyaç duyduğu hizmetlere dokunmaz. Başlamadan önce açık kalacak her hizmetin, kapatılacak bir hizmete bağlı olup olmadığını kontrol eder; bağlıysa hiçbir şeyi değiştirmeden durur.
- **Son kez normal yeniden başlatır.** Kurulum tamam.

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

## Bir şey bozulursa

Eski bir sürüm Wi-Fi'yi, Microsoft Store'u ya da uygulamalarda oturum açmayı bozduysa, Yönetici PowerShell'de `Scripts\Windows\Services-Restore.ps1` dosyasını çalıştırıp bilgisayarı yeniden başlat. Betik değiştirmeden önce mevcut ayarları yedekler.

## Güvenlik

İndirilen her dosyanın bozulmadığı ve değiştirilmediği SHA-256 ile kontrol edilir. Sürücüler yalnızca üreticinin kendi sitesinden, dijital imzası doğrulanarak kurulur.
