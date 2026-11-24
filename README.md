# cullewie's-progress

Windows 11'i formatladıktan sonra bilgisayarı oyun için hazırlayan, tek komutla çalışan açık kaynak bir kurulum aracı.

Başlat menüsünde **PowerShell**'e sağ tıkla, **Yönetici olarak çalıştır**'ı seç ve şu komutu yapıştır:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Bir pencere açılır. Bir mod seç ve **Başlat**'a bas. Pencere her adımı ve sonucunu gösterir. Bilgisayar kurulum sırasında birkaç kez kendiliğinden yeniden başlar; her açılışta Windows'a giriş yapman yeterli, pencere kaldığı yerden devam eder.

## Modlar

**All-in:** Bilgisayarı oyun için en sade haline getirir. Windows güncellemelerini kurar, ekran kartı sürücüsünü temizleyip en yenisini kurar (NVIDIA / AMD), gereksiz uygulamaları ve hizmetleri kapatır. Microsoft Store, winget, Xbox ve Windows Update kaldırılır ya da kapatılır.

**Xbox & Store:** All-in ile aynı, ama Microsoft Store, Xbox uygulaması, Game Pass, kumanda ve Game Bar çalışır. Windows Update yalnızca aylık güncellemeyi alır.

**Only Store Mode:** All-in ile aynı, ama Microsoft Store'dan indirme ve güncelleme çalışır. Xbox kaldırılır. Windows Update yalnızca aylık güncellemeyi alır.

**Vanilla Mode:** Aracın yaptığı değişiklikleri geri alır ve Windows'u normal haline döndürür. Ekran kartı sürücüsü, BitLocker ve artık sunulmayan uygulamalar geri gelmez.

---

Sorun olursa GitHub'da bir *issue* aç ya da X'ten yaz: [@cullewie](https://x.com/cullewie). Lisans: [MIT](LICENSE).
