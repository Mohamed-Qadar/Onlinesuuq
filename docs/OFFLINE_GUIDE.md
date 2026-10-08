# Onlinesuuq: offline inventory guide

## English

1. Download **Onlinesuuq-Setup.exe** from the [latest release](https://github.com/Mohamed-Qadar/Onlinesuuq/releases/latest).
2. Run the installer, click **Install**, and open Onlinesuuq from the Start menu. You do not need to install Python, a database or Flutter.
3. Choose **English** at the top if needed. Somali is the initial language.
4. Choose **Add product**. Enter its name, optional SKU/category, selling price in USD and opening stock.
5. Use **Stock in** when new stock arrives, **Stock out** for damage or other removals, and **Record sale** when you sell an item. Sales reduce stock and appear in history. No money is transferred by the app.
6. Review **Stock & sales history**. Historical sales keep the price recorded at the time of sale. The stock value uses current selling prices; it is not profit or purchase cost.
7. Open the top-right menu and choose **Export backup** regularly. Keep a copy on a USB drive or another safe location. **Restore backup** replaces current inventory after confirmation; it does not merge two shops.

Data is private to the Windows user profile on this computer. Two PCs do not synchronize. Each new installation starts empty. Updates retain inventory; uninstall does not delete it. The **About / data location** menu shows the data folder. Only one app instance can open the inventory at a time; close the other window if startup reports a lock error.

To archive a product, first reduce its stock to zero. Its stock and sale history remains available. Mistaken sales cannot currently be edited or cancelled: record a stock-in adjustment with a note if physical stock must be corrected, but note that this does not reverse the recorded sales total.

The installer is unsigned, so Windows may show an unknown-publisher warning. Obtain it from this repository's Releases page. Requires Windows 10/11 x64.

![Example inventory with fictional products](previews/offline-inventory-en.png)

## Soomaali

1. Soo dejiso **Onlinesuuq-Setup.exe**, fur oo guji **Install**.
2. Ka fur Onlinesuuq liiska Start. Internet iyo akoon looma baahna.
3. Guji **Ku dar alaab**. Geli magaca, qiimaha USD iyo tirada bilowga.
4. Adeegso **Alaab soo gashay**, **Alaab baxday** iyo **Diiwaangeli iib** si aad kaydka u maamusho.
5. Ka eeg **Taariikhda kaydka iyo iibka** dhaqdhaqaaqa alaabta.
6. Menu-ga kore ka dooro **Dhoofin nuqul** oo nuqulka ku hay disk kale. **Soo celi nuqul** wuxuu beddelaa xogta hadda jirta.

Xogtu waxay ku kaydsan tahay kombiyuutarkaaga. Kombiyuutarradu iskuma xidhna, lacagna app-ku ma wareejiyo. Haddii aad rabto English, badhanka sare ka dooro.
