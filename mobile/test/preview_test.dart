import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dukaan/main.dart';
import 'package:dukaan/l10n.dart';

import 'app_test.dart' show appFor, jsonResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppStrings.delegate.load(const Locale('so'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    const fontPath = String.fromEnvironment('PREVIEW_FONT');
    if (fontPath.isNotEmpty) {
      final loader = FontLoader('Roboto');
      loader.addFont(
        File(fontPath).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
      await loader.load();
    }
  });
  for (final width in [360, 390, 1024]) {
    testWidgets('home layout at $width pixels', (tester) async {
      tester.view.physicalSize = Size(width.toDouble(), 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = await appFor(
        (_) async => jsonResponse({'results': [], 'next': null}),
      );
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: DukaanApp(app)));
      await tester.pumpAndSettle();
      expect(find.text('Dukaankaaga, gacantaada.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      const capture = bool.fromEnvironment('CAPTURE_PREVIEW');
      if (capture) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('../docs/previews/home-$width.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
