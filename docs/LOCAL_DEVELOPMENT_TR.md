# Dukaan — Flutter Android + Django API

Somali’de bağımsız küçük satıcılar için tek uygulama: mağazanı aç, ürün ekle, mağaza kodunu paylaş, siparişi kabul et ve manuel ödeme/teslimat durumunu yönet. Müşteri hesabı gerekmez. **Web alışveriş sitesi veya WebView değildir.** Django Admin yalnız platform yöneticisinindir.

Bu kaynak kod yerel geliştirme/pilot içindir. Google Play’e veya production’a hazır olduğu iddia edilmez. Android SDK bulunmadığı için bu ortamda APK/AAB ve iki cihaz testi tamamlanamadı. Güncel gerçek sonuçlar: [docs/TEST_RESULTS.md](TEST_RESULTS.md).

## Yapı ve sabit sürümler

- `backend/`: Python **3.12.14**, Django **5.2.18**, DRF **3.18.3**, SimpleJWT **5.5.1**. Geçişli Python bağımlılıkları `requirements.txt` içinde sabitlenmiştir.
- `mobile/`: Flutter **3.47.6**, Dart **3.13.5**, Android native Flutter ekranları. Paketler `pubspec.yaml` ve `pubspec.lock` ile sabittir; SDK tercihi `.fvmrc` içindedir.
- PostgreSQL: Compose **18.3**; bu bilgisayardaki gerçek test sunucusu **18.0**. SQLite kullanılmaz.
- `docs/`: OpenAPI, API iş akışı, Android yayınlama ve test kayıtları.

