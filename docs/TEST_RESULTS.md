# Offline Windows release verification — 8 October 2026

Version 1.1.0, application commit `403383227d912f44b42d1d9e300fa295921e4190`.

[Successful Windows build](https://github.com/Mohamed-Qadar/Onlinesuuq/actions/runs/37757929316) · [Published release](https://github.com/Mohamed-Qadar/Onlinesuuq/releases/tag/v1.1.0)

- Flutter analysis: no issues.
- 18 Flutter tests passed, including inventory persistence, historical sale price, stock limits, backup validation/restore, archive history, incomplete writes and local product-entry/language switching.
- Windows x64 release and Inno Setup installer compiled successfully.
- Automated silent install, native process/window startup, local inventory initialization and uninstall passed on the GitHub Windows 2022 runner.
- Desktop layout rendered and visually inspected at 1280x800 with fictional inventory.
- Installer SHA256: `86ddb011cdb5aa541ccf9227aaff324e77f746e616eec436b125b8394caefb1d`.

The hosted runner has development tools installed; this is not a claim of exhaustive testing on every clean consumer PC. The package bundles the Visual C++ runtime. Installer is unsigned. Offline mode does not include cloud sync, internet storefront, payment processing, or sale cancellation. Data is stored locally; users should export backups regularly.

---

## Earlier online / Android verification record

# Gerçek doğrulama sonuçları

Tarih: **8 Ekim 2026**, Africa/Nairobi. Son kaynak değişikliklerinden sonra çalıştırılan kontroller aşağıdadır. Çalıştırılmamış işlemler başarılı sayılmamıştır.

| Kontrol | Gerçek sonuç |
|---|---|
| Python | 3.12.14 |
| Django / DRF | 5.2.18 / 3.18.3 |
| PostgreSQL | Ayrı yerel cluster, PostgreSQL 18.0, 127.0.0.1:55432 |
| `manage.py test shop --noinput` | **30 test geçti**, 0 başarısız, 0 atlanan; son koşu 37,798 saniye |
| PostgreSQL concurrency | 3 TransactionTestCase geçti: iki sipariş aynı stoğa talip, aynı siparişin çift kabulü, aynı checkout’un eşzamanlı gönderimi |
| `manage.py check` | Sorun yok |
| `makemigrations --check --dry-run` | Eksik migration yok |
| Migration uygulama | 0001_initial, 0002_ratebucket_created_at, 0003_event_reference uygulandı |
| `pip check` | Bozuk/uyumsuz bağımlılık bildirimi yok |
| OpenAPI oluşturma / validate | Başarılı, son koşuda 0 uyarı / 0 hata |
| Flutter / Dart | 3.47.6 / 3.13.5 |
| `flutter analyze` | **No issues found** |
| `flutter test` | **12 test geçti**, 0 başarısız, 0 atlanan |
| `flutter test test_live/live_api_test.dart ...` | **1 gerçek API akış testi geçti** |
| Dar/geniş widget düzeni | 360, 390 ve 1024 px testleri geçti; PNG önizlemeleri oluşturuldu |
| `docker compose config --quiet` | Başarılı |
| Çalışan API kontrolü | `GET /api/v1/config/`: HTTP 200, `Cache-Control: no-store` |

## Backend kapsamı

Kayıt, giriş, refresh dönüşümü/eski token reddi, çıkış ve eski access reddi; büyük/küçük harfsiz e-posta; şifre değişimi, reset ve kapalı hesap; tek mağaza ve korunmuş sahiplik/moderasyon alanları; başka mağazanın ürün/sipariş/görsel uçlarına erişim engeli; taslak/arşiv/askıya alınmış içerik; negatif fiyat/stok/adet ve karışık mağaza; gerçek görsel doğrulama, yeniden encode, üç fotoğraf sınırı ve bozuk PNG; misafir checkout, sunucu toplamı, fiyat değişiminde yeniden onay, idempotency; teslimat bölgesi/ücreti; kabul/iptal/geri stok; satıcı ödeme onayı ve iade gereksinimi; orijinal ödeme referansının olay geçmişinde korunması; tüm kalemlerin rollback’i; takip mahremiyeti ve başlıkları; Admin readonly durum/stok ve ortak servis; CSRF, DB rate limit, dil seçimi; demo seed tekrar çalıştırma ve production engeli; eski stok formu çakışması; süresi dolmuş misafir token’ının yalnız mevcut sonucu kurtarması.

Eşzamanlılık testleri ayrı thread ve DB bağlantılarıyla gerçek PostgreSQL üzerinde çalıştı. SQLite kullanılmadı. Mutlak stok düzenlemesinin eski timestamp ile kabul edilmiş sipariş stok düşümünü ezemediği ayrıca test edildi.

## Flutter kapsamı

Tek mağazalı sepet ve açık değiştirme gereksinimi, stok sınırı, taslak kalıcılığı, giriş/refresh ve korumalı isteğin tekrarı, hesap değişiminde özel veri temizliği, timeout sırasında aynı checkout anahtarının korunması, kayıp yanıtta mevcut sonucu kurtarma, offline çıkışta sahte iptal başarısı göstermeme, takip token’ının URL yerine başlıkta taşınması, Somalice/İngilizce dil değişimi, native mağaza/ürün ekranına navigasyon ve üç ekran genişliği.

Gerçek API testi iki ayrı `Api` nesnesi ve iki ayrı token deposu kullanır. Satıcı kayıt/giriş → mağaza → ürün → multipart fotoğraf yükleme → mağazayı yayımlama → ayrı misafir ürün listeleme → fiyat teklifi → checkout → aynı checkout’u tekrar gönderme → kabul → manuel PAID → PREPARING → DELIVERED → misafir takip → stok kontrolü → çıkış akışı geçti.

Bu test **Flutter test VM’sinde** çalıştı; Android galerisini veya donanım güvenli depolamasını çalıştırmadı. Test deposu bellektedir; uygulamanın Android kodu `flutter_secure_storage` kullanır. Gerçek cihazla doğrulanmış gibi yorumlanmamalıdır.

## Görsel önizlemeler

- [390 px Somalice ana ekran](previews/home-390.png)
- [360 px ana ekran](previews/home-360.png)
- [1024 px geniş görünüm](previews/home-1024.png)

Bunlar gerçek Flutter widget render’larıdır, Android ekran görüntüsü değildir. Yerel önizlemede Segoe UI ve Material Icons yüklendi; Android’in gerçek font/klavye davranışı cihaz testinde ayrıca kontrol edilmelidir. 390 px görüntü gözle incelendi, yatay taşma görülmedi.

## Çalıştırılamayan veya tamamlanmayan kontroller

- **Android SDK yok** (`flutter doctor -v`: Unable to locate Android SDK). APK/AAB üretilmedi; debug/release Gradle derlemesi, imza doğrulaması, iki cihaz/emülatör akışı ve gerçek galeri/güvenli depolama testi çalıştırılmadı. Native integration denemesi “No supported devices connected” ile durdu.
- Docker istemcisi var, Docker motoru çalışmıyor. Desktop başlatma denemesi otomatik onay denetimince engellendi; ayrıntılı gerekçe dönmedi. **Compose build/up çalıştırılmadı.** Yalnız Compose yapılandırması doğrulandı; backend testleri kurulu PostgreSQL ile tamamlandı.
- Gerçek SMTP, HTTPS/reverse proxy, kalıcı cloud media, production yedek/geri yükleme ve mağaza yayımlama yoktur.
- Self-service hesap/veri silme henüz yok; Play öncesi geliştirilmelidir. Geniş izin, süreç sonlandırma sonrası fotoğraf kurtarma, TalkBack, büyük yazı boyutu ve ana dili Somalice olan kullanıcı testleri bekliyor.
- Bazı Flutter platform ve Django/DRF kütüphane metinleri İngilizce kalabilir. Proje metinleri Somalice/İngilizce kataloglarındadır; çeviriler kusursuzluk iddiası taşımaz.
- Kullanılmayan eski görsel dosyalarının depodan temizliği ve operasyonel veri saklama politikası production öncesi hazırlanmalıdır.

İlk koşularda bulunan dil testi başlık çakışması, Flutter yerelleştirme delegesi, widget testindeki kaydırma hedefi ve bozuk PNG doğrulama hatası düzeltildi. Yukarıdaki sayılar son başarılı koşullara aittir.
