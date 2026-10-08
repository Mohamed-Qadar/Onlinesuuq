import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'state.dart';
import 'models.dart';
import 'l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(Api(), await SharedPreferences.getInstance());
  await state.init();
  runApp(DukaanApp(state));
}

class DukaanApp extends StatelessWidget {
  final AppState state;
  const DukaanApp(this.state, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      title: state.brand,
      debugShowCheckedModeBanner: false,
      locale: Locale(state.language),
      supportedLocales: const [Locale('so'), Locale('en')],
      localizationsDelegates: const [
        AppStrings.delegate,
        MaterialFallback(),
        WidgetsFallback(),
        CupertinoFallback(),
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff16735e)),
        scaffoldBackgroundColor: const Color(0xfff7f9f8),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      home: HomeScreen(state),
    ),
  );
}

String tr(BuildContext context, String key) => AppStrings.of(context).text(key);
Future<T?> open<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
// Opens a public legal page (privacy / account deletion) in the device browser.
Future<void> openUrl(BuildContext context, String? url) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = tr(context, 'linkUnavailable');
  final uri = url == null ? null : Uri.tryParse(url);
  final ok =
      uri != null &&
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
Widget gap() => const SizedBox(height: 16);
Widget note(BuildContext context, String key) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Text(
    tr(context, key),
    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
  ),
);
Widget money(String amount) => Text(
  '\$$amount USD',
  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
);

Future<bool> confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'confirm')),
        content: Text(tr(ctx, message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(ctx, 'back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ctx, 'confirm')),
          ),
        ],
      ),
    ) ??
    false;

