# API v1

API kökü `/api/v1/`, makine tarafından okunabilir sözleşme `openapi.yaml`, çalışan şema `/api/v1/schema/`, Swagger `/api/v1/docs/`.

JSON isteklerinde `Content-Type: application/json`, dil için `Accept-Language: so` veya `en`. Para değerleri iki ondalıklı string’dir. Liste yanıtları `{count, next, previous, results}` biçiminde, sayfa başına 24 kayıt döner. `next` URL’si takip edilmelidir. Hatalar `{errors: ...}` zarfındadır. 400 doğrulama, 401 oturum, 403 yetki, 404 görünmeyen/bulunamayan nesne, 429 hız sınırıdır.

## Hesap ve yetki

`POST auth/register/`: name, email, password, password_repeat. `POST auth/login/`: email/password → access/refresh. E-posta büyük/küçük harfe duyarsızdır. Satıcı uçlarında `Authorization: Bearer ACCESS` gerekir. `POST auth/refresh/` refresh’i tek kullanımda döndürür; yeni refresh güvenli depolamada eskisinin yerini almalıdır. `POST auth/logout/` refresh gönderir; sunucu iptali başarılı olmadan mobil çıkış başarılı sayılmaz.

`POST auth/password/`: old_password/password. `POST auth/reset/`: email, her durumda 204; maildeki uid/token `POST auth/reset/confirm/` ile yeni password yanında gönderilir. Debug console mail kodlarını geliştirme konsolunda gösterir; production console backend kullanmayın. API mail/telefon doğrulanmış iddiasında bulunmaz.

## Mağaza ve ürünler

- `GET stores/?q=kod-veya-ad`: yalnız satışa açık eşleşmeleri arar; boş arama marketplace listesi açmaz.
- `GET stores/{slug}/`, `GET stores/{slug}/products/?q=...&category=...`, `GET products/{id}/`.
- `GET/POST/PATCH seller/store/`: kendi mağazası; POST mağazayı taslak açar. `POST seller/store/publish/`: `{published: true}`.
- `POST seller/store/logo/`: multipart `image`.
- `GET/POST seller/products/`, `GET/PATCH/DELETE seller/products/{id}/`. DELETE arşivler, fiziksel silmez.
- Stok PATCH için `expected_updated_at` alanına en son GET’in `updated_at` değerini ekleyin. Çakışmada formu yeniden yükleyin; kör retry ile eski stok yazmayın.
- `POST seller/products/{id}/photos/`: multipart image. `DELETE seller/products/{id}/photos/{photo_id}/`.
- `GET seller/dashboard/`, `GET seller/orders/?status=NEW&from=2026-10-01&to=2026-10-08`, `GET seller/orders/{id}/`.
- `POST reports/`: store, isteğe bağlı product, reason. Ürün belirtilirse mağazayla eşleşmelidir.

Sunucu owner, suspended, moderated, staff, ödeme ve toplam alanlarına güvenmez. Satıcıya ait olmayan ID’ler 404 verir. Admin yalnız platform yönetimi içindir.

## Güvenilir checkout sırası

1. `POST guest/` → rastgele `token`, `expires_at`. Token’ı cihazın güvenli depolamasında tutun. Aşağıdaki uçlarda `X-Guest-Token` başlığına koyun.
2. `POST quote/` ile müşteri ve sepet detaylarını gönderin:

```json
{
  "store": 1,
  "items": [{"product": 1, "quantity": 2}],
  "customer_name": "Demo customer",
  "phone": "+252610000000",
  "fulfillment": "pickup",
  "region": "",
  "address": "",
  "note": ""
}
```

3. Sunucu ürün satırlarını, delivery_fee/total ve imzalı `quote` döndürür. **Toplamı gösterip açık onay alın.** NEW sipariş stok rezervasyonu değildir ve müşteri henüz ödeme yapmamalıdır.
4. Aynı detaylara `quote` ve UUID `idempotency_key` ekleyerek `POST checkout/` yapın. Anahtarı **istekten önce** güvenli kaydedin. Başarı `tracking_token` ve kişisel veri içermeyen `order` döndürür.
5. Timeout’ta yeni anahtar üretmeyin. `GET checkout/{idempotency_key}/` ile aynı anonim oturumdan sonucu sorgulayın. 404 ise aynı POST’u tekrar gönderin. 400 fiyat değişikliği/teklif süresi ise önce anahtar için sonuç olmadığını doğrulayıp yeni fiyatı gösterin ve yeniden onay alın.
6. Takip `GET tracking/` + `X-Tracking-Token: TOKEN` ile yapılır. URL/query içine sır yazmayın. Tahmin edilebilir referansla takip yapılamaz.

Bir istek başka mağazanın ürününü içerirse reddedilir. İstemci toplamı veya fiyatı gönderse de hesaba katılmaz. Adet 1–999, en fazla 50 farklı kalemdir; toplam 9.999.999.999,99 USD sınırını aşamaz. Teslimat seçilirse mağazanın bölge listesi ve açık adres gerekir. Pickup ücreti sıfırdır. Quote 15 dakika, anonim oturum 30 gün geçerlidir. Süresi dolan anonim token yalnız kendi mevcut checkout sonucunu geri almak için kullanılabilir; yeni quote/checkout yapamaz. Mobil istemci yeni teklif öncesi süresi dolan oturumu yeniler. Sonucu belirsiz checkout varken oturum anahtarını sessizce yenilemeyin.

## Sipariş/ödeme işlemleri

`POST seller/orders/{id}/act/`:

```json
{"action": "PAID", "confirmed": true, "reference": "isteğe bağlı manuel referans"}
```

`NEW → ACCEPTED → PREPARING → DELIVERED`; ilk üç durumdan CANCELLED. Kabul/iptal tekrarları zararsızdır. `PAID` yalnız ACCEPTED/PREPARING/DELIVERED + UNPAID durumunda ve açık confirmed=true ile mümkündür. DELIVERED ödeme durumunu değiştirmez. Ödenmiş iptal REFUND_REQUIRED olur, gerçek iade sonrası REFUNDED yapılır. API para transfer etmez.

`CORRECT_PAYMENT` yalnız superuser’ın gerekçeli işlemidir; satıcı API sorguları diğer satıcı siparişlerini admin için bile açmaz. Platform yöneticisi Admin sipariş formundaki gerekçe alanını kullanır. Olay kayıtları değiştirilemez. Admin sipariş durum/stok alanları readonly, durum eylemleri ortak servise gider.

## Hız sınırı ve dağıtım

IP başına saatlik: kayıt 10, giriş 30, refresh 180, reset 5, reset onay 20, anonim oturum 30, quote 120, checkout 60, takip/sonuç 180, şikâyet 10. Sayaçlar PostgreSQL’de atomik güncellenir; worker başına ayrı bellek sayacı yoktur. NAT arkasındaki çok kullanıcı aynı sınırı paylaşır. Pilot verisine göre ayarlayın. Güvenilir proxy ve gerçek istemci IP aktarımı production öncesi yapılandırılmalıdır.

Gizli başlıklar, şifreler, müşteri adresleri ve gövdeleri loglamayın. API `no-store` yanıtlar üretir; yalnız uygulama açıkça halka açık ürün yanıtlarını çevrimdışı cache eder. Media ve public cache’de eski içerik kalabilir; yeni sipariş/kabul mutlaka sunucuda tekrar kontrol edilir.
