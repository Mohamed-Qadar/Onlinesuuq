# Offline Windows inventory (1.1.0)

The desktop release now works without an API or account. Build with:

```powershell
.\packaging\windows\Build-Setup.ps1 -Mode offline
```

GitHub Actions: Build Windows Setup > Run workflow > mode: offline. This builds the installer, checks silent installation/native startup/uninstall, and optionally creates a draft release.

Users can add products, record stock in/out and sales, and export/restore JSON backups. Restore replaces the current inventory after confirmation. Data is kept outside the install folder and retained on uninstall; the app's About menu shows its location. Somali and English are included. Online orders, payments and cloud sync are not included. Keep backups for a future explicit data migration.

---

## Original online client instructions

The API instructions below apply only to online builds. Pass `-Mode online` to Build-Setup.ps1.

# Onlinesuuq: Windows Release ve tek Setup.exe

Windows kaynakları `mobile/windows/`, kurulum betikleri `packaging/windows/` altındadır. Bu paket Flutter istemcisini kurar; Django/PostgreSQL canlı sunucuda kalır. Kullanıcıya Python, Docker, Flutter veya PostgreSQL kurdurulmaz. İlk giriş/sipariş işlemleri için internet gerekir.

## 1. Geliştirici bilgisayarına gerekli araçlar