abstract class ScreenState<T extends StatefulWidget> extends State<T> {
  bool busy = false;
  String? error;
  Future<void> perform(Future<void> Function() action) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && context.mounted) {
        setState(() => error = e is ApiError ? e.message : 'unexpectedError');
      }
    } finally {
      if (mounted && context.mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget errors() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            tr(context, error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
  Widget button(String key, Future<void> Function() action, {IconData? icon}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: FilledButton.icon(
          onPressed: busy ? null : () => perform(action),
          icon: Icon(icon ?? Icons.arrow_forward, size: 20),
          label: Text(tr(context, key)),
        ),
      );
}

class HomeScreen extends StatefulWidget {
  final AppState app;
  const HomeScreen(this.app, {super.key});
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends ScreenState<HomeScreen> {
  final query = TextEditingController();
  List<Store> stores = [];
  String? next;
  bool searched = false;
  bool cached = false;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search({bool more = false}) async {
    final path = more
        ? next!.replaceFirst(widget.app.api.base, '')
        : 'stores/?q=${Uri.encodeComponent(query.text.trim())}';
    dynamic data;
    try {
      data = await widget.app.api.call(path, authenticated: false);
      await widget.app.remember(path, data);
      cached = false;
    } on ApiError catch (e) {
      if (e.status != 0 || !widget.app.cache.containsKey(path)) {
        rethrow;
      }
      data = widget.app.cache[path];
      cached = true;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      final found = (data['results'] as List)
          .map((e) => Store.fromJson(e))
          .toList();
      stores = more ? [...stores, ...found] : found;
      next = data['next'] as String?;
      searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(
        title: Text(app.brand),
        actions: [
          TextButton(
            onPressed: () =>
                app.setLanguage(app.language == 'so' ? 'en' : 'so'),
            child: Text(app.language == 'so' ? 'English' : 'Soomaali'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(
            Icons.storefront_rounded,
            size: 66,
            color: Color(0xff16735e),
          ),
          gap(),
          Text(
            tr(context, 'welcome'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          note(context, 'intro'),
          TextField(
            controller: query,
            decoration: InputDecoration(
              labelText: tr(context, 'storeSearch'),
              prefixIcon: const Icon(Icons.search),
            ),
            onSubmitted: (_) => perform(search),
          ),
          button('findStore', search, icon: Icons.search),
          errors(),
          if (cached) note(context, 'cachedWarning'),
          for (final store in stores)
            Card(
              child: ListTile(
                title: Text(store.name),
                subtitle: Text('${store.slug} · ${store.city}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(context, StoreScreen(app, store)),
              ),
            ),
          if (next != null) button('more', () => search(more: true)),
          if (searched && stores.isEmpty) note(context, 'noStores'),
          gap(),
          const Divider(),
          gap(),
          FilledButton.tonalIcon(
            onPressed: () => open(
              context,
              app.signedIn ? SellerScreen(app) : AuthScreen(app),
            ),
            icon: const Icon(Icons.store),
            label: Text(
              tr(context, app.signedIn ? 'manageStore' : 'openStore'),
            ),
          ),
          gap(),
          OutlinedButton.icon(
            onPressed: () => open(context, CartScreen(app)),
            icon: const Icon(Icons.shopping_bag_outlined),
            label: Text('${tr(context, 'cart')} (${app.cart.length})'),
          ),
          OutlinedButton.icon(
            onPressed: () => open(context, TrackingList(app)),
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(tr(context, 'myOrders')),
          ),
          note(context, 'manualPaymentNotice'),
        ],
      ),
    );
  }
}

class StoreScreen extends StatefulWidget {
  final AppState app;
  final Store store;
  const StoreScreen(this.app, this.store, {super.key});
  @override
  State<StoreScreen> createState() => _StoreState();
}

class _StoreState extends ScreenState<StoreScreen> {
  List<Product> products = [];
  String? next;
  bool cached = false;
  final query = TextEditingController(), category = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => perform(load));
  }

  @override
  void dispose() {
    query.dispose();
    category.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final path = more
        ? next!.replaceFirst(widget.app.api.base, '')
        : 'stores/${widget.store.slug}/products/?q=${Uri.encodeComponent(query.text)}&category=${Uri.encodeComponent(category.text)}';
    dynamic data;
    try {
      data = await widget.app.api.call(path, authenticated: false);
      await widget.app.remember(path, data);
      cached = false;
    } on ApiError catch (e) {
      if (e.status != 0 || !widget.app.cache.containsKey(path)) {
        rethrow;
      }
      data = widget.app.cache[path];
      cached = true;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      final found = (data['results'] as List)
          .map((p) => Product.fromJson(p))
          .toList();
      products = more ? [...products, ...found] : found;
      next = data['next'] as String?;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.store.name),
      actions: [
        IconButton(
          tooltip: tr(context, 'cart'),
          onPressed: () => open(context, CartScreen(widget.app)),
          icon: const Icon(Icons.shopping_bag_outlined),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () => perform(load),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.store.description),
          Text('${widget.store.city} · ${widget.store.phone}'),
          Text('${tr(context, 'regions')}: ${widget.store.regions.join(', ')}'),
          Text(widget.store.pickup),
          Text('${tr(context, 'deliveryFee')}: \$${widget.store.deliveryFee}'),
          TextButton.icon(
            onPressed: () => shareStore(widget.store),
            icon: const Icon(Icons.share_outlined),
            label: Text(tr(context, 'shareStore')),
          ),
          TextField(
            controller: query,
            decoration: InputDecoration(
              labelText: tr(context, 'searchProducts'),
            ),
          ),
          gap(),
          TextField(
            controller: category,
            decoration: InputDecoration(labelText: tr(context, 'category')),
          ),
          button('search', load, icon: Icons.search),
          errors(),
          if (cached) note(context, 'cachedWarning'),
          if (!busy && products.isEmpty) note(context, 'noProducts'),
          for (final p in products)
            ProductTile(
              p,
              onTap: () =>
                  open(context, ProductScreen(widget.app, widget.store, p)),
            ),
          if (next != null) button('more', () => load(more: true)),
          TextButton(
            onPressed: () =>
                open(context, ReportScreen(widget.app, widget.store)),
            child: Text(tr(context, 'report')),
          ),
        ],
      ),
    ),
  );
}

Future<void> shareStore(Store store) async {
  const installUrl = String.fromEnvironment('INSTALL_URL');
  await SharePlus.instance.share(
    ShareParams(
      text:
          '${store.name}\n${store.slug}${installUrl.isEmpty ? '' : '\n$installUrl'}',
    ),
  );
}

class ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const ProductTile(this.product, {required this.onTap, super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(12),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: product.images.isEmpty
            ? const SizedBox(
                width: 56,
                height: 56,
                child: Icon(Icons.inventory_2_outlined),
              )
            : Image.network(
                product.images.first,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                cacheWidth: 160,
                errorBuilder: (_, e, stack) => const SizedBox(
                  width: 56,
                  child: Icon(Icons.image_not_supported_outlined),
                ),
              ),
      ),
      title: Text(product.name),
      subtitle: Text(
        '\$${product.price} USD\n${product.stock == 0 ? tr(context, 'soldOut') : product.category}',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class ProductScreen extends StatefulWidget {
  final AppState app;
  final Store store;
  final Product product;
  const ProductScreen(this.app, this.store, this.product, {super.key});
  @override
  State<ProductScreen> createState() => _ProductState();
}

class _ProductState extends ScreenState<ProductScreen> {
  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final image in p.images)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  image,
                  height: 230,
                  fit: BoxFit.contain,
                  cacheWidth: 700,
                  errorBuilder: (_, e, stack) => const SizedBox(
                    height: 100,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          Text(p.name, style: Theme.of(context).textTheme.headlineSmall),
          gap(),
          money(p.price),
          gap(),
          Text(p.description),
          note(context, 'stockFinalAtAcceptance'),
          errors(),
          if (p.stock == 0)
            note(context, 'soldOut')
          else
            button('addToCart', () async {
              final app = widget.app;
              bool replace = false;
              if (app.cart.isNotEmpty && app.cartStore?.id != widget.store.id) {
                replace = await confirm(context, 'replaceCart');
                if (!replace) {
                  return;
                }
              }
              final added = await app.add(widget.store, p, replace: replace);
              if (mounted && context.mounted) {
                if (added) {
                  await open(context, CartScreen(app));
                } else {
                  setState(() => error = 'stockLimit');
                }
              }
            }, icon: Icons.add_shopping_cart),
          TextButton(
            onPressed: () => open(
              context,
              ReportScreen(widget.app, widget.store, product: p),
            ),
            child: Text(tr(context, 'report')),
          ),
        ],
      ),
    );
  }
}

class CartScreen extends StatefulWidget {
  final AppState app;
  const CartScreen(this.app, {super.key});
  @override
  State<CartScreen> createState() => _CartState();
}

class _CartState extends ScreenState<CartScreen> {
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'cart'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          errors(),
          if (app.cart.isEmpty) note(context, 'emptyCart'),
          if (app.cartStore != null)
            Text(
              app.cartStore!.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          for (final line in app.cart.toList())
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.product.name),
                    Text('\$${line.product.price} USD'),
                    Row(
                      children: [
                        IconButton(
                          tooltip: tr(context, 'remove'),
                          onPressed: () async {
                            if (line.quantity == 1) {
                              app.cart.remove(line);
                            } else {
                              line.quantity--;
                            }
                            await app.saveCart();
                            if (mounted && context.mounted) {
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.remove),
                        ),
                        Text('${line.quantity}'),
                        IconButton(
                          tooltip: tr(context, 'add'),
                          onPressed: line.quantity >= line.product.stock
                              ? null
                              : () async {
                                  line.quantity++;
                                  await app.saveCart();
                                  if (mounted && context.mounted) {
                                    setState(() {});
                                  }
                                },
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          note(context, 'cartEstimate'),
          if (app.cart.isNotEmpty)
            button('checkout', () async {
              await open(context, CheckoutScreen(app));
              if (mounted && context.mounted) {
                setState(() {});
              }
            }),
          if (app.pending != null) note(context, 'pendingCheckout'),
        ],
      ),
    );
  }
}

class CheckoutScreen extends StatefulWidget {
  final AppState app;
  const CheckoutScreen(this.app, {super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutState();
}

class _CheckoutState extends ScreenState<CheckoutScreen> {
  final fields = <String, TextEditingController>{
    for (final key in ['customer_name', 'phone', 'address', 'note'])
      key: TextEditingController(),
  };
  String fulfillment = 'pickup', region = '';
  Map<String, dynamic>? quote, details;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void invalidate() => setState(() {
    quote = null;
    details = null;
  });
  Future<void> showResult(dynamic result) async {
    if (mounted && result != null) {
      await open(
        context,
        OrderScreen(widget.app, tracking: result['tracking_token'] as String),
      );
      if (mounted && context.mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    if (app.pending != null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr(context, 'checkout'))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            note(context, 'pendingCheckout'),
            errors(),
            button(
              'checkRetry',
              () async => showResult(await app.retryPending()),
            ),
            button('reviewAgain', () async {
              await app.discardRejectedPending();
              if (mounted && context.mounted) {
                setState(() {});
              }
            }),
          ],
        ),
      );
    }
    final store = app.cartStore;
    if (store == null || app.cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(tr(context, 'emptyCart'))),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'checkout'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          note(context, 'acceptanceNotice'),
          note(context, 'waitToPay'),
          for (final key in ['customer_name', 'phone'])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: fields[key],
                onChanged: (_) => invalidate(),
                keyboardType: key == 'phone'
                    ? TextInputType.phone
                    : TextInputType.name,
                decoration: InputDecoration(
                  labelText: tr(context, key),
                  hintText: key == 'phone' ? '+252612345678' : null,
                ),
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: fulfillment,
            decoration: InputDecoration(labelText: tr(context, 'fulfillment')),
            items: [
              DropdownMenuItem(
                value: 'pickup',
                child: Text(tr(context, 'pickup')),
              ),
              if (store.regions.isNotEmpty)
                DropdownMenuItem(
                  value: 'delivery',
                  child: Text(tr(context, 'delivery')),
                ),
            ],
            onChanged: (v) {
              fulfillment = v!;
              invalidate();
            },
          ),
          gap(),
          if (fulfillment == 'delivery') ...[
            DropdownButtonFormField<String>(
              initialValue: region.isEmpty ? null : region,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr(context, 'region')),
              items: store.regions
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) {
                region = v!;
                invalidate();
              },
            ),
            gap(),
            TextField(
              controller: fields['address'],
              onChanged: (_) => invalidate(),
              decoration: InputDecoration(labelText: tr(context, 'address')),
            ),
            gap(),
          ],
          TextField(
            controller: fields['note'],
            onChanged: (_) => invalidate(),
            decoration: InputDecoration(labelText: tr(context, 'note')),
          ),
          errors(),
          button('reviewTotal', () async {
            await app.api.freshGuestForQuote();
            details = CheckoutRequest(store.id, app.cart, {
              for (final e in fields.entries) e.key: e.value.text.trim(),
              'fulfillment': fulfillment,
              'region': fulfillment == 'delivery' ? region : '',
              'address': fulfillment == 'delivery'
                  ? fields['address']!.text.trim()
                  : '',
            }).toJson();
            final result = await app.api.call(
              'quote/',
              method: 'POST',
              body: details,
              authenticated: false,
              anonymous: true,
            );
            setState(() => quote = Map<String, dynamic>.from(result));
          }),
          if (quote != null) ...[
            const Divider(),
            for (final line in quote!['lines'])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${line['name']} × ${line['quantity']}'),
                subtitle: Text('\$${line['unit_price']} USD'),
                trailing: Text('\$${line['line_total']}'),
              ),
            Text('${tr(context, 'deliveryFee')}: \$${quote!['delivery_fee']}'),
            gap(),
            money(quote!['total'] as String),
            button('confirmOrder', () async {
              await showResult(
                await app.submit(details!, quote!['quote'] as String),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class TrackingList extends StatefulWidget {
  final AppState app;
  const TrackingList(this.app, {super.key});
  @override
  State<TrackingList> createState() => _TrackingListState();
}

class _TrackingListState extends ScreenState<TrackingList> {
  final token = TextEditingController();
  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'myOrders'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.app.pending != null)
          button('checkRetry', () async {
            await open(context, CheckoutScreen(widget.app));
            if (mounted && context.mounted) {
              setState(() {});
            }
          }),
        if (widget.app.tracking.isEmpty) note(context, 'noOrders'),
        for (final item in widget.app.tracking.reversed)
          Card(
            child: ListTile(
              title: Text((item['reference'] as String).substring(0, 10)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(
                context,
                OrderScreen(widget.app, tracking: item['token'] as String),
              ),
            ),
          ),
        gap(),
        TextField(
          controller: token,
          obscureText: true,
          decoration: InputDecoration(labelText: tr(context, 'trackingToken')),
        ),
        button('trackOrder', () async {
          if (token.text.trim().isNotEmpty) {
            await open(
              context,
              OrderScreen(widget.app, tracking: token.text.trim()),
            );
          }
        }),
        note(context, 'trackingPrivacy'),
        errors(),
      ],
    ),
  );
}

class OrderScreen extends StatefulWidget {
  final AppState app;
  final int? id;
  final String? tracking;
  const OrderScreen(this.app, {this.id, this.tracking, super.key});
  @override
  State<OrderScreen> createState() => _OrderState();
}

class _OrderState extends ScreenState<OrderScreen> {
  OrderSummary? order;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => perform(load));
  }

  Future<void> load() async {
    final data = widget.id != null
        ? await widget.app.api.call('seller/orders/${widget.id}/')
        : await widget.app.api.call(
            'tracking/',
            authenticated: false,
            tracking: widget.tracking,
          );
    if (mounted && context.mounted) {
      setState(() => order = OrderSummary.fromJson(data));
    }
  }

  Future<void> act(String action) async {
    if (!await confirm(
      context,
      ['PAID', 'REFUNDED'].contains(action) ? 'verifyPayment' : 'confirmAction',
    )) {
      return;
    }
    String reference = '';
    if (['PAID', 'REFUNDED'].contains(action) && mounted) {
      final controller = TextEditingController();
      final input = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, 'paymentReference')),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: tr(ctx, 'optionalReference'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr(ctx, 'back')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(tr(ctx, 'confirm')),
            ),
          ],
        ),
      );
      if (input == null) {
        return;
      }
      reference = input;
      // Controller lives until the dialog has finished its closing animation.
    }
    await widget.app.api.call(
      'seller/orders/${widget.id}/act/',
      method: 'POST',
      body: {'action': action, 'confirmed': true, 'reference': reference},
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'order')),
        actions: [
          IconButton(
            tooltip: tr(context, 'refresh'),
            onPressed: busy ? null : () => perform(load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          errors(),
          if (o != null) ...[
            SelectableText(
              o.reference,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            gap(),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(tr(context, o.status))),
                Chip(label: Text(tr(context, o.payment))),
              ],
            ),
            if (o.status == 'NEW') ...[
              note(context, 'acceptanceNotice'),
              note(context, 'waitToPay'),
            ],
            if (o.payment == 'REFUND_REQUIRED') note(context, 'refundNotice'),
            for (final line in o.json['lines'])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${line['name']} × ${line['quantity']}'),
                trailing: Text('\$${line['line_total']}'),
              ),
            Text('${tr(context, 'deliveryFee')}: \$${o.json['delivery_fee']}'),
            gap(),
            money(o.total),
            if (o.json['payment_instructions'] != null &&
                ['ACCEPTED', 'PREPARING', 'DELIVERED'].contains(o.status)) ...[
              note(context, 'payDirect'),
              SelectableText(
                (o.json['payment_instructions'] as Map).values.join('\n'),
              ),
            ],
            if (widget.id == null && widget.tracking != null) ...[
              gap(),
              ExpansionTile(
                title: Text(tr(context, 'trackingToken')),
                children: [SelectableText(widget.tracking!)],
              ),
              note(context, 'trackingPrivacy'),
            ],
            if (widget.id != null) ...[
              const Divider(),
              Text('${o.json['customer_name']} · ${o.json['phone']}'),
              Text(
                '${tr(context, o.json['fulfillment'])}\n${o.json['region']}\n${o.json['address']}\n${o.json['note']}',
              ),
              if (o.status == 'NEW') button('ACCEPTED', () => act('ACCEPTED')),
              if (o.status == 'ACCEPTED')
                button('PREPARING', () => act('PREPARING')),
              if (o.status == 'PREPARING')
                button('DELIVERED', () => act('DELIVERED')),
              if (['NEW', 'ACCEPTED', 'PREPARING'].contains(o.status))
                button('CANCELLED', () => act('CANCELLED')),
              if (o.payment == 'UNPAID' &&
                  ['ACCEPTED', 'PREPARING', 'DELIVERED'].contains(o.status))
                button('PAID', () => act('PAID')),
              if (o.payment == 'REFUND_REQUIRED')
                button('REFUNDED', () => act('REFUNDED')),
              note(context, 'events'),
              for (final event in o.json['events'] ?? [])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(context, event['action'] as String)),
                  subtitle: Text(event['created_at'] as String),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final AppState app;
  const AuthScreen(this.app, {super.key});
  @override
  State<AuthScreen> createState() => _AuthState();
}

