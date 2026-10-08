import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dukaan/inventory.dart';
import 'package:dukaan/offline_main.dart';

void main() {
  late Directory dir;
  late Inventory inventory;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('onlinesuuq-test-');
    inventory = Inventory(dir);
    await inventory.open();
  });
  tearDown(() async {
    await inventory.close();
    await dir.delete(recursive: true);
  });
  Future<String> product() async {
    await inventory.saveProduct(
      name: 'Rice',
      sku: 'R1',
      category: 'Food',
      priceCents: 1250,
      openingStock: 10,
    );
    return inventory.products.single['id'];
  }

  test(
    'stock and historical sale price survive close, reopen and restore',
    () async {
      final id = await product();
      await inventory.adjust(id, 'sale', 3, 'Cash sale');
      await inventory.saveProduct(
        id: id,
        name: 'Rice',
        sku: 'R1',
        category: 'Food',
        priceCents: 1500,
      );
      final backup = inventory.export();
      await inventory.close();
      inventory = Inventory(dir);
      await inventory.open();
      expect(inventory.products.single['stock'], 7);
      expect(inventory.movements.last['unitCents'], 1250);
      await inventory.adjust(id, 'in', 4, 'Delivery');
      await inventory.restore(backup);
      expect(inventory.products.single['stock'], 7);
      expect(inventory.movements.length, 2);
    },
  );
  test(
    'overselling, negative inputs and malformed backups preserve data',
    () async {
      final id = await product();
      final before = inventory.export();
      await expectLater(
        inventory.adjust(id, 'sale', 11, ''),
        throwsFormatException,
      );
      await expectLater(
        inventory.adjust(id, 'in', -2, ''),
        throwsFormatException,
      );
      await expectLater(
        inventory.restore('{"format":"wrong"}'),
        throwsFormatException,
      );
      await expectLater(
        inventory.restore(before.replaceFirst('"stock": 10', '"stock": 99')),
        throwsFormatException,
      );
      expect(inventory.export(), before);
    },
  );
  test(
    'archiving retains movement history and refuses stock remaining',
    () async {
      final id = await product();
      await expectLater(inventory.archive(id), throwsFormatException);
      await inventory.adjust(id, 'out', 10, 'Damaged');
      await inventory.archive(id);
      expect(inventory.products.single['archived'], true);
      expect(inventory.movements.length, 2);
    },
  );
  test(
    'incomplete writes are ignored; corrupt committed snapshot is never reset',
    () async {
      await product();
      await inventory.close();
      await File('${dir.path}/inventory-99999999999999999999.json.tmp')
          .writeAsString('partial');
      inventory = Inventory(dir);
      await inventory.open();
      expect(inventory.products.length, 1);
      await inventory.close();
      await File('${dir.path}/inventory-99999999999999999999.json')
          .writeAsString('corrupt');
      inventory = Inventory(dir);
      await expectLater(inventory.open(), throwsFormatException);
      expect(
        await File('${dir.path}/inventory-99999999999999999999.json')
            .readAsString(),
        'corrupt',
      );
    },
  );
  test('decimal price parsing does not round or accept invalid inputs', () {
    expect(parseCents('12.05'), 1205);
    expect(parseCents('0.1'), 10);
    expect(parseCents('-1'), null);
    expect(parseCents('NaN'), null);
    expect(parseCents('1.001'), null);
    expect(parseCents('1000001'), null);
  });
  testWidgets(
    'offline app starts without API, adds product, changes language',
    (tester) async {
      SharedPreferences.setMockInitialValues({'offlineLanguage': 'en'});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(OfflineApp(inventory, prefs));
      await tester.pumpAndSettle();
      expect(
        find.text('Your shop, on your computer. Works offline.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Add product'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Product name'),
        'Milk',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Opening stock'),
        '6',
      );
      await tester.tap(find.text('Save'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        if (inventory.products.isNotEmpty) {
          break;
        }
      }
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Milk'), findsOneWidget);
      expect(inventory.products.single['stock'], 6);
      await tester.tap(find.text('Soomaali'));
      await tester.pumpAndSettle();
      expect(find.text('Ku dar alaab'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
