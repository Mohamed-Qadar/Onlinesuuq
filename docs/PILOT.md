# Yerel ve isteğe bağlı pilot

İlk hedef yereldir. Flutter/Django/PostgreSQL kodunun çalışması için ücretli API, SMS, WhatsApp API, AI, domain veya cloud satın alınması gerekmez. Elektrik, bilgisayar, internet ve isteğe bağlı mağaza geliştirici hesabı gibi maliyetlerin ücretsiz olduğu iddia edilmez.

Yerel pilotun sınırları:

- Bilgisayar uykuya girer/kapanırsa API ve DB kullanılamaz. Kesintisiz hizmet garantisi yoktur.
- Yerel ağ/USB dışında erişim yoktur; fiziksel telefon bağlantısı ve güvenlik duvarı yapılandırması gerekir.
- Kapasite disk/RAM/ağ ile sınırlıdır; PostgreSQL ve media yedeği kendiliğinden dış depoya alınmaz.
- Console e-posta gerçek mail teslimi değildir. Otomatik ödeme, kurye, bildirim veya operatör doğrulaması yoktur.
- Fotoğraflar kalıcı named volume veya yerel media klasöründedir; disk arızasında yedek yoksa kaybolabilir.
- Anonim oturum 30 gün, fiyat teklifi 15 dakika geçerlidir. Refresh 14 gün sonra tekrar giriş ister.

Bu teslimde herhangi bir “ücretsiz cloud paketi” önerilmedi, kaynak oluşturulmadı veya ödeme yöntemi eklenmedi. Bu nedenle doğrulanmamış cloud ücretsizliği, kota veya uptime vaadi yoktur.

İsteğe bağlı cloud pilotu için önce somut sağlayıcının resmî koşullarını seçim tarihinde kontrol edin: uyku/soğuk başlangıç, CPU/RAM, aylık trafik, kalıcı disk ve nesne deposu, veritabanı boyutu/bağlantı sınırı, otomatik yedek ve geri yükleme, süre sonu/veri silme, kredi kartı/otomatik ücretlendirme, bölge ve veri işleme koşulları. Bu tablo ve maliyet onayı olmadan kaynak satın almayın.

Tek Django monolith + PostgreSQL yeterlidir. Production için uygun WSGI sunucusu, TLS reverse proxy, doğru ALLOWED_HOSTS ve proxy güveni, güvenli media origin’i, kalıcı dosya deposu, düzenli yedek/geri yükleme, SMTP ve hata izleme hazırlanmalıdır. Compose’daki runserver internete açık production için kullanılmaz.
