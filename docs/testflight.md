# Tutar 1.0 (12) — TestFlight metadata

## Beta Description — Turkish

Tutar; gelir, gider, bütçe, tekrar ve taksitleri takip etmek için tamamen ücretsiz, reklamsız ve açık kaynak bir iOS uygulamasıdır. Otomatik kuruşlu numaratör hızlı veri girişi sağlar. Taksitler ayrı bir sekme yerine işlemdeki Plan alanından, Tek sefer ve Tekrar seçeneklerinin yanında ayarlanır. Bağlı işlemler toplamı tam korur, 1/3 gibi sıra bilgisini gösterir ve tek taksit ya da bu ve sonrasını düzenleme/silme seçenekleri sunar. Dime/Tutar CSV içe aktarma, CSV dışa aktarma, tam JSON yedekleme, yerel saklama ve isteğe bağlı özel iCloud eşzamanlaması bulunur.

Tutar, Rafael Soh ve katkıda bulunanların oluşturduğu Dime temel alınarak değiştirilmiş GPLv3 çalışmasıdır. Değişiklik tarihi: 4 Ağustos 2026. Tam kaynak: https://github.com/furkancak1r/tutar-ios

## What to Test — Turkish

Build 12, kayıtlar ekranına Dime'ın güçlü toplam hiyerarşisinden esinlenen ancak Tutar'a özgü monokrom bir aylık özet getirir. Net toplam artık büyük odaktır; seçili ay rozet içinde, aylık hareket ince eğilim çizgisinde, harcama ve gelir ise sakin ikinci seviyede gösterilir. Önceki build'deki koyu mod, sağ alt hızlı kayıt, iki satırlı işlemler, Face ID geçişi ve numaratör titreşimi düzeltmeleri korunur. Gradient veya yeni tasarım bağımlılığı eklenmedi.

1. Kayıtlar ekranında net toplamın birincil odak olduğunu; seçili ay rozetinin, monokrom eğilim çizgisinin ve ikincil harcama/gelir değerlerinin açık ve koyu modda okunabildiğini doğrulayın.
2. Yeni kayıt düğmesinin sağ altta, sekme çubuğunun üstünde ve kolay erişilebilir kaldığını doğrulayın.
3. İşlem satırında notun üstte; kategori, kısa gün/ay tarihi ve taksit sırasının altta; tutarın sağda okunaklı göründüğünü kontrol edin. Tarihte yıl görünmemeli.
4. Bir satırı sola kaydırın; Düzenle ve Sil eylemlerinin koyu modda belirgin ve okunaklı olduğunu doğrulayın.
5. Ay özetini sağa/sola kaydırın; özet verilerinin ve çizginin seçilen aya güncellendiğini, animasyonlu geçişi ve dört sekmenin görünür kaldığını kontrol edin.
6. Ayarlar ekranını koyu modda inceleyin; başlıkların, seçimlerin, anahtarların ve para birimi kodunun okunaklı olduğunu doğrulayın.
7. İşlem editöründe Tuş titreşimi açıkken rakam ve silme tuşlarına basın; her dokunuşta hafif dokunsal geri bildirim gelmeli.
8. Türkçe ve English arayüzü, açık/koyu görünümü ve en büyük Dynamic Type boyutunu deneyin; en büyük boyutta özet ve işlem satırı okunabilir dikey düzene geçmeli.
9. Uygulama Kilidi'ni etkinleştirin; Face ID sırasında kilit ekranının arkada kaldığını, başarı işareti görünürken uygulamanın çizilmeye başladığını ve tek doğrulama sonrası yeniden kilitlenmediğini kontrol edin.
10. 3.000 TL, 3 taksit ve 18 Ağustos seçerek 18 Ağustos, 18 Eylül ve 18 Ekim'de tam üç bağlı işlem oluştuğunu doğrulayın.
11. Plan alanından tekrar oluşturun; aynı vade için mükerrer işlem oluşmadığını kontrol edin.
12. Özel emojili kategoriyle CSV ve tam JSON yedeğini dışa ve içe aktarın; emojinin korunduğunu doğrulayın.
13. TRY dışında bir ISO para birimi seçin ve seçimin uygulama yeniden açıldığında korunduğunu doğrulayın.
14. VoiceOver ile sekmeleri, ay düğmelerini, net toplamı, işlem satırlarını, kilit ekranını ve numaratörü gezin.

## Beta Description — English

Tutar is a completely free, ad-free, open-source iOS app for tracking income, expenses, budgets, repeats, and installments. Its automatic-cents keypad makes entry fast. Installments live in the transaction Schedule field beside One time and Repeat, rather than in a separate tab. Linked entries preserve the exact total, show positions such as 1/3, and support editing or deleting one installment or the selected installment and all following ones. Dime/Tutar CSV import, CSV export, complete JSON backup, local storage, and optional private iCloud sync are included.

Tutar is a GPLv3 modified work based on Dime, originally created by Rafael Soh and contributors. Modification date: 4 August 2026. Complete source: https://github.com/furkancak1r/tutar-ios

## What to Test — English

Build 12 adds a Tutar-specific monochrome monthly summary inspired by Dime's strong balance hierarchy. Net total is now the primary focus; the selected month appears in a pill, monthly movement in a restrained trend line, and spending/income as quiet secondary metrics. The previous build's dark-mode, bottom-right quick entry, two-line records, Face ID timing, and keypad-haptic fixes remain. No gradient or new design dependency was added.

1. Confirm net total is the primary focus and that the selected-month pill, monochrome trend, and secondary spent/income values remain readable in light and dark appearance.
2. Confirm the add button stays at the bottom-right above the tab bar and remains easy to reach.
3. In each record, verify the note is on top; category, abbreviated day/month date, and installment position are below; and the amount is readable on the right. The date must not include a year.
4. Swipe a record left and confirm Edit and Delete remain distinct and readable in dark mode.
5. Swipe the month summary left and right; confirm the values and trend update for the selected month, the transition animates, and all four tabs remain visible.
6. Inspect Settings in dark mode and confirm headings, picker values, switches, and the currency code are readable.
7. With Key haptics enabled, press number and delete keys in the editor; each tap should produce light haptic feedback.
8. Test Turkish and English, light and dark appearance, and the largest Dynamic Type size. At the largest size, summary values and records should adapt to a readable vertical layout.
9. Enable App Lock; confirm the lock screen stays behind Face ID, app content starts rendering during the success checkmark, and one successful authentication does not relock the app.
10. Enter 3,000, choose 3 installments and 18 August, then verify exactly three linked entries on 18 August, 18 September, and 18 October.
11. Create a repeat from Schedule and confirm a due date is materialized only once.
12. Export and import CSV and complete JSON backup with a custom category emoji; confirm the emoji is preserved.
13. Choose a non-default ISO currency and confirm the choice persists after relaunch.
14. Navigate tabs, month controls, net total, transaction rows, the lock screen, and the keypad with VoiceOver.

Feedback email: furkancakr7@gmail.com

Source and GPLv3 license: https://github.com/furkancak1r/tutar-ios
