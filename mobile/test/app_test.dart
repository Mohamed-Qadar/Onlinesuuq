import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dukaan/api.dart';
import 'package:dukaan/state.dart';
import 'package:dukaan/models.dart';
import 'package:dukaan/main.dart';
import 'package:dukaan/l10n.dart';

class MemorySecrets implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Map<String, dynamic> storeJson(int id) => {
  'id': id,
  'name': 'Demo Shop $id',
  'slug': 'demo-$id',
  'description': 'Independent shop',
  'phone': '+252610000000',
  'city': 'Demo',
  'pickup_instructions': 'Point',
  'delivery_fee': '2.00',
  'delivery_regions': ['Zone'],
};
Map<String, dynamic> productJson(int id, int store, {int stock = 3}) => {
  'id': id,
  'store': store,
  'name': 'Tea',
  'price': '5.00',
  'stock': stock,
  'description': 'A small pack',
  'category': 'Food',
  'photos': [],
  'published': true,
  'archived': false,
};

Future<AppState> appFor(
  Future<http.Response> Function(http.Request) handler,
) async {
  SharedPreferences.setMockInitialValues({});
  return AppState(
    Api(
      base: 'http://localhost/api/v1/',
      client: MockClient(handler),
      secrets: MemorySecrets(),
    ),
    await SharedPreferences.getInstance(),
  );
}

