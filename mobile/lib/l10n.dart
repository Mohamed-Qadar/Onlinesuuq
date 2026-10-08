import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class AppStrings {
  final Map<String, dynamic> messages;
  AppStrings(this.messages);
  String text(String key) => messages[key] as String? ?? key;
  static AppStrings of(BuildContext context) =>
      Localizations.of<AppStrings>(context, AppStrings)!;
  static const delegate = _StringsDelegate();
}

class _StringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _StringsDelegate();
  static final _cache = <String, AppStrings>{};
  @override
  bool isSupported(Locale locale) => ['so', 'en'].contains(locale.languageCode);
  @override
  Future<AppStrings> load(Locale locale) {
    final cached = _cache[locale.languageCode];
    if (cached != null) {
      return SynchronousFuture(cached);
    }
    return rootBundle.loadString('lib/l10n/${locale.languageCode}.json').then((
      text,
    ) {
      final strings = AppStrings(jsonDecode(text));
      _cache[locale.languageCode] = strings;
      return strings;
    });
  }

  @override
  bool shouldReload(_StringsDelegate old) => false;
}

// Flutter's built-in Material catalogue may not cover Somali. App-owned labels
// are translated; platform date/selection controls fall back to English.
class MaterialFallback extends LocalizationsDelegate<MaterialLocalizations> {
  const MaterialFallback();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(MaterialFallback old) => false;
}

class WidgetsFallback extends LocalizationsDelegate<WidgetsLocalizations> {
  const WidgetsFallback();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture(const DefaultWidgetsLocalizations());
  @override
  bool shouldReload(WidgetsFallback old) => false;
}

class CupertinoFallback extends LocalizationsDelegate<CupertinoLocalizations> {
  const CupertinoFallback();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(CupertinoFallback old) => false;
}
