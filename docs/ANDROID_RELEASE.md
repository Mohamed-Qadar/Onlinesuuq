# Android doğrulama ve yayımlama

Bu ortamda Android SDK/emülatör yoktur. APK/AAB oluşturulmadı. Flutter analizi ve VM/widget testleri cihaz doğrulamasının yerine geçmez.

## Yerel debug derleme

1. [Resmî Flutter Android kurulumunu](https://docs.flutter.dev/platform-integration/android/setup) izleyerek Android Studio, SDK, JDK, Android command-line tools ve emülatörü kurun.
2. `flutter doctor -v`, `flutter doctor --android-licenses`, `flutter devices` ile ortamı doğrulayın.
3. `mobile` dizininde `flutter pub get --enforce-lockfile` ve `flutter build apk --debug --dart-define=API_URL=http://10.0.2.2:8000/api/v1/` çalıştırın.
4. Başarılı derlemede dosya `mobile/build/app/outputs/flutter-apk/app-debug.apk` olur. Bu bir **beklenen çıktı yolu**, bu teslimde mevcut APK değildir.

Debug manifest HTTP erişimine izin verir. Main/release manifest HTTP’yi kapatır, yedeklemeyi kapatır. Galeri seçimi platform photo picker aracılığıyladır; SMS, konum, rehber veya geniş dosya erişimi izni istenmez. Gerçek cihazda izin reddi, fotoğraf seçiminin iptali ve süreç öldürülmesi ayrıca denenmelidir.

## İki bağımsız Android oturumu kabul testi

Satıcı için bir cihaz/emülatör, müşteri için ayrı cihaz/emülatör kullanın. Telefonlarda aynı backend adresine erişildiğini doğrulayın.

1. Satıcı kayıt/giriş → mağaza bilgileri → taslak mağaza.
2. Ürün adı, fiyat, stok → kaydet → galeriden fotoğraf → yayımlanmış ürün → mağazayı yayımla.
3. Android paylaşım menüsünden mağaza adını/kodunu paylaşın. Gerçek INSTALL_URL ayarlı değilse yalnız kod paylaşılmalıdır.
4. Misafir ikinci cihazdan kodu arasın, fotoğraflı ürünü açsın, sepete eklesin. Başka mağaza ürünü seçerse değişim onayı görünmelidir.
5. Pickup ve delivery ücretlerini karşılaştırın; adres/bölge hatalarını deneyin. Son toplamı onaylayıp sipariş oluşturun.
6. Yeni siparişte ödeme hesabı görünmemeli. Satıcı kabul edince stok yalnız bir kez düşmeli; müşteri yenileyince ödeme talimatı görünmeli.
7. Satıcı kendi hesabını gerçekten kontrol ettikten sonra onay ekranı ve isteğe bağlı referansla PAID; ardından PREPARING ve DELIVERED.
8. Ayrı siparişte PAID → CANCELLED → REFUND_REQUIRED → gerçek iade sonrası REFUNDED doğrulayın.
9. İstek sırasında ağı kesin: başarı varsayılmamalı. Aynı anahtarla retry/sonuç sorgusu tek sipariş döndürmeli. Kabul/ödeme sırasında offline işlemler başarılı görünmemeli.
10. Hesap değişimi/çıkış sonrası eski satıcı ekranı, takip kayıtları, sepet ve checkout bilgileri temizlenmeli. Eski refresh çalışmamalı.
11. 360 ve 390 px dar ekran, büyük sistem yazı boyutu, klavye, geri tuşu, TalkBack, Somalice/İngilizce ve fotoğraf seçimi kontrolü yapın.

## İmzalı release

Application ID `so.onlinesuuq.app` olarak ayarlandı (marka: Onlinesuuq). İlk Play yüklemesinden önce hâlâ değiştirilebilir; yayımdan sonra **asla** değişmez — bu yüzden ilk yüklemeden önce son kez onaylayın. Geçici ikonları ve mağaza görsellerini son marka tasarımıyla değiştirin. Not: Android `namespace` hâlâ `so.dukaan.dukaan`'dır (Kotlin paket dizini); bu yalnızca R sınıfı paketidir ve Play kimliğini etkilemez, isterseniz sonra hizalayabilirsiniz.

```powershell
# Anahtarı repo DIŞINDA oluşturun. Şifreleri etkileşimli girin.
keytool -genkeypair -v -keystore C:\secure\dukaan-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

`mobile/android/key.properties` (Git dışında):

```properties
storeFile=C:/secure/dukaan-upload.jks
storePassword=YOUR_PRIVATE_PASSWORD
keyAlias=upload
keyPassword=YOUR_PRIVATE_PASSWORD
```

```powershell
Set-Location mobile
flutter analyze
flutter test
flutter build appbundle --release --dart-define=API_URL=https://YOUR_REAL_API_HOST/api/v1/
flutter build apk --release --dart-define=API_URL=https://YOUR_REAL_API_HOST/api/v1/
```

Gerçek kurulum adresi varsa ayrıca `--dart-define=INSTALL_URL=https://YOUR_REAL_INSTALL_URL` verin. Sahte Play Store bağlantısı yoktur. Varsayılan debug anahtarı release imzası olarak kullanılmaz; key.properties yoksa imzalı dağıtım hazırlanmamıştır. AAB tipik çıktı: `build/app/outputs/bundle/release/app-release.aab`. İmzayı ve backend HTTPS erişimini cihazda doğrulayın.

## Play yayını öncesi tamamlanacaklar

- Gerçek API domain’i, HTTPS, kalıcı görseller, SMTP, müşteri destek kanalı ve geri yüklenebilir yedek.
- Uygulama içinden hesap/veri silme isteği ve çalışan dış web silme isteği sayfası. **Uygulandı:** uygulama içinde *Maamul dukaankayga → Tirtir akoonka* (API `POST /api/v1/auth/delete/`, şifre onaylı); dış sayfa `GET /account-deletion/`. Kişisel kimlikler ve fotoğraflar silinir/anonimleştirilir, hesap pasifleştirilir; sipariş/denetim kayıtları kişisel bilgisiz saklanır. Saklama süresi (şablonda 7 yıl) ve destek e-postasını (`SUPPORT_EMAIL`) gerçek değerlerle güncelleyin.
- Gerçek işletme/uygulama adıyla gizlilik politikası; telefon, adres, e-posta, sipariş, fotoğraf ve token işlemenin açıklaması. **Uygulandı:** `GET /privacy/` (metin şablonu `backend/shop/templates/shop/privacy.html`). İşletme adı, adres ve yürürlük tarihini gerçek değerlerle değiştirin. Data Safety formunu gerçek davranışa göre doldurun. Play Console listelemesinde gizlilik politikası URL'si olarak bu sayfayı verin.
- Uygulama izinleri, hedef SDK, içerik derecelendirmesi, bölgesel dağıtım, test kanalı ve geliştirici hesap doğrulamasının güncel Play Console koşulları.
- Upload anahtarı, Play App Signing, anahtar yedekleme ve erişim sınırları. Özel anahtar/parolalar depoya veya APK kaynaklarına girmez.
- İki cihaz kabul testi, erişilebilirlik, düşük ağ/cihaz kapasitesi ve ana dili Somalice olan kullanıcı testi.

8 Ekim 2026 tarihinde kontrol edilen resmî kaynaklar: [Android release hazırlığı](https://developer.android.com/studio/publish/preparing), [uygulama imzalama](https://developer.android.com/studio/publish/app-signing), [Google Play hesap silme gereksinimleri](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en). Yayın tarihinde koşulları yeniden kontrol edin. Bu kontrol listesi tamamlanmadan “Play’e hazır” denmemelidir.