8 Ekim 2026 tarihinde [Django güvenlik sürümü](https://docs.djangoproject.com/en/dev/releases/5.2.18/), [Python 3.12.14](https://blog.python.org/2026/08/python-31214-31116-31021/) ve [Flutter kararlı SDK arşivi](https://docs.flutter.dev/install/archive) kontrol edildi. Sürüm yükseltmelerinde kilit dosyalarını güncelleyip testleri yeniden çalıştırın. Python geliştirme, Docker ve test sürümü aynıdır.

## Bu çalışma alanında hızlı başlatma (PowerShell)

Komutları proje kökünden çalıştırın. Bu oturum `.venv`, `.tools/flutter`, `.env` ve yalnız bu projeye ait `.local/pgdata` oluşturdu; bunlar Git dışında tutulur. Diğer PostgreSQL hizmeti değiştirilmedi.

```powershell
Set-Location 'C:\Users\Moha-qadar\OneDrive\Desktop\E-ticaret'
# Projeye ait PostgreSQL kapalıysa başlatın; açıksa tekrar çalıştırmayın:
& 'C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe' -D .local/pgdata -l .local/postgres.log -o '-p 55432 -h 127.0.0.1' start
.\.venv\Scripts\python.exe backend/manage.py migrate
.\.venv\Scripts\python.exe backend/manage.py seed_demo
.\.venv\Scripts\python.exe backend/manage.py runserver 127.0.0.1:8000 --noreload
```

Bu oturumda oluşturulan geçici yerel PostgreSQL yalnız `127.0.0.1:55432` üzerinde `trust` doğrulaması kullanır. Yalnız bilgisayardaki geliştirme içindir; ağda veya production’da kullanmayın. Kalıcı ekip ortamında parola/SCRAM kullanan Compose veya ayrı PostgreSQL kullanın. `.local` veritabanını depoya veya herkese açık depolamaya eklemeyin.

Android SDK ve emülatör kurulduktan sonra ikinci PowerShell penceresinde:

```powershell
Set-Location 'C:\Users\Moha-qadar\OneDrive\Desktop\E-ticaret\mobile'
..\.tools\flutter\bin\flutter.bat pub get --enforce-lockfile
..\.tools\flutter\bin\flutter.bat devices
..\.tools\flutter\bin\flutter.bat run -d emulator-5554 --dart-define=API_URL=http://10.0.2.2:8000/api/v1/
```

Emülatör adı `flutter devices` çıktısına göre değişebilir. `10.0.2.2`, Android emülatöründen ana bilgisayarı gösterir. Ana bilgisayarda API açıklaması: `http://127.0.0.1:8000/api/v1/docs/`, Admin: `http://127.0.0.1:8000/admin/`. Müşteri web mağazası yoktur.

## Temiz Windows kurulumu

Python 3.12.14, PostgreSQL 18, Git, Flutter 3.47.6 ve Android Studio/Android SDK kurun. Python 3.12 güvenlik bakım dönemindedir; tam 3.12.14 ikilisini sağlayan güvenilir bir dağıtım veya aşağıdaki Docker yolu kullanın. Eski 3.12.x kurulumunu aynı sürüm gibi kabul etmeyin.

```powershell
python --version
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -c "import secrets; print(secrets.token_urlsafe(48))"
# Üretilen değeri .env içindeki SECRET_KEY'e yazın; DB parolasını da değiştirin.
```

PostgreSQL’de ayrı `dukaan` rolü ve `dukaan` veritabanı oluşturun. Testlerin çalışacağı geliştirme rolüne `CREATEDB` yetkisi gerekir; production uygulama rolüne vermeyin. `.env` içindeki host/port/kullanıcı/parolayı bu veritabanına göre ayarlayın. Ardından:

```powershell
.\.venv\Scripts\python.exe backend/manage.py migrate
.\.venv\Scripts\python.exe backend/manage.py createsuperuser
.\.venv\Scripts\python.exe backend/manage.py seed_demo
.\.venv\Scripts\python.exe backend/manage.py runserver 127.0.0.1:8000 --noreload
```

Flutter için `flutter --version` çıktısının 3.47.6 olduğunu doğrulayın. PATH kullanıyorsanız belgelerdeki `..\.tools\flutter\bin\flutter.bat` yerine `flutter` yazabilirsiniz. Android kurulumu: [Flutter Android kurulum rehberi](https://docs.flutter.dev/platform-integration/android/setup).

## Docker Compose

Docker Desktop motorunu açın. `.env` hazırlayıp rastgele SECRET_KEY/POSTGRES_PASSWORD belirleyin; `DEBUG=true` yerel geliştirme içindir. Compose container bağlantısında host/portu otomatik olarak `db:5432` yapar.

```powershell
docker compose up --build -d
docker compose exec api python manage.py createsuperuser
docker compose exec api python manage.py seed_demo
docker compose exec api python manage.py test shop --noinput
docker compose logs api
docker compose down
```

Veriler `pgdata`, fotoğraflar `media`, toplanmış statikler `static` named volume içindedir. `docker compose down -v` veriyi siler; kullanmayın. Compose geliştirme sunucusu çalıştırır, internete açık production sunucusu değildir. Bu ortamda Docker motoru açılamadığı için Compose build/run doğrulanmadı.

## Telefon, USB ve yerel ağ

Fiziksel Android’de USB hata ayıklamayı açın, bilgisayarı telefonda onaylayın:

```powershell
adb devices
adb reverse tcp:8000 tcp:8000
Set-Location mobile
flutter run -d TELEFON_ID --dart-define=API_URL=http://127.0.0.1:8000/api/v1/
```

Wi-Fi testi için API’yi `0.0.0.0:8000` üzerinde başlatın, bilgisayarın LAN IP’sini `ALLOWED_HOSTS` listesine ekleyin, güvenlik duvarında yalnız özel ağ erişimini açın ve aynı Wi-Fi üzerindeki telefonda `API_URL=http://BILGISAYAR_IP:8000/api/v1/` kullanın. Compose varsayılanı yalnız loopback’e bind eder; LAN için port eşlemesini bilinçli olarak `8000:8000` yapmanız gerekir. Bu debug istisnasıdır. **Release manifest HTTP trafiğini kapatır; Dart release uygulaması HTTPS olmayan API_URL ile başlamaz.**

## Testler ve şema

```powershell
.\.venv\Scripts\python.exe -m pip check
.\.venv\Scripts\python.exe backend/manage.py check
.\.venv\Scripts\python.exe backend/manage.py makemigrations --check --dry-run
.\.venv\Scripts\python.exe backend/manage.py test shop --noinput
.\.venv\Scripts\python.exe backend/manage.py spectacular --file docs/openapi.yaml --validate --lang en
Set-Location mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test
# API ayrı terminalde çalışırken: iki bağımsız Dart API istemcisi; emülatör testi değildir.
flutter test test_live/live_api_test.dart --dart-define=API_URL=http://127.0.0.1:8000/api/v1/
```

`TransactionTestCase` testleri gerçek PostgreSQL zorunlu kılar. Test veritabanı `test_dukaan` oluşturulur; geliştirme uygulama veritabanı silinmez. Canlı API testi benzersiz `example.invalid` satıcı/mağaza oluşturur ve geliştirme veritabanında bırakır; production adresine karşı çalıştırmayın.

## Ortam ayarları ve marka

| Değişken | Amaç |
|---|---|
| `SECRET_KEY` | Zorunlu uzun rastgele sunucu sırrı; APK’ya girmez |
| `DEBUG` | Varsayılan false; yalnız yerelde true |
| `BRAND_NAME` | Uygulama adı, varsayılan Onlinesuuq |
| `PUBLISHER_NAME` | Bireysel geliştiricinin gerçek adı (Play yayıncı kimliği). Şirket değildir, satıcı mağaza bilgisinden ayrıdır. Boşsa yasal sayfalar "tamamlanacak" gösterir |
| `SUPPORT_EMAIL` | Gizlilik/hesap silme sayfalarında görünen destek adresi. Boşsa sayfalar "tamamlanacak" gösterir |
| `POSTGRES_DB/USER/PASSWORD/HOST/PORT` | Yalnız sunucuda DB bağlantısı |
| `ALLOWED_HOSTS` | Virgülle ayrılmış açık host listesi |
| `EMAIL_BACKEND` | Debug console, production SMTP varsayılanı |
| `EMAIL_HOST/PORT/HOST_USER/HOST_PASSWORD` | SMTP, TLS açık |
| `DEFAULT_FROM_EMAIL` | Gerçek doğrulanmış göndericiyle değiştirilmeli |
| Flutter `API_URL` | `--dart-define` ile sonu `/api/v1/` olan API adresi |
| Flutter `INSTALL_URL` | Gerçek yayımlanmış kurulum adresi varsa paylaşım metnine eklenir |

`BRAND_NAME` API’den uygulamaya gelir. Ad değişikliğinde APK çevrimdışı varsayılanı ve Android başlatıcı etiketini aynı ayardan üretmek için `python backend/manage.py export_brand` çalıştırıp uygulamayı yeniden derleyin. Adın marka/domain uygunluğu araştırılmış veya satın alınmış değildir.

## İş kuralları

- Bir satıcının tek mağazası vardır. Tüm satıcı sorguları oturum sahibine göre filtrelenir. Sahiplik ve moderasyon alanları istemciden yazılamaz.
- Sipariş NEW iken stok ayrılmaz. Kabul sırasında mağaza → sipariş → artan ürün ID sırasıyla PostgreSQL satırları kilitlenir. Herhangi bir ürün uygun değilse tamamı geri alınır.
- Kabul/iptal tekrarları ikinci stok hareketi yaratmaz. Teslim edilmiş veya iptal edilmiş sipariş yeniden açılmaz.
- Stok düzenlemesi `expected_updated_at` ister. Eski ürün formu kabul edilen siparişin stok düşümünü ezemez; kullanıcı ürünü yeniden açmalıdır.
- Checkout önce 15 dakika geçerli imzalı fiyat teklifi alır. Ürün/fiyat/teslimat/ödeme talimatı değişmişse yeniden inceleme gerekir. Para Decimal ile hesaplanır; istemci toplamı kullanılmaz.
- Anonim oturum sunucuda yalnız hash olarak tutulur (30 gün). Checkout anahtarı o oturumla eşleşir. Aynı anahtar farklı içerikle kullanılamaz. Bağlantı belirsizliğinde mobil istemci aynı anahtarı saklar ve sonucu sorgular.
- Access token 10 dakika, refresh token 14 gün. Refresh her kullanımda döner ve önceki token iptal olur. Şifre değişimi/çıkış tüm kullanıcının oturum sürümünü artırır; diğer cihazlar da tekrar giriş yapar. Admin hesap kapatma da oturumları geçersiz kılar.
- Sipariş ve ödeme ayrı durumdur. Para alma/iade otomatik değildir. Manuel onayda kullanıcı, zaman, referans ve olay kaydı tutulur. Yanlış ödeme düzeltmesi yalnız superuser + gerekçeyle Admin üzerinden yapılabilir.
- Takip endpoint’i token’ı `X-Tracking-Token` başlığında alır; telefon/adres/ad alanını döndürmez. API yanıtları `no-store`, `noindex`, `no-referrer` kullanır. Access log’larda başlık/gövde yakalamayın.
- IP bazlı DB sayaçları worker’lar arasında ortaktır. Proxy’de `REMOTE_ADDR` doğru ve güvenilir şekilde yapılandırılmalıdır. Arbitrary X-Forwarded-For’a güvenilmez. Günlük `python backend/manage.py cleanup_rate_limits` ve `python backend/manage.py flushexpiredtokens` çalıştırın.
- Görseller gerçek JPEG/PNG/WebP olarak doğrulanır, 5 MB / 20 milyon piksel sınırı uygulanır, yön düzeltme ve yeniden JPEG encode ile metadata temizlenir; dosya adı rastgeledir.

## Demo, diller ve küçük kararlar

`seed_demo` iki mağaza (`demo-1`, `demo-2`), üçer ürün ve örnek sipariş oluşturur; tekrar çalıştırıldığında yeni kopyalar oluşturmaz. İlk çalıştırmada rastgele satıcı şifrelerini terminalde gösterir. `--password` opsiyoneldir; paylaşılan terminal/geçmişte gerçek şifre kullanmayın. Admin şifresi oluşturmaz, `DEBUG=False` altında çalışmaz.

Somalice varsayılan, İngilizce ikinci dildir. Uygulamanın JSON çevirileri Flutter `LocalizationsDelegate` ile yüklenir; API proje mesajları Django gettext kataloglarındadır. `python backend/compile_translations.py` katalogları yeniden derler. **Somalice metinler ana dili konuşan kullanıcılarla test edilmelidir.** Flutter’ın bazı platform metinleri ve henüz çevrilmemiş Django/DRF yerleşik doğrulama mesajları İngilizce kalabilir.

Sepet ve son 20 halka açık ürün sorgusu çevrimdışı saklanır; fotoğrafların çevrimdışı kalıcılığı garanti edilmez. Özel satıcı ekranları diskte cache edilmez. Hesap değişimi takip kayıtları, anonim oturum, checkout taslağı ve sepeti temizler. Saklamak istediğiniz takip anahtarını hesap değişiminden önce güvenli bir yerde tutun. Kayıtların silinmesi sunucudaki gerçek siparişi iptal etmez. Bildirim, sürekli polling, AI, SMS, mobil para API’si veya ücretli bağımlılık yoktur.

## Static/media ve yedekleme

`python backend/manage.py collectstatic --noinput` Admin statiklerini `backend/staticfiles` altında toplar. Yerel `DEBUG` sunucusu media’yı sunar. Production’da media/static ayrı origin veya güvenli reverse proxy ile çalıştırılmalı; dosyalara çalıştırma yetkisi verilmemelidir. Kalıcı volume veya kalıcı nesne deposu gereklidir; geçici cloud diskini kullanmayın. Silinen/değiştirilen görsellerin eski dosyaları otomatik temizlenmez; referans kontrolü yapan bakım politikası hazırlanmalıdır.

Compose PostgreSQL yedeği (parolayı komut satırına yazmadan):

```powershell
docker compose exec db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -f /tmp/dukaan.dump'
docker compose cp db:/tmp/dukaan.dump ./dukaan.dump
# Geri yüklemeyi önce AYRI, boş veritabanında sınayın; mevcut veriye --clean uygulamayın.
docker compose cp ./dukaan.dump db:/tmp/restore.dump
docker compose exec db sh -c 'createdb -U "$POSTGRES_USER" dukaan_restore'
docker compose exec db sh -c 'pg_restore -U "$POSTGRES_USER" -d dukaan_restore --no-owner /tmp/restore.dump'
```

Media volume’u ayrıca yedekleyin; DB yedeği fotoğrafları içermez. Yedekler müşteri verisi ve takip sırlarını içerir; erişim sınırlı/şifreli depolama ve geri yükleme testi gerekir. Gerçek veri içeren `.dump` dosyalarını Git’e eklemeyin.

## Production ve sonraki adımlar

[Android yayınlama kontrol listesi](ANDROID_RELEASE.md), [API sözleşmesi](API.md), [test kayıtları](TEST_RESULTS.md), [pilot sınırları](PILOT.md) ve [Data Safety hazırlığı](DATA_SAFETY.md) teslim kapsamındadır. Gerçek SMTP, HTTPS, domain, kalıcı depolama, yedek/geri yükleme ve hata izleme süreçleri hâlâ tamamlanmalıdır. Self-service hesap/veri silme uygulandı (uygulama içi + `/account-deletion/` web sayfası + `POST /api/v1/auth/delete/`). Gelecek roadmap: Somalice metinden ürün taslağı; şu anda AI servisi veya düğmesi yoktur.

## Bireysel geliştirici Play yayını

Bu uygulama **bireysel (şahıs) geliştirici** hesabından yayımlanır; şirket değildir. Yayıncı kimliği (`PUBLISHER_NAME`, destek e-postası) uygulama içindeki **satıcıların mağaza/işletme bilgilerinden ayrıdır** — ikisi karıştırılmamalıdır. Aşağıdaki Google gereklilikleri şirket hesabına değil, bireysel hesaba göredir ve yayın tarihinde Play Console'dan yeniden doğrulanmalıdır (Google kuralları değiştirebilir).

- **Kimlik doğrulama:** Bireysel hesapta yasal ad ve adres, hesap açılışında bağlanan Google Payments profilinden alınır; profil doğrulanmamışsa resmi kimlik belgesi istenir. Play'de yalnızca e-posta adresi herkese açık görünür; web sitesi bireysel hesapta isteğe bağlıdır. ([kimlik doğrulama](https://support.google.com/googleplay/android-developer/answer/10841920?hl=en), [gerekli bilgiler](https://support.google.com/googleplay/android-developer/answer/13628312?hl=en))
- **Cihaz doğrulama:** Yeni bireysel hesaplar, uygulamayı yayınlamadan önce Play Console mobil uygulamasıyla gerçek bir Android cihaza (en az Android 10, rootsuz) erişimi doğrulamalıdır. ([cihaz doğrulama](https://support.google.com/googleplay/android-developer/answer/14316361))
- **Kapalı test zorunluluğu:** 13 Kasım 2023'ten sonra açılan bireysel hesaplar, üretime (production) başvurmadan önce **en az 12 test kullanıcısıyla, kesintisiz en az 14 gün** kapalı test yürütmelidir (başlangıçtaki 20 kişi şartı Aralık 2024'te 12'ye indirildi). Testçiler 14 gün boyunca kayıtlı kalmalıdır. ([kapalı test şartı](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en))
- **Yaş:** Geliştirici en az 18 yaşında olmalıdır.

**Otomatik kod testleri ile Play kapalı testi ayrı şeylerdir:** Bu repodaki `flutter test` ve `manage.py test` geliştirici doğrulama testleridir ve Google'ın 12 testçi/14 gün kapalı test şartını **karşılamaz**. Kapalı test, gerçek testçilerin Play'den yüklediği imzalı derlemeyle Play Console üzerinde ayrıca yürütülür.

Değişmeyen teknik gereklilikler (hesap türünden bağımsız): gerçek `API_URL` (HTTPS), imza anahtarı + `key.properties` (repo dışında), onaylanmış `applicationId`, uygulama ikonu/mağaza görselleri ve canlı backend. Ayrıntılar [docs/ANDROID_RELEASE.md](ANDROID_RELEASE.md) içindedir.