http.Response jsonResponse(dynamic body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppStrings.delegate.load(const Locale('so'));
    await AppStrings.delegate.load(const Locale('en'));
  });
  test(
    'cart explicitly requires replacing another shop and persists draft',
    () async {
      final app = await appFor((_) async => jsonResponse({}));
      final a = Store.fromJson(storeJson(1)), b = Store.fromJson(storeJson(2));
      final p = Product.fromJson(productJson(1, 1)),
          q = Product.fromJson(productJson(2, 2));
      expect(await app.add(a, p), true);
      expect(await app.add(b, q), false);
      expect(app.cart.first.product.id, 1);
      expect(await app.add(b, q, replace: true), true);
      expect(app.cart.length, 1);
      expect(app.cartStore!.id, 2);
      expect(app.prefs.getString('cart'), contains('Demo Shop 2'));
      expect(
        await app.add(b, Product.fromJson(productJson(3, 2, stock: 0))),
        false,
      );
    },
  );

  test('login, single refresh rotation and retry protected call', () async {
    int refreshes = 0;
    final app = await appFor((req) async {
      if (req.url.path.endsWith('/login/')) {
        return jsonResponse({'access': 'old', 'refresh': 'refresh-1'});
      }
      if (req.url.path.endsWith('/refresh/')) {
        refreshes++;
        expect(jsonDecode(req.body)['refresh'], 'refresh-1');
        return jsonResponse({'access': 'new', 'refresh': 'refresh-2'});
      }
      return req.headers['Authorization'] == 'Bearer new'
          ? jsonResponse({'ok': true})
          : jsonResponse({'errors': 'expired'}, 401);
    });
    await app.api.login('demo@example.invalid', 'secret');
    expect((await app.api.call('seller/store/'))['ok'], true);
    expect(refreshes, 1);
    expect(await app.api.secrets.read('refresh'), 'refresh-2');
    expect(app.prefs.getKeys(), isNot(contains('refresh')));
  });

  test('account switch removes prior private state', () async {
    final app = await appFor(
      (_) async => jsonResponse({'access': 'new', 'refresh': 'new-refresh'}),
    );
    app.tracking.add({'token': 'private', 'reference': 'old'});
    app.pending = {'customer_name': 'old'};
    await app.api.secrets.write('tracking', 'private');
    await app.api.secrets.write('guest', 'old-guest');
    await app.add(
      Store.fromJson(storeJson(1)),
      Product.fromJson(productJson(1, 1)),
    );
    await app.signIn('new@example.invalid', 'password');
    expect(app.tracking, isEmpty);
    expect(app.pending, isNull);
    expect(app.cart, isEmpty);
    expect(await app.api.secrets.read('tracking'), isNull);
    expect(await app.api.secrets.read('guest'), isNull);
  });

  test(
    'timeout keeps same checkout key; confirmed retry stores tracking securely',
    () async {
      final sent = <String>[];
      int submits = 0;
      final app = await appFor((req) async {
        if (req.url.path.endsWith('/guest/')) {
          return jsonResponse({'token': 'guest'});
        }
        if (req.method == 'GET') {
          return jsonResponse({'errors': 'missing'}, 404);
        }
        final data = jsonDecode(req.body);
        sent.add(data['idempotency_key']);
        submits++;
        if (submits == 1) {
          throw TimeoutException('offline');
        }
        return jsonResponse({
          'tracking_token': 'tracking-private',
          'order': {'reference': 'reference'},
        }, 201);
      });
      await expectLater(
        app.submit({'store': 1, 'items': []}, 'quote'),
        throwsA(isA<ApiError>()),
      );
      expect(app.pending, isNotNull);
      expect(app.tracking, isEmpty);
      expect(await app.api.secrets.read('pending'), contains(sent.first));
      await app.retryPending();
      expect(sent[0], sent[1]);
      expect(app.pending, isNull);
      expect(
        await app.api.secrets.read('tracking'),
        contains('tracking-private'),
      );
    },
  );

  test('lost response recovers existing result without resubmission', () async {
    int posts = 0;
    final app = await appFor((req) async {
      if (req.url.path.endsWith('/guest/')) {
        return jsonResponse({'token': 'guest'});
      }
      if (req.method == 'POST') {
        posts++;
        throw TimeoutException('lost response');
      }
      return jsonResponse({
        'tracking_token': 'saved',
        'order': {'reference': 'reference'},
      });
    });
    await expectLater(
      app.submit({'store': 1}, 'quote'),
      throwsA(isA<ApiError>()),
    );
    await app.retryPending();
    expect(posts, 1);
    expect(app.tracking.single['token'], 'saved');
  });

  test('offline logout does not pretend server revocation succeeded', () async {
    final app = await appFor((_) async => throw TimeoutException('offline'));
    app.api.access = 'access';
    await app.api.secrets.write('refresh', 'refresh');
    await expectLater(app.signOut(), throwsA(isA<ApiError>()));
    expect(await app.api.secrets.read('refresh'), 'refresh');
  });

  test('tracking token only sent in header', () async {
    final app = await appFor((req) async {
      expect(req.headers['X-Tracking-Token'], 'private-token');
      expect(req.url.toString(), isNot(contains('private-token')));
      return jsonResponse({'status': 'NEW'});
    });
    await app.api.call(
      'tracking/',
      authenticated: false,
      tracking: 'private-token',
    );
  });

  testWidgets('Somali home and language switch fit a 360px phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await appFor(
      (_) async => jsonResponse({'results': [], 'next': null}),
    );
    await tester.pumpWidget(DukaanApp(app));
    await tester.pumpAndSettle();
    expect(find.text('Dukaankaaga, gacantaada.'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Your shop, in your hands.'), findsOneWidget);
    expect(app.language, 'en');
    expect(tester.takeException(), isNull);
  });

  testWidgets('search opens native shop and product screen', (tester) async {
    final app = await appFor((req) async {
      if (req.url.path.contains('/products/')) {
        return jsonResponse({
          'results': [productJson(1, 1)],
          'next': null,
        });
      }
      return jsonResponse({
        'results': [storeJson(1)],
        'next': null,
      });
    });
    app.language = 'en';
    await tester.pumpWidget(DukaanApp(app));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'demo-1');
    await tester.tap(find.text('Find shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo Shop 1'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Tea'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Tea'));
    await tester.pumpAndSettle();
    expect(find.text('Add to bag'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
