// Runs on the Flutter test VM against a real local API, not an Android emulator.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dukaan/api.dart';

import '../test/app_test.dart' show MemorySecrets;

void main() {
  test(
    'two mobile API sessions: seller photo to guest checkout to delivery',
    () async {
      const base = String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://127.0.0.1:8000/api/v1/',
      );
      final seller = Api(base: base, secrets: MemorySecrets());
      final customer = Api(base: base, secrets: MemorySecrets());
      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final email = 'mobile-$suffix@example.invalid';
      const password = 'Mobile-test-only-Long-password-92!';
      await seller.call(
        'auth/register/',
        method: 'POST',
        authenticated: false,
        body: {
          'name': 'Mobile test seller',
          'email': email,
          'password': password,
          'password_repeat': password,
        },
      );
      await seller.login(email, password);
      final store = await seller.call(
        'seller/store/',
        method: 'POST',
        body: {
          'name': 'Mobile test shop',
          'slug': 'mobile-$suffix',
          'phone': '+252610000000',
          'city': 'Demo',
          'pickup_instructions': 'Demo point',
          'delivery_regions': ['Demo zone'],
          'delivery_fee': '2.00',
          'payment_provider': 'Other',
          'payment_account': 'TEST-NOT-PAYABLE',
          'payment_name': 'Demo',
        },
      );
      final product = await seller.call(
        'seller/products/',
        method: 'POST',
        body: {
          'name': 'Mobile test tea',
          'slug': 'tea',
          'price': '5.50',
          'stock': 3,
          'published': true,
        },
      );
      final dir = await Directory.systemTemp.createTemp('dukaan-upload-');
      try {
        final image = File('${dir.path}/test.png');
        await image.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEklEQVR4nGNkaGCAAyYEEx8HABoEAIgBCl8RAAAAAElFTkSuQmCC',
          ),
        );
        await seller.upload(
          'seller/products/${product['id']}/photos/',
          image.path,
        );
      } finally {
        await dir.delete(recursive: true);
      }
      await seller.call(
        'seller/store/publish/',
        method: 'POST',
        body: {'published': true},
      );
      final visible = await customer.call(
        'stores/${store['slug']}/products/',
        authenticated: false,
      );
      expect(visible['results'][0]['photos'].length, 1);
      final details = <String, dynamic>{
        'store': store['id'],
        'items': [
          {'product': product['id'], 'quantity': 2},
        ],
        'customer_name': 'Demo guest',
        'phone': '+252610000001',
        'fulfillment': 'pickup',
      };
      final quote = await customer.call(
        'quote/',
        method: 'POST',
        body: details,
        authenticated: false,
        anonymous: true,
      );
      expect(quote['total'], '11.00');
      final key =
          '00000000-0000-4000-8000-${suffix.substring(suffix.length - 12)}';
      final payload = {
        ...details,
        'quote': quote['quote'],
        'idempotency_key': key,
      };
      final first = await customer.call(
        'checkout/',
        method: 'POST',
        body: payload,
        authenticated: false,
        anonymous: true,
      );
      final retry = await customer.call(
        'checkout/',
        method: 'POST',
        body: payload,
        authenticated: false,
        anonymous: true,
      );
      expect(first['tracking_token'], retry['tracking_token']);
      final tracking = first['tracking_token'] as String;
      expect(first['order']['payment_instructions'], isNull);
      final orders = await seller.call('seller/orders/');
      final id = orders['results'][0]['id'];
      for (final action in ['ACCEPTED', 'PAID', 'PREPARING', 'DELIVERED']) {
        await seller.call(
          'seller/orders/$id/act/',
          method: 'POST',
          body: {
            'action': action,
            'confirmed': true,
            'reference': 'TEST-MANUAL',
          },
        );
      }
      final tracked = await customer.call(
        'tracking/',
        authenticated: false,
        tracking: tracking,
      );
      expect(tracked['status'], 'DELIVERED');
      expect(tracked['payment'], 'PAID');
      expect(tracked.containsKey('phone'), false);
      expect(tracked.containsKey('address'), false);
      final updated = await seller.call('seller/products/${product['id']}/');
      expect(updated['stock'], 1);
      await seller.logout();
      expect(await seller.secrets.read('refresh'), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
