# Kaynak ve dosya karmaları

Kaynak paket 12 PowerShell dosyası içeriyordu; WinGet sürümü bu repodan çıkarıldı. Aşağıdaki değerler repoda kalan 11 dosyayı ve sonradan eklenen Tweaks.ps1, Defender.ps1 ve P0-State.ps1 dosyalarını tanımlar. Her dosyanın boyu bayt cinsindendir.

| Dosya | Bayt | SHA-256 |
|---|---:|---|
| Scripts/Drivers/DDU/DDU.ps1 | 12051 | 83bdabd9bdac7aa4b2b6ed30daf758b8d3beaa47deaf907790012a32f2f12dce |
| Scripts/Drivers/Debloated-Installer/Driver-Installer.ps1 | 37422 | 5bf49a8407d7b7cb9acd89465efcf3d68f91729b29ec11327fbf88492260e0c1 |
| Scripts/Drivers/Multi-GPU/Driver-Downloader.ps1 | 4195 | 95c0a6d05e45e230f9cce80ba8895f9b26072fbe6a3d022944fc0b8c671709cf |
| Scripts/Drivers/NVIDIA/NVIDIA-Driver-Updater.ps1 | 8702 | 25ed28da9d26504a19168262c0c3054df439ef5e90143b940b24e13af05a9adb |
| Scripts/NVIDIA/Digital-Vibrance.ps1 | 10551 | e3ba8e46b90f3b353245cf67e83b7b4bcccee804304e97cbe575345572b9506f |
| Scripts/NVIDIA/Settings-GitHub.ps1 | 12972 | 5b9c788538179fc4ae1d023e69064a5520ae78fba23e84d0647508c34e149e0c |
| Scripts/Windows/Copilot-Off.ps1 | 1548 | 2de74ba40c6aa77e7be94a1a5a022bdeea592405fe4ce1edc49613649c79b156 |
| Scripts/Windows/Power-Plan.ps1 | 16724 | d2c675f55c89d54becbbba0bbbf299f3671a90f1f269603d8b001c183ff28ef0 |
| Scripts/Windows/Services.ps1 | 29012 | 3db3d332d3e8ed3a820036a9aaccb0041124afc255c5a2e4b008ed2bd66eafd1 |
| Scripts/Windows/Timer-Resolution.ps1 | 10617 | 36e1a45ba988ed00a21acb5b0be7a355493811f9b5f31618081d4fa77b6dd6a4 |
| Scripts/Windows/Tweaks.ps1 | 11519 | 4dd36fd3eb646958dd1512b388828752657e92661f107326a269fbf4abd76706 |
| Scripts/Windows/Defender.ps1 | 11959 | d49d2eeb6105bb2319ee8f21b2f329facfd3fc82c9c83c0f885eb1e425221a0f |
| Scripts/NVIDIA/P0-State.ps1 | 1356 | 613c9aba2ad32f0db0609cc6046fac946919cddd66a26919e74677a2403266dc |
| Scripts/Windows/Widgets.ps1 | 1398 | 95376b109b970b8f66fcb9433fe9a112fde83550a6145925c20c67163dc5396c |

Ana NVIDIA Driver Updater aynı GPU bulma, NVIDIA katalog arama ve imza doğrulama mantığını korur. Büyük paketi Windows PowerShell 5.1'in yavaş yerleşik ilerleme çubuğu yerine yüzdeyi sınırlı aralıklarla güncelleyen akışla indirir. İmzalı NVIDIA paketi yalnızca `Display.Driver` bileşeni için `-s -n Display.Driver` ile çalıştırılır; NVIDIA App ve NVIDIA Control Panel kurulum akışına eklenmez.


The guided DDU path uses NVIDIA-only cleanup flags in normal Windows mode, without restarting or creating a restore point; it saves the GPU model name for the primary updater. The standalone DDU Auto/Manual path keeps its original Safe Mode behavior. Services Off leaves the Windows CaptureService in Manual mode so screen-capture apps can start it on demand.