class _AuthState extends ScreenState<AuthScreen> {
  bool register = false;
  final fields = <String, TextEditingController>{
    for (final key in ['name', 'email', 'password', 'password_repeat'])
      key: TextEditingController(),
  };
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, register ? 'register' : 'login'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        note(context, 'sellerIntro'),
        for (final key in ['name', 'email', 'password', 'password_repeat'])
          if (register || ['email', 'password'].contains(key))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: fields[key],
                obscureText: key.contains('password'),
                autocorrect: !key.contains('password'),
                enableSuggestions: !key.contains('password'),
                keyboardType: key == 'email'
                    ? TextInputType.emailAddress
                    : TextInputType.text,
                decoration: InputDecoration(labelText: tr(context, key)),
              ),
            ),
        errors(),
        button(register ? 'register' : 'login', () async {
          if (register) {
            await widget.app.api.call(
              'auth/register/',
              method: 'POST',
              authenticated: false,
              body: {for (final e in fields.entries) e.key: e.value.text},
            );
          }
          await widget.app.signIn(
            fields['email']!.text.trim(),
            fields['password']!.text,
          );
          if (mounted && context.mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => SellerScreen(widget.app)),
            );
          }
        }),
        TextButton(
          onPressed: () => setState(() => register = !register),
          child: Text(tr(context, register ? 'login' : 'register')),
        ),
        TextButton(
          onPressed: () =>
              open(context, PasswordScreen(widget.app, reset: true)),
          child: Text(tr(context, 'forgotPassword')),
        ),
        TextButton(
          onPressed: () => openUrl(context, widget.app.privacyUrl),
          child: Text(tr(context, 'privacyPolicy')),
        ),
      ],
    ),
  );
}

