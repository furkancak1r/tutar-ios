# Tutar 1.0 (10) — TestFlight metadata

## Beta Description — Turkish

Tutar; gelir, gider, bütçe, tekrar ve taksitleri takip etmek için tamamen ücretsiz, reklamsız ve açık kaynak bir iOS uygulamasıdır. Otomatik kuruşlu numaratör hızlı veri girişi sağlar. Taksitler ayrı bir sekme yerine işlemdeki Plan alanından, Tek sefer ve Tekrar seçeneklerinin yanında ayarlanır. Bağlı işlemler toplamı tam korur, 1/3 gibi sıra bilgisini gösterir ve tek taksit ya da bu ve sonrasını düzenleme/silme seçenekleri sunar. Dime/Tutar CSV içe aktarma, CSV dışa aktarma, tam JSON yedekleme, yerel saklama ve isteğe bağlı özel iCloud eşzamanlaması bulunur.

Tutar, Rafael Soh ve katkıda bulunanların oluşturduğu Dime temel alınarak değiştirilmiş GPLv3 çalışmasıdır. Değişiklik tarihi: 4 Ağustos 2026. Tam kaynak: https://github.com/furkancak1r/tutar-ios

## What to Test — Turkish

Build 10, Apple tasarım ilkeleri doğrultusunda daha sade ve profesyonel bir arayüz sunar. Büyük kartlar azaltıldı, veri hiyerarşisi sıkılaştırıldı, işlem ve bütçe satırları tek satıra uygun hâle getirildi, grafik etiketleri düzeltildi ve iPad içerik genişliği dengelendi. Gradient veya yeni tasarım bağımlılığı eklenmedi.

1. Kayıtlar ekranında not, kategori, taksit sırası ve tutarın tek satırda kaldığını doğrulayın.
2. Ay özetini sağa/sola kaydırın; animasyonlu geçişi ve dört sekmenin görünür kaldığını kontrol edin.
3. Analiz ekranında tek günlük verinin yalnız bir gün etiketi ve dar bir grafik sütunuyla gösterildiğini doğrulayın.
4. Bütçe satırlarında harcanan ve kalan tutarların kompakt, okunabilir ve taşmasız kaldığını kontrol edin.
5. İşlem editörünü iPhone ve iPad’de açın; numaratörün dengeli genişlikte ve onay düğmesinin açık/koyu görünümde okunaklı olduğunu doğrulayın.
6. Türkçe ve English arayüzü, açık/koyu görünümü ve en büyük Dynamic Type boyutunu deneyin.
7. Uygulama Kilidi’ni etkinleştirin; Face ID sırasında kilit ekranının arkada kaldığını ve tek doğrulama sonrası yeniden kilitlenmediğini kontrol edin.
8. 3.000 TL, 3 taksit ve 18 Ağustos seçerek 18 Ağustos, 18 Eylül ve 18 Ekim’de tam üç bağlı işlem oluştuğunu doğrulayın.
9. Plan alanından tekrar oluşturun; aynı vade için mükerrer işlem oluşmadığını kontrol edin.
10. Özel emojili kategoriyle CSV ve tam JSON yedeğini dışa ve içe aktarın; emojinin korunduğunu doğrulayın.
11. TRY dışında bir ISO para birimi seçin ve seçimin uygulama yeniden açıldığında korunduğunu doğrulayın.
12. VoiceOver ile sekmeleri, ay düğmelerini, işlem satırlarını, kilit ekranını ve numaratörü gezin.

## Beta Description — English

Tutar is a completely free, ad-free, open-source iOS app for tracking income, expenses, budgets, repeats, and installments. Its automatic-cents keypad makes entry fast. Installments live in the transaction Schedule field beside One time and Repeat, rather than in a separate tab. Linked entries preserve the exact total, show positions such as 1/3, and support editing or deleting one installment or the selected installment and all following ones. Dime/Tutar CSV import, CSV export, complete JSON backup, local storage, and optional private iCloud sync are included.

Tutar is a GPLv3 modified work based on Dime, originally created by Rafael Soh and contributors. Modification date: 4 August 2026. Complete source: https://github.com/furkancak1r/tutar-ios

## What to Test — English

Build 10 introduces a cleaner, more professional interface aligned with Apple design guidance. Large cards were reduced, data hierarchy was tightened, transaction and budget rows were made single-line friendly, chart labels were corrected, and iPad content width was balanced. No gradient or new design dependency was added.

1. Confirm note, category, installment position, and amount stay on one line in Records.
2. Swipe the month summary left and right; verify the animated transition and that all four tabs remain visible.
3. In Analysis, confirm a single day produces one day label and a narrow chart bar.
4. Check that spent and remaining values in Budget rows stay compact, readable, and unclipped.
5. Open the transaction editor on iPhone and iPad; verify the keypad width and submit-button contrast in light and dark appearance.
6. Test Turkish and English, light and dark appearance, and the largest Dynamic Type size.
7. Enable App Lock; confirm the lock screen remains behind Face ID and one successful authentication does not relock the app.
8. Enter 3,000, choose 3 installments and 18 August, then verify exactly three linked entries on 18 August, 18 September, and 18 October.
9. Create a repeat from Schedule and confirm a due date is materialized only once.
10. Export and import CSV and complete JSON backup with a custom category emoji; confirm the emoji is preserved.
11. Choose a non-default ISO currency and confirm the choice persists after relaunch.
12. Navigate tabs, month controls, transaction rows, the lock screen, and the keypad with VoiceOver.

Feedback email: furkancakr7@gmail.com

Source and GPLv3 license: https://github.com/furkancak1r/tutar-ios
