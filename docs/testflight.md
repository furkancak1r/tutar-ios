# Tutar 1.0 (9) — TestFlight metadata

## Beta Description — Turkish

Tutar; gelir, gider, bütçe, tekrar ve taksitleri takip etmek için tamamen ücretsiz, reklamsız ve açık kaynak bir iOS uygulamasıdır. Otomatik kuruşlu numaratör hızlı veri girişi sağlar. Taksitler ayrı bir sekme yerine işlemdeki Plan alanından, Tek sefer ve Tekrar seçeneklerinin yanında ayarlanır. Bağlı işlemler toplamı tam korur, 1/3 gibi sıra bilgisini gösterir ve tek taksit ya da bu ve sonrasını düzenleme/silme seçenekleri sunar. Dime/Tutar CSV içe aktarma, CSV dışa aktarma, tam JSON yedekleme, yerel saklama ve isteğe bağlı özel iCloud eşzamanlaması bulunur.

Tutar, Rafael Soh ve katkıda bulunanların oluşturduğu Dime temel alınarak değiştirilmiş GPLv3 çalışmasıdır. Değişiklik tarihi: 4 Ağustos 2026. Tam kaynak: https://github.com/furkancak1r/tutar-ios

## What to Test — Turkish

Build 9, işlem ve kategori listelerindeki emojileri renkli yuvarlak arka plan olmadan doğrudan gösterir. İşlem CSV’si artık kategori emojisini de dışa ve içe aktarır; eski Dime/Tutar CSV dosyaları geriye uyumlu kalır. Tam JSON yedeği, değiştirilmiş hazır kategori emojilerini de geri yükler.

1. 3.000 TL, 3 taksit ve ilk tarih 18 Ağustos seçerek tam üç işlemin 18 Ağustos, 18 Eylül ve 18 Ekim’e oluşturulduğunu doğrulayın.
2. Kuruşla tam bölünmeyen bir tutarda farkın yalnız son taksite verildiğini kontrol edin.
3. Tek taksiti ve “bu ve sonrası” kapsamını ayrı ayrı düzenleyin/silin; mükerrer kayıt oluşmamalı.
4. Gelecek taksitlerin ayrı bölümde kaldığını ve yalnız ait oldukları ayın analizine girdiğini kontrol edin.
5. Plan alanında günlük/haftalık/aylık tekrar oluşturun; aynı vade için mükerrer işlem oluşmadığını doğrulayın.
6. Bütçe ve kategori ekleme/düzenlemeyi; bir kategoriyi silince eski işlemlerin korunmasını deneyin.
7. Dime CSV içe aktarmayı iki kez yapıp ikinci geçişte mükerrerlerin atlandığını; CSV ve tam JSON yedeğin dışa aktarılabildiğini kontrol edin.
8. Ayarlar’dan Sistem, Türkçe ve English seçeneklerini; açık/koyu modu; iCloud kapatma/açma sonrası yeniden başlatmayı deneyin.
9. iPhone ve iPad’de büyük metin/VoiceOver ile taşma veya etiketsiz denetim bildirin.
10. Ayarlar > Kategoriler > Kategori ekle akışında “Simge veya emoji” alanına dokununca emoji klavyesinin doğrudan açıldığını doğrulayın.
11. Ay özetini sağa/sola kaydırarak ay değiştirmeyi; uzun kayıtların tek satırda kaldığını ve kırpılan metnin VoiceOver’da tam okunduğunu kontrol edin.
12. Para birimi listesinden TRY dışında bir ISO para birimi seçin; Türkçe arayüzde seçimin korunduğunu doğrulayın.
13. Uygulama Kilidi’ni açın, Tutar’ı arka plana gönderip geri dönün ve Face ID sırasında uygulamanın yeniden kilitlenmeden, ikinci istem açmadan tek doğrulamayla açıldığını doğrulayın.
14. Açık ve koyu görünümde yeni siyah-beyaz temayı; ikon ve widget dahil hiçbir ana vurgu alanında mavi/gradient kalmadığını kontrol edin.
15. Soğuk açılışta uygulama logosu veya spinner yerine sabit kilit simgesi ve kilit metninin göründüğünü; Face ID penceresi açılırken ekranın yeniden yükleniyormuş gibi değişmediğini doğrulayın.
16. Face ID penceresi açıkken arka planda iskelet yükleme görünümü yerine kilit ekranının kaldığını; başarılı yüz eşleşmesinden sonra doğrudan Kayıtlar ekranına geçildiğini doğrulayın.
17. İşlem ve Ayarlar > Kategoriler listelerinde emojilerin yuvarlak renkli bir zemin olmadan doğrudan göründüğünü kontrol edin.
18. Özel emojili bir kategoriyle işlem oluşturun; CSV ve tam JSON yedeğini dışa aktarıp yeniden içe aldığınızda emojinin korunduğunu doğrulayın.

