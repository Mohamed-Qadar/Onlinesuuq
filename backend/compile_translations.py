"""Compile project translations without requiring a system gettext installation."""
import ast
from pathlib import Path
import polib

ROOT = Path(__file__).parent
SO = {
    'Order total exceeds the supported limit.': 'Wadarta dalabku waxay dhaaftay xadka la oggol yahay.',
    'This field is required.': 'Goobtan waa khasab.',
    'This field may not be blank.': 'Goobtan madhan lagama tagi karo.',
    'This field may not be null.': 'Goobtan waa inay leedahay qiime.',
    'Enter a valid email address.': 'Geli cinwaan iimayl sax ah.',
    'A valid integer is required.': 'Geli tiro dhan oo sax ah.',
    'A valid number is required.': 'Geli tiro sax ah.',
    'Must be a valid boolean.': 'Dooro haa ama maya.',
    'No active account found with the given credentials': 'Akoon firfircoon laguma helin xogtan gelitaanka.',
    'Authentication credentials were not provided.': 'Xogta gelitaanka lama bixin.',
    'You do not have permission to perform this action.': 'Uma lihid oggolaansho ficilkan.',
    'Not found.': 'Lama helin.',
    'The submitted data was not a file. Check the encoding type on the form.': 'Xogta la soo diray ma aha fayl sax ah.',
    'No file was submitted.': 'Fayl lama soo dirin.',
    'Ensure this field has no more than {max_length} characters.': 'Goobtan ha ka badnaan {max_length} xaraf.',
    'Ensure this field has at least {min_length} characters.': 'Goobtan ha lahaato ugu yaraan {min_length} xaraf.',
    'Ensure this value is greater than or equal to {min_value}.': 'Qiimuhu waa inuu ahaadaa {min_value} ama ka badan.',
    'Ensure this value is less than or equal to {max_value}.': 'Qiimuhu waa inuu ahaadaa {max_value} ama ka yar.',
    'This password is too common.': 'Furahan sirta ah aad ayaa loo isticmaalaa.',
    'This password is entirely numeric.': 'Furahan sirta ah wuxuu ka kooban yahay tirooyin keliya.',
    'Stock changed or needs a fresh version. Reload the product before editing.': 'Kaydku wuu is beddelay. Dib u soo geli alaabta ka hor tafatirka.',
    'New': 'Cusub', 'Accepted': 'La aqbalay', 'Preparing': 'La diyaarinayo', 'Delivered': 'La gaarsiiyey',
    'Cancelled': 'La joojiyey', 'Unpaid': 'Lama bixin', 'Paid — seller confirmed': 'Waa la bixiyey — iibiyaha ayaa xaqiijiyey',
    'Refund required': 'Lacag celin ayaa loo baahan yahay', 'Refunded — seller confirmed': 'Lacagta waa la celiyey',
    'Pickup': 'Soo qaado', 'Delivery': 'Gaarsiin', 'Session expired.': 'Fadhigu wuu dhacay.',
    'This store is unavailable.': 'Dukaankan hadda lama heli karo.',
    'Duplicate products are not allowed.': 'Alaab isku mid ah laba jeer lama gelin karo.',
    'A product is unavailable.': 'Alaab ayaa hadda aan la heli karin.',
    'Insufficient stock.': 'Kaydku kuma filna.',
    'Choose a delivery region and enter an address.': 'Dooro aagga gaarsiinta oo geli cinwaanka.',
    'This checkout key was already used for different details.': 'Furahan dalabka hore ayaa loogu isticmaalay xog kale.',
    'Review the latest total and confirm again.': 'Hubi wadarta cusub oo mar kale xaqiiji.',
    'Prices or order details changed. Review the latest total and confirm again.': 'Qiimaha ama xogta dalabka ayaa is beddelay. Hubi wadarta cusub oo xaqiiji.',
    'Invalid order transition.': 'Isbeddelkan dalabka lama oggola.',
    'Insufficient stock or unavailable product.': 'Kaydku kuma filna ama alaabta lama heli karo.',
    'Explicit confirmation is required.': 'Xaqiijin cad ayaa loo baahan yahay.',
    'Payment cannot be confirmed for this order.': 'Lacag bixinta dalabkan lama xaqiijin karo.',
    'No refund is awaiting confirmation.': 'Ma jiro lacag celin sugaysa xaqiijin.',
    'Only an administrator may correct a payment, with a reason.': 'Maamulaha oo keliya ayaa sixi kara lacag bixinta isagoo sabab sheegaya.',
    'Complete your store profile before publishing.': 'Dhammaystir xogta dukaanka ka hor daabicidda.',
    'Add an available published product first.': 'Marka hore ku dar alaab kayd leh oo la daabacay.',
    'Images must be at most 5 MB.': 'Sawirku kama weynaan karo 5 MB.',
    'Upload a valid JPEG, PNG or WebP image.': 'Soo geli sawir sax ah oo JPEG, PNG ama WebP ah.',
    'This email is already registered.': 'Iimaylkan horay ayaa loo diiwaangeliyey.',
    'Passwords do not match.': 'Furayaasha sirta ah isma waafaqaan.',
    'Enter a list of delivery regions.': 'Geli liiska aagagga gaarsiinta.',
    'This product code is already used.': 'Koodhkan alaabta hore ayaa loo isticmaalay.',
    'The product must belong to this store.': 'Alaabtu waa inay ka tirsan tahay dukaankan.',
    'Current password is incorrect.': 'Furaha sirta ah ee hadda waa khalad.',
    'Invalid reset code or password.': 'Koodhka ama furaha sirta ah waa khalad.',
    'You already have a store.': 'Waxaad horay u leedahay dukaan.',
    'This store code is already used.': 'Koodhkan dukaanka hore ayaa loo isticmaalay.',
    'Choose an image.': 'Dooro sawir.',
    'A product can have at most three photos.': 'Alaabtu waxay yeelan kartaa ugu badnaan saddex sawir.',
    'Guest session expired.': 'Fadhiga martida wuu dhacay.',
    'Use an international phone number, for example +252612345678.': 'Isticmaal lambar caalami ah, tusaale +252612345678.',
}
messages = set(SO)
for source in (ROOT / 'shop').glob('*.py'):
    for node in ast.walk(ast.parse(source.read_text(encoding='utf8'))):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == '_' and node.args and isinstance(node.args[0], ast.Constant):
            messages.add(node.args[0].value)
for language in ['so', 'en']:
    path = ROOT / 'locale' / language / 'LC_MESSAGES'
    path.mkdir(parents=True, exist_ok=True)
    po = polib.POFile()
    po.metadata = {'Content-Type': 'text/plain; charset=UTF-8', 'Language': language,
        'Plural-Forms': 'nplurals=2; plural=(n != 1);'}
    for msg in sorted(messages):
        po.append(polib.POEntry(msgid=msg, msgstr=SO.get(msg, msg) if language == 'so' else msg))
    po.save(str(path / 'django.po'))
    po.save_as_mofile(str(path / 'django.mo'))