class SellerScreen extends StatefulWidget {
  final AppState app;
  const SellerScreen(this.app, {super.key});
  @override
  State<SellerScreen> createState() => _SellerState();
}

class _SellerState extends ScreenState<SellerScreen> {
  Store? store;
  Map<String, dynamic>? dashboard;
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => perform(load));
  }

  Future<void> load() async {
    try {
      final data = await widget.app.api.call('seller/store/');
      store = Store.fromJson(data);
      dashboard = Map<String, dynamic>.from(
        await widget.app.api.call('seller/dashboard/'),
      );
    } on ApiError catch (e) {
      if (e.status != 404) {
        rethrow;
      }
      store = null;
    }
    if (mounted && context.mounted) {
      setState(() => loaded = true);
    }
  }

  Future<void> edit(Widget screen) async {
    await open(context, screen);
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'manageStore')),
        actions: [
          IconButton(
            tooltip: tr(context, 'refresh'),
            onPressed: busy ? null : () => perform(load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          errors(),
          if (loaded && store == null) ...[
            note(context, 'createStoreIntro'),
            button('createStore', () => edit(StoreEditor(app))),
          ],
          if (store != null) ...[
            Text(store!.name, style: Theme.of(context).textTheme.headlineSmall),
            Text(store!.slug),
            note(context, 'checklist'),
            if (store!.json['suspended'] == true)
              note(context, 'storeSuspended'),
            if (dashboard != null) ...[
              _metric(
                context,
                'activeProducts',
                '${dashboard!['active_products']}',
              ),
              _metric(context, 'newOrders', '${dashboard!['new_orders']}'),
              _metric(
                context,
                'preparingOrders',
                '${dashboard!['preparing_orders']}',
              ),
              _metric(
                context,
                'sellerConfirmedTotal',
                '\$${dashboard!['seller_confirmed_total']} USD',
              ),
            ],
            button(
              'products',
              () => edit(ProductList(app)),
              icon: Icons.inventory_2_outlined,
            ),
            button(
              'orders',
              () => edit(SellerOrders(app)),
              icon: Icons.receipt_long_outlined,
            ),
            button(
              'myStore',
              () => edit(StoreEditor(app, store: store)),
              icon: Icons.store_outlined,
            ),
            button(
              store!.json['published'] == true ? 'unpublish' : 'publish',
              () async {
                await app.api.call(
                  'seller/store/publish/',
                  method: 'POST',
                  body: {'published': store!.json['published'] != true},
                );
                await load();
              },
            ),
            button(
              'shareStore',
              () => shareStore(store!),
              icon: Icons.share_outlined,
            ),
            if (dashboard != null) ...[
              note(context, 'lowStock'),
              for (final p in dashboard!['low_stock'])
                ListTile(
                  title: Text(p['name'] as String),
                  trailing: Text('${p['stock']}'),
                ),
            ],
          ],
          const Divider(),
          button('changePassword', () => edit(PasswordScreen(app))),
          button(
            'deleteAccount',
            () => edit(DeleteAccountScreen(app)),
            icon: Icons.delete_forever,
          ),
          button('logout', () async {
            await app.signOut();
            if (mounted && context.mounted) {
              Navigator.popUntil(context, (r) => r.isFirst);
            }
          }, icon: Icons.logout),
          TextButton(
            onPressed: () => openUrl(context, app.privacyUrl),
            child: Text(tr(context, 'privacyPolicy')),
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String key, String value) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(context, key)),
          gap(),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );
}