- Flutter 3.47.6 (bu çalışma alanında `.tools/flutter`).
- [Visual Studio Community](https://visualstudio.microsoft.com/downloads/): **Desktop development with C++** iş yükünü; MSVC x64/x86, Windows SDK ve CMake araçlarını içerecek şekilde kurun. VS Code tek başına yeterli değildir.
- [Inno Setup 6.3 veya üzeri](https://jrsoftware.org/isdl.php). Aşağıdaki komut varsayılan `C:\Program Files (x86)\Inno Setup 6\ISCC.exe` yolunu kullanır; başka konuma kurduysanız yolu değiştirin.
- Windows Ayarlar'da **Geliştirici Modu / Developer Mode** açık olmalıdır; Flutter eklentileri symlink kullanır. Ayarlar aramasına “Geliştirici Modu” yazıp açın. Bu bilgisayarda kontrol sırasında kapalıydı.

Windows platform dosyaları zaten üretildi; tekrar `flutter create` çalıştırmanız gerekmez. Gelecekte sıfırdan platform ekleme komutu `flutter create --platforms=windows --no-pub .` şeklindedir. Bu komut yeni örnek counter testi oluşturursa yalnız üretilen örnek testi kaldırın; uygulamanın mevcut testlerini silmeyin.

## 2. Sıralı derleme komutları (x64 Windows, 64-bit PowerShell)

```powershell
Set-Location 'C:\Users\Moha-qadar\OneDrive\Desktop\E-ticaret'
$env:Path = "$(Get-Location)\.tools\flutter\bin;$env:Path"
flutter config --enable-windows-desktop
flutter doctor -v
Set-Location mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test

# Yer tutucuyu GERÇEK canlı Django HTTPS adresinizle değiştirin.
$apiUrl = 'https://YOUR_REAL_API_HOST/api/v1/'
flutter build windows --release "--dart-define=API_URL=$apiUrl"
if ($LASTEXITCODE -ne 0) { throw 'Release derlemesi başarısız; paketlemeye geçmeyin.' }

# App-local Visual C++ runtime DLL'lerini aynı klasöre koyar.
& ..\packaging\windows\Copy-VCRuntime.ps1

# Önce uygulamayı test edin:
& .\build\windows\x64\runner\Release\Onlinesuuq.exe
```

Komutları sırayla çalıştırın; bir adım hata verirse sonraki adıma geçmeyin. `doctor` içinde Visual Studio Windows desteği başarılı olmalıdır. Sadece Windows için Android SDK zorunlu değildir. Flutter PATH'te zaten kuruluysa `$env:Path` satırına gerek yoktur. PowerShell betik çalıştırma politikası yerel dosyaları engelliyorsa dosyaları inceleyip bu oturum için `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned` kullanabilirsiniz; kurum politikalarını aşmayın.

`API_URL` gizli anahtar değildir, exe'den okunabilir. Yalnız genel HTTPS API adresini yazın; DB parolası, SECRET_KEY veya yönetici token'ı eklemeyin. `127.0.0.1`/`10.0.2.2` son kullanıcının bilgisayarında sizin backend'inize ulaşmaz. GitHub repo URL'si Django API adresi değildir. Canlı URL paylaşılmadığı için hazır komutta yer tutucu bulunur.

Derleme klasörü:

```text
mobile/build/windows/x64/runner/Release/
  Onlinesuuq.exe
  flutter_windows.dll
  ... plugin DLL files ...
  msvcp140.dll
  vcruntime140.dll
  vcruntime140_1.dll
  ... additional CRT DLL files ...
  data/
```

`Copy-VCRuntime.ps1` DLL'leri kurulu Visual Studio'nun **redistributable x64 CRT** dizininden alır. Farklı toolchain kullanıyorsanız `-CrtDirectory 'C:\...\x64\Microsoft.VC143.CRT'` verin. Derlediğiniz toolchain ile uyumlu runtime ve Microsoft yeniden dağıtım koşullarını kullanın. İnternetteki rastgele DLL sitelerini veya System32'yi kaynak olarak kullanmayın. Bütün Release klasörü paketlenir; tek başına uygulama exe'si yeterli değildir.

## 3. Inno Setup

Hazır dosya: `packaging/windows/Onlinesuuq.iss`.

Inno Setup Compiler'da **File → Open** ile bu dosyayı açıp **Build → Compile (F9)** seçin. Varsayılan sürüm 1.0.0'dır. Uygulama/CRT dosyaları eksikse script derlemeyi durdurur. Varsayılan çıktı proje kökündeki `dist/Onlinesuuq-Setup.exe` olur.

Terminalden aynı işlem:

```powershell
Set-Location 'C:\Users\Moha-qadar\OneDrive\Desktop\E-ticaret'
& 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' '/DMyAppVersion=1.0.0' '.\packaging\windows\Onlinesuuq.iss'
```

Installer İngilizcedir. Uygulamanın Somalice/English seçenekleri değişmez. Şirket adı veya kurumsal sertifika varsayımı yoktur. Kurulum kullanıcının `%LOCALAPPDATA%\Programs\Onlinesuuq` klasörüne yapılır, yönetici izni istemez. Başlat menüsü kısayolu ve isteğe bağlı masaüstü kısayolu eklenir. Windows uygulama kaldırma ekranından kaldırılabilir. Kullanıcı verileri/token depoları otomatik olarak silinmez; paylaşılan bilgisayarda kaldırmadan önce uygulamadan çıkış yapın.

Gelecek sürümlerde `.iss` içindeki **AppId'yi değiştirmeyin**. `pubspec.yaml` sürümünü artırın, derlemeyi yenileyin ve installer'a aynı sürümü verin. Eski sürümü çalışırken yükseltme, kaldırma ve yeniden kurma davranışlarını ayrıca test edin. Dijital imza eklenmedi; Windows indirilen imzasız dosyada yayıncı/SmartScreen uyarısı gösterebilir. Bu hazırlık imza veya güven itibarı sağlamaz.

## 4. Hepsini yapan yardımcı komut

Araçlar kurulduktan sonra, proje kökünde:

```powershell
.\packaging\windows\Build-Setup.ps1 -ApiUrl 'https://YOUR_REAL_API_HOST/api/v1/'
```

Bu script `pubspec.yaml` sürümünü okur, HTTPS adres biçimini kontrol eder, bağımlılıkları doğrular, analyze/test çalıştırır, x64 Release derler, CRT kopyalar ve Inno Setup'ı çağırır. Herhangi bir hata varsa durur. Başarılı olursa:

- `dist/Onlinesuuq-Setup.exe`
- `dist/Onlinesuuq-Setup.exe.sha256`

İsteğe bağlı `-InnoCompiler` ve `-CrtDirectory` parametreleri vardır. API'nin gerçekte çalıştığını veya sertifikasının doğruluğunu sadece URL biçim kontrolü kanıtlamaz; uygulamayla canlı uçları test edin.

## 5. Temiz Windows bilgisayarda test

Visual Studio/Flutter kurulu olmayan Windows 10/11 x64 bilgisayarda veya VM'de Setup'ı çalıştırın. Başlat menüsü, masaüstü kısayolu, normal kullanıcı kurulumu, API girişi/token yenileme, ürün dosya seçimi/yükleme, paylaşım, misafir siparişi ve ağ kesilmesi akışlarını deneyin. Uygulamayı kapatıp açın; ardından yükseltme/kaldırmayı kontrol edin. `x64compatible` ARM64 üzerinde x64 emülasyonuna da izin verebilir; bu paket native ARM64 olarak derlenmiş değildir ve ARM64 cihazda doğrulanmamıştır.

## 6. GitHub Releases: tarayıcıdan yükleme

Önce kaynak kodunun doğru son commit'ini `Mohamed-Qadar/Onlinesuuq` reposuna yükleyin. `.env`, `.local`, `.venv`, `.tools`, özel anahtarlar ve veritabanı yedeklerini yüklemeyin. `mobile/windows/` ve `packaging/windows/` kaynakları repoya girer; `dist/` ve `mobile/build/` Git dışında kalır. Setup, repo dosyasına değil **Release asset** olarak yüklenir.

1. GitHub hesabınızla giriş yapıp [repo yayınlarını](https://github.com/Mohamed-Qadar/Onlinesuuq/releases) açın.
2. **Draft a new release** veya ilk yayın için **Create a new release** düğmesine basın.
3. **Choose a tag** alanında `v1.0.0` yazıp **Create new tag** seçin. Target olarak bu sürümün kaynak kodunu içeren branch/commit'i seçin. Var olan bir tag'i başka sürüm için yeniden kullanmayın.
4. Başlık: `Onlinesuuq 1.0.0 — Windows`. Açıklama: desteklenen sistem (Windows x64), Somalice/English, internet gereksinimi, yenilikler ve varsa bilinen eksikler.
5. Dosya ekleme alanına `dist/Onlinesuuq-Setup.exe` dosyasını sürükleyin. İsterseniz SHA256 dosyasını da ekleyin. Yüklemenin bitmesini bekleyin.
6. Genel kararlı sürüm için **pre-release** işaretlemeyin; varsa **Set as latest release** seçin. Henüz test edilmediyse draft olarak saklayın veya pre-release yayımlayın.
7. **Publish release** seçin. Yayındaki **Assets** bölümünde gerçek Setup dosyasının göründüğünü doğrulayın. Otomatik `Source code (zip)` dosyası kurulum değildir.

**Yüklemeden sonra çalışacak sürüme özel indirme linki:**

```text
https://github.com/Mohamed-Qadar/Onlinesuuq/releases/download/v1.0.0/Onlinesuuq-Setup.exe
```

**En güncel kararlı sürümün indirme linki:**

```text
https://github.com/Mohamed-Qadar/Onlinesuuq/releases/latest/download/Onlinesuuq-Setup.exe
```

İkinci link için her kararlı yayında dosya adını **Onlinesuuq-Setup.exe** olarak koruyun ve doğru yayını Latest yapın. Bu dosyalar henüz yüklenmediği için linklerin şu anda çalıştığı iddia edilmez. Herkesin giriş yapmadan indirebilmesi için repo public olmalıdır; private repo asset'leri erişim yetkisi ister. Yayın sonrası linki oturum açılmamış tarayıcıda deneyin.

Repo README'sine eklenebilecek bağlantı:

```markdown
[Download Onlinesuuq for Windows](https://github.com/Mohamed-Qadar/Onlinesuuq/releases/latest/download/Onlinesuuq-Setup.exe)
```

## Doğrulama sınırı ve kaynaklar

Windows runner dosyaları bu çalışma alanında üretildi. 12 Flutter testi geçti; iki PowerShell scriptinin sözdizimi doğrulandı. Mevcut pubspec ile uyuşmayan eksik lock dosyası yeniden çözümlendi; doğrudan paket sürümleri değiştirilmedi. Windows plugin hazırlığı Developer Mode/symlink hatası verdi. Visual Studio C++ toolchain ve Inno Setup da bulunmadığından native Release, `.iss` derlemesi, Setup kurulumu/yükseltmesi ve canlı API bağlantısı burada doğrulanmadı. Gerçek API adresi de verilmedi. GitHub'a yayın yapılmadı ve repo erişimi web üzerinden doğrulanamadı.

Resmî kaynaklar: [Flutter Windows kurulumu](https://docs.flutter.dev/platform-integration/windows/setup), [Flutter Windows dağıtımı ve CRT](https://docs.flutter.dev/platform-integration/windows/building), [Inno kurulum ayrıcalıkları](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm), [GitHub Release oluşturma](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository), [Release indirme bağlantıları](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases).
