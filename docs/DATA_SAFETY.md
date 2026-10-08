# Google Play Data Safety hazırlığı

Bu tablo, **koddaki gerçek davranışa** dayanır (Flutter bağımlılıkları, Android izinleri, API alanları, Django modelleri). Play Console'daki Data Safety formunu doldurmadan önce burada "doğrulanmadı" işaretli satırları kendi canlı altyapınıza göre kesinleştirin. Otomatik olarak "veri toplamıyoruz" denmemiştir.

Kaynaklar: `mobile/pubspec.yaml`, `mobile/android/app/src/main/AndroidManifest.xml`, `backend/shop/models.py`, `backend/shop/views.py`, `backend/shop/security.py`.

## Toplanan veriler

| Veri türü (Google kategorisi) | Toplanıyor mu | Neden | Kimler görür | Silme |
|---|---|---|---|---|
| Ad — satıcı adı, müşteri adı (`User.name`, `Order.customer_name`) | Evet | Hesap, sipariş | Satıcı siparişini görür | Hesap silmede anonimleştirilir; sipariş kaydı kişiselleştirilmeden kalır |
| E-posta (`User.email`) | Evet | Giriş, şifre sıfırlama | Yalnız kullanıcı/sistem | Hesap silmede anonimleştirilir |
| Telefon — satıcı + müşteri (`Store.phone`, `Store.whatsapp`, `Order.phone`) | Evet | İletişim, teslimat | Satıcı iletişimi alıcıya görünür; müşteri telefonu satıcıya | Satıcı telefonu silmede temizlenir; sipariş telefonu kayıt olarak kalır |
| Adres — teslimat (`Order.region`, `Order.address`) | Evet (yalnız teslimat siparişinde) | Teslimat | İlgili satıcı | Sipariş kaydı olarak kalır |
| Ödeme bilgisi — mobil para hesap adı/numarası (`Store.payment_account`, `Store.payment_name`) | Evet | Alıcı satıcıya ödeme yapsın | Alıcılara görünür | Hesap silmede temizlenir. **Not:** kart/banka değil, kullanıcının girdiği mobil-para tanıtıcısıdır |
| Fotoğraflar (`Photo.image`, `Store.logo`) | Evet | Ürün/mağaza görseli | Alıcılara görünür | Hesap silmede dosyalar silinir |
| Satın alma/sipariş geçmişi (`Order`, `OrderLine`, `Event`) | Evet | Sipariş akışı, denetim | Satıcı ve ilgili alıcı | Kişisel alanlar temizlenerek saklanır |
| Şifre (`User.password`) | Evet, yalnız tuzlu hash | Kimlik doğrulama | Hiç kimse (hash) | Hesap silmede kullanılamaz hale gelir |
| IP adresi | Evet, sunucu tarafı | Yalnız hız sınırlama/kötüye kullanım (`RateBucket`, hash'lenmiş) | Yalnız sistem | Hız sayaçları `cleanup_rate_limits` ile silinir |
| Cihaz-içi tokenlar (misafir oturumu, takip anahtarı) | Cihazda saklanır | Misafir checkout, sipariş takibi | Yalnız cihaz | Hesap/oturum değişiminde cihazdan silinir; sunucuda yalnız hash |
| Konum, SMS, rehber, takvim, kişiler | **Hayır** | — | — | — |
| Reklam/analitik tanımlayıcıları | **Hayır** (reklam/analitik SDK yok — doğrulandı) | — | — | — |

## İzinler ve SDK'lar

- Android izinleri: yalnız `INTERNET`. Konum, SMS, rehber, geniş dosya erişimi yoktur. Fotoğraflar sistem foto seçicisiyle (`image_picker`) alınır.
- Flutter bağımlılıkları: `http`, `flutter_secure_storage`, `image_picker`, `share_plus`, `shared_preferences`, `url_launcher`, `uuid`, `flutter_localizations`. Üçüncü taraf reklam/analitik/çökme (crash) SDK'sı **yoktur** (doğrulandı).
- Aktarımda şifreleme: Evet. Release derlemesi HTTPS olmayan `API_URL`'i reddeder; manifest `usesCleartextTraffic=false`.
- Üçüncü taraf şirketlerle paylaşım: Kod içinde yoktur. Satıcı/alıcı arasında bilgi gösterimi uygulamanın temel işlevidir, Google anlamında "üçüncü taraf paylaşımı" değildir.

## Doğrulanmadı (canlı altyapıya göre teyit edilmeli)

- **Barındırma (hosting) sağlayıcısı** ve verinin fiziksel konumu / veri işleme koşulları.
- **SMTP/e-posta sağlayıcısı** (şifre sıfırlama e-postalarını işler).
- **Ters proxy / web sunucusu erişim logları** IP veya yol tutuyor mu (Django tarafı `django.server`/`django.request` logları kapalıdır — doğrulandı; öndeki proxy ayrı yapılandırılır).
- **Yedeklerin** saklama süresi, erişimi ve şifrelemesi.
- Medya depolamanın (fotoğraflar) kalıcı/erişim-sınırlı olup olmadığı.

## Benim doldurmam gereken Data Safety alanları

- Sipariş/denetim kayıtlarının **saklama süresi ve gerekçesi** (gerçek bir gerekçe; uydurma yasal zorunluluk değil). Bu, gizlilik ve hesap-silme sayfalarında da "tamamlanacak" olarak işaretlidir.
- Yukarıdaki "doğrulanmadı" satırlarının her biri.
- `PUBLISHER_NAME` ve `SUPPORT_EMAIL` ortam değişkenlerine gerçek değerler.
