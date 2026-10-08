import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inventory.dart';
import 'l10n.dart';
import 'developer_credit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final support = await getApplicationSupportDirectory();
    final inventory = Inventory(Directory('${support.path}/offline-inventory'));
    await inventory.open();
    runApp(OfflineApp(inventory, await SharedPreferences.getInstance()));
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SelectableText(
                'Onlinesuuq could not open your inventory.\n'
                'Close any other Onlinesuuq window and try again. If this continues, keep your data files and contact support.\n\n'
                'Onlinesuuq ma furi karin kaydkaaga. Xir daaqadaha kale ee Onlinesuuq, kadib isku day mar kale.\n'
                'https://github.com/Mohamed-Qadar/Onlinesuuq/issues',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OfflineApp extends StatefulWidget {
  final Inventory inventory;
  final SharedPreferences prefs;
  const OfflineApp(this.inventory, this.prefs, {super.key});
  @override
  State<OfflineApp> createState() => _OfflineAppState();
}

class _OfflineAppState extends State<OfflineApp> {
  late String language = widget.prefs.getString('offlineLanguage') ?? 'so';
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Onlinesuuq',
    debugShowCheckedModeBanner: false,
    locale: Locale(language),
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
      scaffoldBackgroundColor: const Color(0xfff5f8f7),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: InventoryScreen(widget.inventory, language, () async {
      final value = language == 'so' ? 'en' : 'so';
      await widget.prefs.setString('offlineLanguage', value);
      setState(() => language = value);
    }),
  );
}