## Beta Description — English

Tutar is a completely free, ad-free, open-source iOS app for tracking income, expenses, budgets, repeats, and installments. Its automatic-cents keypad makes entry fast. Installments live in the transaction Schedule field beside One time and Repeat, rather than in a separate tab. Linked entries preserve the exact total, show positions such as 1/3, and support editing or deleting one installment or the selected installment and all following ones. Dime/Tutar CSV import, CSV export, complete JSON backup, local storage, and optional private iCloud sync are included.

Tutar is a GPLv3 modified work based on Dime, originally created by Rafael Soh and contributors. Modification date: 4 August 2026. Complete source: https://github.com/furkancak1r/tutar-ios

## What to Test — English

Build 9 displays emoji directly in transaction and category lists without a colored circular background. Transaction CSV now exports and imports category emoji while remaining compatible with older Dime/Tutar CSV files. Complete JSON backups also restore edited emoji on built-in categories.

1. Enter a total of 3,000, choose 3 installments and 18 August, then verify exactly three linked entries on 18 August, 18 September, and 18 October.
2. Use a total that does not divide evenly into cents and confirm only the last installment receives the remainder.
3. Edit/delete one installment and “this and following”; no duplicate entries should appear.
4. Confirm future installments are separate and affect only their own calendar month.
5. Create daily, weekly, and monthly repeats from Schedule and confirm a due date is materialized only once.
6. Add/edit budgets and categories; deleting a category must preserve its old transactions.
7. Import a Dime CSV twice and confirm duplicates are skipped, then test transaction CSV and complete JSON backup export.
8. Test System, Turkish, and English language choices, light/dark appearance, and an iCloud sync change followed by relaunch.
9. Report clipping or unlabeled controls with large text or VoiceOver on iPhone and iPad.
10. In Settings > Categories > Add category, tap “Symbol or emoji” and confirm the emoji keyboard opens directly.
11. Swipe the month summary left/right to change months; confirm long records stay on one line and VoiceOver reads truncated content in full.
12. Choose a non-default ISO currency and confirm the choice remains active in both English and Turkish.
13. Enable App Lock, background and reopen Tutar, then confirm one Face ID/device-authentication attempt unlocks it without relocking or showing a second prompt.
14. Check the new black-and-white theme in light and dark appearance, including the icon and widget; there should be no blue primary accent or gradient.
15. Cold-launch the app and confirm the fixed lock symbol and text appear instead of the app logo or a spinner, with no refresh-like visual change when the Face ID prompt opens.
16. While the Face ID prompt is open, confirm the lock screen remains behind it instead of a skeleton loading view, then send a successful match and verify Records appears directly.
17. In Records and Settings > Categories, confirm emoji appear directly without a colored circular background.
18. Create a transaction in a category with a custom emoji, export and re-import both CSV and complete JSON backups, and confirm the emoji is preserved.

Feedback email: furkancakr7@gmail.com

Source and GPLv3 license: https://github.com/furkancak1r/tutar-ios