class StoreEditor extends StatefulWidget {
  final AppState app;
  final Store? store;
  const StoreEditor(this.app, {this.store, super.key});
  @override
  State<StoreEditor> createState() => _StoreEditorState();
}

class _StoreEditorState extends ScreenState<StoreEditor> {
  final fields = <String, TextEditingController>{};
  String provider = 'EVC Plus';
  @override
  void initState() {
    super.initState();
    for (final key in [
      'name',
      'slug',
      'description',
      'phone',
      'whatsapp',
      'city',
      'delivery_regions',
      'pickup_instructions',
      'delivery_fee',
      'payment_account',
      'payment_name',
    ]) {
      final value = widget.store?.json[key];
      fields[key] = TextEditingController(
        text: value is List
            ? value.join(', ')
            : value?.toString() ?? (key == 'delivery_fee' ? '0.00' : ''),
      );
    }
    provider = widget.store?.json['payment_provider'] as String? ?? provider;
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'myStore'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        note(context, 'manualPaymentNotice'),
        for (final e in fields.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: e.value,
              keyboardType: e.key.contains('phone') || e.key == 'whatsapp'
                  ? TextInputType.phone
                  : e.key == 'delivery_fee'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: tr(context, e.key),
                hintText: e.key == 'phone'
                    ? '+252612345678'
                    : e.key == 'delivery_regions'
                    ? tr(context, 'commaRegions')
                    : null,
              ),
            ),
          ),
        DropdownButtonFormField<String>(
          initialValue: provider,
          decoration: InputDecoration(
            labelText: tr(context, 'payment_provider'),
          ),
          items: [
            'EVC Plus',
            'eDahab',
            'ZAAD',
            'SAHAL',
            'Other',
          ].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: (p) => setState(() => provider = p!),
        ),
        errors(),
        button('save', () async {
          await widget.app.api.call(
            'seller/store/',
            method: widget.store == null ? 'POST' : 'PATCH',
            body: {
              for (final e in fields.entries) e.key: e.value.text.trim(),
              'delivery_regions': fields['delivery_regions']!.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
              'payment_provider': provider,
            },
          );
          if (mounted && context.mounted) {
            Navigator.pop(context);
          }
        }),
        if (widget.store != null)
          button('chooseLogo', () async {
            final image = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1600,
              imageQuality: 85,
            );
            if (image != null) {
              await widget.app.api.upload('seller/store/logo/', image.path);
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(tr(context, 'saved'))));
              }
            }
          }, icon: Icons.photo_outlined),
      ],
    ),
  );
}

