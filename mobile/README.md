# Dukaan Android

Flutter 3.47.6 / Dart 3.13.5. Satıcı ve müşteri aynı uygulamada; web veya WebView alışveriş ekranı yoktur.

Kurulum ve kesin komutlar için [ana README](../README.md), Android imzalama/iki cihaz testi için [yayın rehberi](../docs/ANDROID_RELEASE.md).

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d emulator-5554 --dart-define=API_URL=http://10.0.2.2:8000/api/v1/
```

`test/` unit/widget testleridir. `test_live/live_api_test.dart` iki ayrı Dart API oturumuyla gerçek yerel backend’i sınar; cihaz testi değildir. Release API_URL HTTPS olmalıdır; debug Android manifestinde yerel HTTP istisnası bulunur.
