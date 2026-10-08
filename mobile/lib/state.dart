import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'models.dart';
import 'brand.dart';

class AppState extends ChangeNotifier {
  final Api api;
  final SharedPreferences prefs;
  String language;
  String brand = defaultBrand;
  String? privacyUrl;
  String? accountDeletionUrl;
  Store? cartStore;
  final List<CartLine> cart = [];
  final Map<String, dynamic> cache = {};
  List<Map<String, dynamic>> tracking = [];
  Map<String, dynamic>? pending;
  bool get signedIn => api.access != null;

  AppState(this.api, this.prefs)
    : language = prefs.getString('language') ?? 'so';
  Future<void> init() async {
    api.language = language;
    final saved = prefs.getString('cart');
    if (saved != null) {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      if (data['store'] != null) {
        cartStore = Store.fromJson(data['store']);
      }
      for (final line in data['lines'] as List) {
        cart.add(
          CartLine(Product.fromJson(line['product']), line['quantity'] as int),
        );
      }
    }
    final cached = prefs.getString('publicCache');
    if (cached != null) {
      cache.addAll(jsonDecode(cached) as Map<String, dynamic>);
    }
    final savedTracking = await api.secrets.read('tracking');
    if (savedTracking != null) {
      tracking = List<Map<String, dynamic>>.from(jsonDecode(savedTracking));
    }
    final savedPending = await api.secrets.read('pending');
    if (savedPending != null) {
      pending = jsonDecode(savedPending) as Map<String, dynamic>;
    }
    try {
      await api.restore();
    } on ApiError {
      /* offline: no seller action succeeds locally */
    }
    try {
      final config =
          await api.call('config/', authenticated: false)
              as Map<String, dynamic>;
      brand = config['brand_name'] as String? ?? brand;
      privacyUrl = config['privacy_url'] as String?;
      accountDeletionUrl = config['account_deletion_url'] as String?;
    } on ApiError {
      /* retain placeholder */
    }
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    language = value;
    api.language = value;
    await prefs.setString('language', value);
    notifyListeners();
  }

  Future<void> saveCart() async {
    await prefs.setString(
      'cart',
      jsonEncode({
        'store': cartStore?.json,
        'lines': cart.map((l) => l.toJson()).toList(),
      }),
    );
    notifyListeners();
  }

  Future<bool> add(Store store, Product product, {bool replace = false}) async {
    if (product.stock <= 0) {
      return false;
    }
    if (cartStore != null && cartStore!.id != store.id && cart.isNotEmpty) {
      if (!replace) {
        return false;
      }
      cart.clear();
    }
    cartStore = store;
    final index = cart.indexWhere((l) => l.product.id == product.id);
    if (index >= 0) {
      if (cart[index].quantity >= product.stock) {
        return false;
      }
      cart[index].quantity++;
    } else {
      cart.add(CartLine(product, 1));
    }
    await saveCart();
    return true;
  }

  Future<void> remember(String key, dynamic data) async {
    cache[key] = data;
    if (cache.length > 20) {
      cache.remove(cache.keys.first);
    }
    await prefs.setString('publicCache', jsonEncode(cache));
  }

  Future<void> clearPrivate() async {
    tracking.clear();
    pending = null;
    cart.clear();
    cartStore = null;
    for (final key in ['tracking', 'pending', 'guest', 'guest_expiry']) {
      await api.secrets.delete(key);
    }
    await saveCart();
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await clearPrivate();
    await api.login(email, password);
    notifyListeners();
  }

  Future<void> signOut() async {
    await api.logout();
    await clearPrivate();
    notifyListeners();
  }

  Future<dynamic> submit(Map<String, dynamic> details, String quote) async {
    // Persist before sending. A timeout never generates a fresh key.
    pending ??= {
      ...details,
      'quote': quote,
      'idempotency_key': const Uuid().v4(),
    };
    await api.secrets.write('pending', jsonEncode(pending));
    final result = await api.call(
      'checkout/',
      method: 'POST',
      body: pending,
      authenticated: false,
      anonymous: true,
    );
    await completeCheckout(result as Map<String, dynamic>);
    return result;
  }

  Future<void> completeCheckout(Map<String, dynamic> result) async {
    final token = result['tracking_token'] as String;
    if (!tracking.any((t) => t['token'] == token)) {
      tracking.add({'token': token, 'reference': result['order']['reference']});
    }
    await api.secrets.write('tracking', jsonEncode(tracking));
    pending = null;
    await api.secrets.delete('pending');
    cart.clear();
    cartStore = null;
    await saveCart();
  }

  Future<dynamic> retryPending() async {
    if (pending == null) {
      return null;
    }
    try {
      final result = await api.call(
        'checkout/${pending!['idempotency_key']}/',
        authenticated: false,
        anonymous: true,
      );
      await completeCheckout(result as Map<String, dynamic>);
      return result;
    } on ApiError catch (e) {
      if (e.status != 404) {
        rethrow;
      }
      return submit(pending!, pending!['quote'] as String);
    }
  }

  Future<void> discardRejectedPending() async {
    // Only after the server confirms no order exists for this key.
    if (pending != null) {
      try {
        final result = await api.call(
          'checkout/${pending!['idempotency_key']}/',
          authenticated: false,
          anonymous: true,
        );
        await completeCheckout(result as Map<String, dynamic>);
        return;
      } on ApiError catch (e) {
        if (e.status != 404) {
          rethrow;
        }
      }
    }
    pending = null;
    await api.secrets.delete('pending');
    notifyListeners();
  }
}