class ProductList extends StatefulWidget {
  final AppState app;
  const ProductList(this.app, {super.key});
  @override
  State<ProductList> createState() => _ProductListState();
}

class _ProductListState extends ScreenState<ProductList> {
  List<Product> products = [];
  String? next;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => perform(load));
  }

  Future<void> load({bool more = false}) async {
    final data = await widget.app.api.call(
      more ? next!.replaceFirst(widget.app.api.base, '') : 'seller/products/',
    );
    if (mounted && context.mounted) {
      setState(() {
        final found = (data['results'] as List)
            .map((e) => Product.fromJson(e))
            .toList();
        products = more ? [...products, ...found] : found;
        next = data['next'] as String?;
      });
    }
  }

  Future<void> edit(Product? product) async {
    await open(context, ProductEditor(widget.app, product: product));
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'products')),
      actions: [
        IconButton(
          tooltip: tr(context, 'refresh'),
          onPressed: () => perform(load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        button('addProduct', () => edit(null), icon: Icons.add),
        errors(),
        if (products.isEmpty && !busy) note(context, 'noProducts'),
        for (final p in products)
          ProductTile(p, onTap: () => perform(() => edit(p))),
        if (next != null) button('more', () => load(more: true)),
      ],
    ),
  );
}

class ProductEditor extends StatefulWidget {
  final AppState app;
  final Product? product;
  const ProductEditor(this.app, {this.product, super.key});
  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ScreenState<ProductEditor> {
  final fields = <String, TextEditingController>{};
  Product? product;
  bool published = false, archived = false;
  @override
  void initState() {
    super.initState();
    product = widget.product;
    for (final key in [
      'name',
      'slug',
      'description',
      'category',
      'price',
      'stock',
    ]) {
      fields[key] = TextEditingController(
        text: product?.json[key]?.toString() ?? (key == 'stock' ? '0' : ''),
      );
    }
    published = product?.json['published'] == true;
    archived = product?.json['archived'] == true;
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final data = await widget.app.api.call(
      product == null ? 'seller/products/' : 'seller/products/${product!.id}/',
      method: product == null ? 'POST' : 'PATCH',
      body: {
        for (final e in fields.entries) e.key: e.value.text.trim(),
        if (product != null) 'expected_updated_at': product!.json['updated_at'],
        'published': published,
        'archived': archived,
      },
    );
    if (mounted && context.mounted) {
      setState(() => product = Product.fromJson(data));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'product'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final e in fields.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: e.value,
              keyboardType: ['price', 'stock'].contains(e.key)
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(labelText: tr(context, e.key)),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr(context, 'published')),
          value: published,
          onChanged: (v) => setState(() => published = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr(context, 'archived')),
          value: archived,
          onChanged: (v) => setState(() => archived = v),
        ),
        if (product?.json['moderated'] == true)
          note(context, 'productModerated'),
        errors(),
        button('save', () async {
          await save();
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(tr(context, 'saved'))));
          }
        }),
        note(context, 'photoHelp'),
        if (product != null) ...[
          for (final photo in product!.json['photos'] as List)
            ListTile(
              leading: const Icon(Icons.image),
              title: Text('${tr(context, 'photo')} ${photo['id']}'),
              trailing: IconButton(
                tooltip: tr(context, 'remove'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => perform(() async {
                  await widget.app.api.call(
                    'seller/products/${product!.id}/photos/${photo['id']}/',
                    method: 'DELETE',
                  );
                  final data = await widget.app.api.call(
                    'seller/products/${product!.id}/',
                  );
                  setState(() => product = Product.fromJson(data));
                }),
              ),
            ),
          if ((product!.json['photos'] as List).length < 3)
            button('choosePhoto', () async {
              final image = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 1600,
                imageQuality: 85,
              );
              if (image != null) {
                await widget.app.api.upload(
                  'seller/products/${product!.id}/photos/',
                  image.path,
                );
                final data = await widget.app.api.call(
                  'seller/products/${product!.id}/',
                );
                if (mounted && context.mounted) {
                  setState(() => product = Product.fromJson(data));
                }
              }
            }, icon: Icons.add_photo_alternate_outlined),
        ],
      ],
    ),
  );
}

