import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

/// Versioned local inventory. Prices are integer USD cents, never floats.
/// Every commit writes and flushes a new snapshot before changing memory.
class Inventory {
  final Directory directory;
  RandomAccessFile? _lock;
  bool _writing = false;
  Map<String, dynamic> _data = {
    'format': 'onlinesuuq-inventory',
    'version': 1,
    'products': <dynamic>[],
    'movements': <dynamic>[],
  };
  Inventory(this.directory);
  List<Map<String, dynamic>> get products =>
      List<Map<String, dynamic>>.from(_copy()['products']);
  List<Map<String, dynamic>> get movements =>
      List<Map<String, dynamic>>.from(_copy()['movements']);
  Map<String, dynamic> _copy() => jsonDecode(jsonEncode(_data));
  String export() => const JsonEncoder.withIndent('  ').convert(_data);
  Future<List<File>> _snapshots() async {
    final files = await directory
        .list()
        .where(
          (f) =>
              f is File &&
              RegExp(r'[/\\]inventory-\d+\.json$').hasMatch(f.path),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> open() async {
    await directory.create(recursive: true);
    final handle = await File('${directory.path}/inventory.lock')
        .open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      _lock = handle;
      final snapshots = await _snapshots();
      if (snapshots.isNotEmpty) {
        // Never silently roll back damaged data or overwrite it with an empty shop.
        _data = validate(await snapshots.first.readAsString());
      }
    } catch (_) {
      await handle.close();
      _lock = null;
      rethrow;
    }
  }

  Future<void> close() async {
    await _lock?.close();
    _lock = null;
  }

  static Map<String, dynamic> validate(String text) {
    if (text.length > 20000000) {
      throw const FormatException('Backup too large');
    }
    final d = jsonDecode(text);
    if (d is! Map<String, dynamic> ||
        d['format'] != 'onlinesuuq-inventory' ||
        d['version'] != 1 ||
        d['products'] is! List ||
        d['movements'] is! List) {
      throw const FormatException('Invalid inventory backup');
    }
    final ids = <String>{};
    for (final p in d['products']) {
      if (p is! Map ||
          p['id'] is! String ||
          !ids.add(p['id']) ||
          p['name'] is! String ||
          (p['name'] as String).trim().isEmpty ||
          (p['name'] as String).length > 150 ||
          p['sku'] is! String ||
          p['category'] is! String ||
          p['priceCents'] is! int ||
          p['priceCents'] < 0 ||
          p['priceCents'] > 100000000 ||
          p['stock'] is! int ||
          p['stock'] < 0 ||
          p['stock'] > 100000000 ||
          p['archived'] is! bool) {
        throw const FormatException('Invalid product');
      }
    }
    final movementIds = <String>{};
    for (final m in d['movements']) {
      if (m is! Map ||
          m['id'] is! String ||
          !movementIds.add(m['id']) ||
          !ids.contains(m['productId']) ||
          m['name'] is! String ||
          m['quantity'] is! int ||
          m['quantity'] == 0 ||
          (m['quantity'] as int).abs() > 100000000 ||
          !['opening', 'in', 'out', 'sale'].contains(m['kind']) ||
          m['unitCents'] is! int ||
          m['unitCents'] < 0 ||
          m['unitCents'] > 100000000 ||
          m['note'] is! String ||
          m['at'] is! String ||
          DateTime.tryParse(m['at']) == null ||
          (['opening', 'in'].contains(m['kind']) && m['quantity'] < 0) ||
          (['out', 'sale'].contains(m['kind']) && m['quantity'] > 0)) {
        throw const FormatException('Invalid movement');
      }
    }
    for (final p in d['products']) {
      final balance = (d['movements'] as List)
          .where((m) => m['productId'] == p['id'])
          .fold<int>(0, (sum, m) => sum + m['quantity'] as int);
      if (balance != p['stock']) {
        throw const FormatException('Invalid stock balance');
      }
    }
    return d;
  }

  Future<void> _commit(Map<String, dynamic> next) async {
    if (_lock == null || _writing) {
      throw StateError('Inventory unavailable');
    }
    _writing = true;
    try {
      final text = jsonEncode(next);
      validate(text);
      final existing = await _snapshots();
      var sequence = DateTime.now().microsecondsSinceEpoch;
      if (existing.isNotEmpty) {
        final old = int.parse(
          RegExp(r'inventory-(\d+)\.json$')
              .firstMatch(existing.first.path)![1]!,
        );
        if (sequence <= old) {
          sequence = old + 1;
        }
      }
      final target =
          '${directory.path}/inventory-${sequence.toString().padLeft(20, '0')}.json';
      final temp = File('$target.tmp');
      await temp.writeAsString(text, flush: true);
      await temp.rename(target);
      _data = next;
      // Retain the previous two committed snapshots for manual recovery.
      for (final file in existing.skip(2)) {
        try {
          await file.delete();
        } on FileSystemException {
          /* commit succeeded */
        }
      }
    } finally {
      _writing = false;
    }
  }

  Future<void> restore(String text) async => _commit(validate(text));
  Future<void> saveProduct({
    String? id,
    required String name,
    required String sku,
    required String category,
    required int priceCents,
    int openingStock = 0,
  }) async {
    final next = _copy();
    final list = next['products'] as List;
    if (id == null) {
      id = const Uuid().v4();
      list.add({
        'id': id,
        'name': name.trim(),
        'sku': sku.trim(),
        'category': category.trim(),
        'priceCents': priceCents,
        'stock': openingStock,
        'archived': false,
      });
      if (openingStock > 0) {
        _movement(next, id, 'opening', openingStock, '');
      }
    } else {
      final p = list.firstWhere((p) => p['id'] == id);
      p.addAll({
        'name': name.trim(),
        'sku': sku.trim(),
        'category': category.trim(),
        'priceCents': priceCents,
      });
    }
    await _commit(next);
  }

  void _movement(
    Map<String, dynamic> next,
    String id,
    String kind,
    int delta,
    String note,
  ) {
    final p = (next['products'] as List).firstWhere((p) => p['id'] == id);
    (next['movements'] as List).add({
      'id': const Uuid().v4(),
      'productId': id,
      'name': p['name'],
      'kind': kind,
      'quantity': delta,
      'unitCents': p['priceCents'],
      'note': note.trim(),
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> adjust(String id, String kind, int quantity, String note) async {
    if (!['in', 'out', 'sale'].contains(kind) ||
        quantity <= 0 ||
        quantity > 100000000) {
      throw const FormatException('Invalid quantity');
    }
    final next = _copy();
    final p = (next['products'] as List).firstWhere((p) => p['id'] == id);
    final delta = kind == 'in' ? quantity : -quantity;
    if (p['archived'] == true || p['stock'] + delta < 0) {
      throw const FormatException('Not enough stock');
    }
    p['stock'] += delta;
    _movement(next, id, kind, delta, note);
    await _commit(next);
  }

  Future<void> archive(String id) async {
    final next = _copy();
    final p = (next['products'] as List).firstWhere((p) => p['id'] == id);
    if (p['stock'] != 0) {
      throw const FormatException('Remove remaining stock first');
    }
    p['archived'] = true;
    await _commit(next);
  }
}