class InventoryScreen extends StatefulWidget {
  final Inventory inventory;
  final String language;
  final VoidCallback toggleLanguage;
  const InventoryScreen(
    this.inventory,
    this.language,
    this.toggleLanguage, {
    super.key,
  });
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String query = '';
  int tab = 0;
  bool busy = false;
  String? error;
  Inventory get db => widget.inventory;
  String t(String en, String so) => widget.language == 'so' ? so : en;
  String money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
  Future<void> action(Future<void> Function() fn) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = t(
            'Could not save. Check the file, available disk space and stock quantity. Your previous data is preserved.',
            'Lama kaydin. Hubi faylka, booska diskiga iyo tirada alaabta. Xogtii hore way kuu kaydsan tahay.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<bool> confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('Confirm', 'Xaqiiji')),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'Jooji')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Confirm', 'Xaqiiji')),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> edit([Map<String, dynamic>? product]) async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(text: product?['name'] ?? '');
    final sku = TextEditingController(text: product?['sku'] ?? '');
    final category = TextEditingController(text: product?['category'] ?? '');
    final price = TextEditingController(
      text: product == null
          ? '0.00'
          : (product['priceCents'] / 100).toStringAsFixed(2),
    );
    final stock = TextEditingController(text: '0');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          t(
            product == null ? 'Add product' : 'Edit product',
            product == null ? 'Ku dar alaab' : 'Beddel alaabta',
          ),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    maxLength: 150,
                    decoration: InputDecoration(
                      labelText: t('Product name', 'Magaca alaabta'),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? t('Required', 'Waa loo baahan yahay')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: sku,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: t(
                        'SKU / code (optional)',
                        'Koodhka alaabta (ikhtiyaari)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: category,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: t(
                        'Category (optional)',
                        'Qaybta (ikhtiyaari)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: price,
                    decoration: InputDecoration(
                      labelText: t(
                        'Selling price (USD)',
                        'Qiimaha iibka (USD)',
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) => parseCents(v ?? '') == null
                        ? t(
                            'Enter 0–1,000,000 with up to 2 decimal places',
                            'Geli 0–1,000,000; ugu badnaan 2 jajab',
                          )
                        : null,
                  ),
                  if (product == null) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: stock,
                      decoration: InputDecoration(
                        labelText: t('Opening stock', 'Tirada bilowga'),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => validQuantity(v, allowZero: true)
                          ? null
                          : t(
                              'Enter a whole number from 0 to 100,000,000',
                              'Geli tiro dhan 0 ilaa 100,000,000',
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel', 'Jooji')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(t('Save', 'Kaydi')),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await action(
        () => db.saveProduct(
          id: product?['id'],
          name: name.text,
          sku: sku.text,
          category: category.text,
          priceCents: parseCents(price.text)!,
          openingStock: int.parse(stock.text),
        ),
      );
    }
    // Controllers are disposed after the dialog's exit animation releases its fields.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in [name, sku, category, price, stock]) {
      c.dispose();
    }
  }

  Future<void> adjust(Map<String, dynamic> product, String kind) async {
    final form = GlobalKey<FormState>();
    final qty = TextEditingController(text: '1');
    final note = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${kindLabel(kind)} — ${product['name']}'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${t('Available', 'La heli karo')}: ${product['stock']}'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: qty,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: t('Quantity', 'Tirada'),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (!validQuantity(v)) {
                      return t(
                        'Enter a positive whole number',
                        'Geli tiro dhan oo ka weyn eber',
                      );
                    }
                    if (kind != 'in' && int.parse(v!) > product['stock']) {
                      return t('Not enough stock', 'Alaab kugu filan ma jirto');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: note,
                  maxLength: 250,
                  decoration: InputDecoration(
                    labelText: t('Note (optional)', 'Faahfaahin (ikhtiyaari)'),
                  ),
                ),
                if (kind == 'sale')
                  Text(
                    '${t('Unit price', 'Qiimaha halkii xabbo')}: ${money(product['priceCents'])} USD',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel', 'Jooji')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(t('Save', 'Kaydi')),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await action(
        () => db.adjust(product['id'], kind, int.parse(qty.text), note.text),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    qty.dispose();
    note.dispose();
  }

  String kindLabel(String kind) => switch (kind) {
    'opening' => t('Opening stock', 'Tirada bilowga'),
    'in' => t('Stock in', 'Alaab soo gashay'),
    'out' => t('Stock out', 'Alaab baxday'),
    'sale' => t('Record sale', 'Diiwaangeli iib'),
    _ => kind,
  };
  Future<void> backup() async {
    final location = await getSaveLocation(
      suggestedName:
          'Onlinesuuq-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (location == null) {
      return;
    }
    await action(() async {
      if (File(location.path).absolute.path.startsWith(
        '${db.directory.absolute.path}${Platform.pathSeparator}',
      )) {
        throw const FormatException('Choose a backup folder outside app data');
      }
      await XFile.fromData(
        utf8.encode(db.export()),
        mimeType: 'application/json',
        name: 'Onlinesuuq-backup.json',
      ).saveTo(location.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'Backup saved. Keep a copy on another drive.',
                'Nuqulka waa la kaydiyay. Ku hay nuqul disk kale.',
              ),
            ),
          ),
        );
      }
    });
  }

  Future<void> restore() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null || !mounted) {
      return;
    }
    if (!await confirm(
      t(
        'Replace this computer’s inventory with the selected backup? Export your current backup first.',
        'Ma ku beddelaysaa kaydka kombiyuutarkan nuqulka aad dooratay? Marka hore kaydi nuqulka xogta hadda.',
      ),
    )) {
      return;
    }
    await action(() async {
      if (await file.length() > 20000000) {
        throw const FormatException('Backup too large');
      }
      await db.restore(await file.readAsString());
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = db.products.where((p) => p['archived'] != true).toList();
    final visible = products
        .where(
          (p) => '${p['name']} ${p['sku']} ${p['category']}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    final units = products.fold<int>(0, (n, p) => n + p['stock'] as int);
    final value = products.fold<int>(
      0,
      (n, p) => n + p['stock'] * p['priceCents'] as int,
    );
    final sales = db.movements
        .where((m) => m['kind'] == 'sale')
        .fold<int>(0, (n, m) => n - (m['quantity'] * m['unitCents']) as int);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Onlinesuuq'),
        actions: [
          TextButton(
            onPressed: widget.toggleLanguage,
            child: Text(widget.language == 'so' ? 'English' : 'Soomaali'),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (value) {
              if (value == 'backup') {
                backup();
              }
              if (value == 'restore') {
                restore();
              }
              if (value == 'about') {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(t('About this version', 'Ku saabsan noocan')),
                    content: SelectableText(
                      '${t('Offline inventory • version 1.1.1\nNo account or internet required. Data stays on this Windows user profile. Back up regularly. Online shops and automatic cloud sync are not included in this version. Sales are local records; no payment is processed.', 'Kayd aan internet u baahnayn • nooca 1.1.1\nAkoon looma baahna. Xogtu waxay ku jirtaa kombiyuutarkan. Samee nuqul joogto ah. Noocan kuma jiraan dukaan internet ah ama isku xidhka xogta. Iibku waa diiwaan keliya; lacag lama wareejiyo.')}\n\n${db.directory.path}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(t('Close', 'Xir')),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'backup',
                child: Text(t('Export backup', 'Dhoofin nuqul')),
              ),
              PopupMenuItem(
                value: 'restore',
                child: Text(t('Restore backup', 'Soo celi nuqul')),
              ),
              PopupMenuItem(
                value: 'about',
                child: Text(
                  t('About / data location', 'Ku saabsan / goobta xogta'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              MaterialBanner(
                content: Text(error!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => error = null),
                    child: Text(t('Close', 'Xir')),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t(
                    'Your shop, on your computer. Works offline.',
                    'Dukaankaaga, kombiyuutarkaaga. Internet looma baahna.',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  metric(t('Products', 'Alaabta'), '${products.length}'),
                  metric(t('Units in stock', 'Tirada kaydka'), '$units'),
                  metric(
                    t('Stock retail value', 'Qiimaha kaydka'),
                    money(value),
                  ),
                  metric(
                    t('Recorded sales', 'Iibka diiwaangashan'),
                    money(sales),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: t(
                          'Search products, SKU or category',
                          'Raadi alaab, koodh ama qayb',
                        ),
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => edit(),
                    icon: const Icon(Icons.add),
                    label: Text(t('Add product', 'Ku dar alaab')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tab == 0
                  ? visible.isEmpty
                        ? Center(
                            child: Text(
                              products.isEmpty
                                  ? t(
                                      'Add your first product to start tracking stock.',
                                      'Ku dar alaabtaada koowaad si aad kaydka u maamusho.',
                                    )
                                  : t(
                                      'No matching products',
                                      'Alaab u dhiganta lama helin',
                                    ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                            itemCount: visible.length,
                            itemBuilder: (ctx, i) {
                              final p = visible[i];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 24,
                                    runSpacing: 12,
                                    children: [
                                      SizedBox(
                                        width: 260,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p['name'],
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                            Text(
                                              '${p['sku']}  ${p['category']}',
                                            ),
                                            Text(
                                              '${money(p['priceCents'])} USD  •  ${t('Stock', 'Kayd')}: ${p['stock']}',
                                              style: TextStyle(
                                                color: p['stock'] <= 5
                                                    ? Colors.deepOrange
                                                    : Colors.teal,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 4,
                                        children: [
                                          TextButton(
                                            onPressed: () => adjust(p, 'in'),
                                            child: Text(kindLabel('in')),
                                          ),
                                          TextButton(
                                            onPressed: p['stock'] == 0
                                                ? null
                                                : () => adjust(p, 'out'),
                                            child: Text(kindLabel('out')),
                                          ),
                                          FilledButton.tonal(
                                            onPressed: p['stock'] == 0
                                                ? null
                                                : () => adjust(p, 'sale'),
                                            child: Text(kindLabel('sale')),
                                          ),
                                          IconButton(
                                            tooltip: t('Edit', 'Beddel'),
                                            onPressed: () => edit(p),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: t(
                                              'Archive (stock must be zero)',
                                              'Kaydi taariikh ahaan (tiradu ha noqoto eber)',
                                            ),
                                            onPressed: p['stock'] != 0
                                                ? null
                                                : () async {
                                                    if (await confirm(
                                                      t(
                                                        'Archive this product? Its history will be kept.',
                                                        'Alaabtan ma ka saaraysaa liiska? Taariikhdeedu way sii jiraysaa.',
                                                      ),
                                                    )) {
                                                      await action(
                                                        () =>
                                                            db.archive(p['id']),
                                                      );
                                                    }
                                                  },
                                            icon: const Icon(
                                              Icons.archive_outlined,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                  : history(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (v) => setState(() => tab = v),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.inventory_2_outlined),
                label: t('Inventory', 'Kaydka'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.history),
                label: t(
                  'Stock & sales history',
                  'Taariikhda kaydka iyo iibka',
                ),
              ),
            ],
          ),
          const DeveloperCredit(),
        ],
      ),
    );
  }

  Widget metric(String label, String value) => Container(
    width: 185,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Text(
          value,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
  Widget history() {
    final rows = db.movements.reversed
        .where(
          (m) => '${m['name']} ${m['note']}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    if (rows.isEmpty) {
      return Center(
        child: Text(t('No movements yet', 'Weli wax dhaqdhaqaaq ah ma jiraan')),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final m = rows[i];
        return Card(
          child: ListTile(
            title: Text('${m['name']} • ${kindLabel(m['kind'])}'),
            subtitle: Text(
              '${DateTime.parse(m['at']).toLocal().toString().substring(0, 19)}\n${m['note']}',
            ),
            trailing: Text(
              '${m['quantity'] > 0 ? '+' : ''}${m['quantity']}${m['kind'] == 'sale' ? '\n${money(-m['quantity'] * m['unitCents'])} USD' : ''}',
            ),
          ),
        );
      },
    );
  }
}

int? parseCents(String value) {
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value.trim())) {
    return null;
  }
  final parts = value.trim().split('.');
  final cents =
      int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return cents <= 100000000 ? cents : null;
}

bool validQuantity(String? value, {bool allowZero = false}) {
  final n = int.tryParse(value ?? '');
  return n != null && n >= (allowZero ? 0 : 1) && n <= 100000000;
}