class SellerOrders extends StatefulWidget {
  final AppState app;
  const SellerOrders(this.app, {super.key});
  @override
  State<SellerOrders> createState() => _SellerOrdersState();
}

class _SellerOrdersState extends ScreenState<SellerOrders> {
  List<Map<String, dynamic>> orders = [];
  String status = '', from = '', to = '';
  String? next;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => perform(load));
  }

  Future<void> load({bool more = false}) async {
    final data = await widget.app.api.call(
      more
          ? next!.replaceFirst(widget.app.api.base, '')
          : 'seller/orders/?status=$status&from=$from&to=$to',
    );
    if (mounted && context.mounted) {
      setState(() {
        final found = List<Map<String, dynamic>>.from(data['results']);
        orders = more ? [...orders, ...found] : found;
        next = data['next'] as String?;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'orders'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          initialValue: status,
          decoration: InputDecoration(labelText: tr(context, 'status')),
          items: ['', 'NEW', 'ACCEPTED', 'PREPARING', 'DELIVERED', 'CANCELLED']
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(tr(context, s.isEmpty ? 'all' : s)),
                ),
              )
              .toList(),
          onChanged: (s) => setState(() => status = s!),
        ),
        gap(),
        TextField(
          decoration: InputDecoration(
            labelText: tr(context, 'dateFrom'),
            hintText: 'YYYY-MM-DD',
          ),
          onChanged: (v) => from = v,
        ),
        gap(),
        TextField(
          decoration: InputDecoration(
            labelText: tr(context, 'dateTo'),
            hintText: 'YYYY-MM-DD',
          ),
          onChanged: (v) => to = v,
        ),
        button('refresh', load, icon: Icons.refresh),
        errors(),
        if (orders.isEmpty && !busy) note(context, 'noOrders'),
        for (final o in orders)
          Card(
            child: ListTile(
              title: Text(o['customer_name'] as String),
              subtitle: Text(
                '${tr(context, o['status'] as String)} · ${tr(context, o['payment'] as String)}',
              ),
              trailing: Text('\$${o['total']}'),
              onTap: () => perform(() async {
                await open(
                  context,
                  OrderScreen(widget.app, id: o['id'] as int),
                );
                await load();
              }),
            ),
          ),
        if (next != null) button('more', () => load(more: true)),
      ],
    ),
  );
}

class PasswordScreen extends StatefulWidget {
  final AppState app;
  final bool reset;
  const PasswordScreen(this.app, {this.reset = false, super.key});
  @override
  State<PasswordScreen> createState() => _PasswordState();
}

class _PasswordState extends ScreenState<PasswordScreen> {
  final fields = <String, TextEditingController>{
    for (final key in ['email', 'uid', 'token', 'old_password', 'password'])
      key: TextEditingController(),
  };
  String? success;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'changePassword'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.reset) ...[
          TextField(
            controller: fields['email'],
            decoration: InputDecoration(labelText: tr(context, 'email')),
          ),
          button('sendReset', () async {
            await widget.app.api.call(
              'auth/reset/',
              method: 'POST',
              authenticated: false,
              body: {'email': fields['email']!.text},
            );
            setState(() => success = 'resetSent');
          }),
          note(context, 'resetHelp'),
        ],
        for (final key
            in widget.reset
                ? ['uid', 'token', 'password']
                : ['old_password', 'password'])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              controller: fields[key],
              obscureText: key.contains('password') || key == 'token',
              decoration: InputDecoration(labelText: tr(context, key)),
            ),
          ),
        errors(),
        if (success != null) note(context, success!),
        button('changePassword', () async {
          await widget.app.api.call(
            widget.reset ? 'auth/reset/confirm/' : 'auth/password/',
            method: 'POST',
            authenticated: !widget.reset,
            body: {for (final e in fields.entries) e.key: e.value.text},
          );
          await widget.app.api.clearAuth();
          await widget.app.clearPrivate();
          if (mounted && context.mounted) {
            Navigator.popUntil(context, (r) => r.isFirst);
          }
        }),
      ],
    ),
  );
}

class DeleteAccountScreen extends StatefulWidget {
  final AppState app;
  const DeleteAccountScreen(this.app, {super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountState();
}

class _DeleteAccountState extends ScreenState<DeleteAccountScreen> {
  final password = TextEditingController();
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'deleteAccount'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        note(context, 'deleteAccountWarning'),
        TextField(
          controller: password,
          obscureText: true,
          decoration: InputDecoration(labelText: tr(context, 'password')),
        ),
        errors(),
        button('deleteAccount', () async {
          if (!await confirm(context, 'deleteAccountConfirm')) {
            return;
          }
          await widget.app.api.call(
            'auth/delete/',
            method: 'POST',
            body: {'password': password.text},
          );
          await widget.app.api.clearAuth();
          await widget.app.clearPrivate();
          if (mounted && context.mounted) {
            Navigator.popUntil(context, (r) => r.isFirst);
          }
        }, icon: Icons.delete_forever),
      ],
    ),
  );
}

class ReportScreen extends StatefulWidget {
  final AppState app;
  final Store store;
  final Product? product;
  const ReportScreen(this.app, this.store, {this.product, super.key});
  @override
  State<ReportScreen> createState() => _ReportState();
}

class _ReportState extends ScreenState<ReportScreen> {
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'report'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: reason,
          maxLines: 5,
          maxLength: 1000,
          decoration: InputDecoration(labelText: tr(context, 'reason')),
        ),
        errors(),
        button('sendReport', () async {
          await widget.app.api.call(
            'reports/',
            method: 'POST',
            authenticated: false,
            body: {
              'store': widget.store.id,
              'product': widget.product?.id,
              'reason': reason.text.trim(),
            },
          );
          if (mounted && context.mounted) {
            Navigator.pop(context);
          }
        }),
      ],
    ),
  );
}
