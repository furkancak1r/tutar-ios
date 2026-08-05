# Tutar 1.0 (24) — TestFlight metadata

## Beta Description — Turkish

Tutar; gelir, gider, bütçe, tekrar ve taksitleri takip etmek için tamamen ücretsiz, reklamsız ve açık kaynak bir iOS uygulamasıdır. İlk açılıştaki dört kısa sayfa kayıtları, Plan alanındaki tekrar/taksit seçeneklerini, bütçelerin işlem oluşturmadığını ve Tutar’ın gizlilik yaklaşımını açıklar. Taksitler ayrı bir sekme yerine işlemdeki Plan alanından ayarlanır. Dime/Tutar CSV içe aktarma, CSV dışa aktarma, tam JSON yedekleme, yerel saklama ve isteğe bağlı özel iCloud eşzamanlaması bulunur.

Tutar, Rafael Soh ve katkıda bulunanların oluşturduğu Dime temel alınarak değiştirilmiş GPLv3 çalışmasıdır. Bu buildin değişiklik tarihi: 5 Ağustos 2026. Tam kaynak: https://github.com/furkancak1r/tutar-ios

## What to Test — Turkish

Build 24, onboarding alt navigasyonunu daha minimal hâle getirir. İlk sayfadaki İleri düğmesi gerçek merkeze alındı; büyük dolgulu geri düğmesi yerine 44 pt erişilebilir dokunma alanını koruyan sade bir chevron kullanıldı. İleri ve başla eylemleri içerik genişliğinde kompakt kapsüllere dönüştürüldü. 36 unit ve 21 UI testlik tam paket geçti. Tutar, Rafael Soh ve katkıda bulunanların Dime uygulamasını temel alan GPLv3 türev çalışmadır. Değişiklik: 5 Ağustos 2026. Kaynak: https://github.com/furkancak1r/tutar-ios

1. Güncellemeden sonraki ilk açılışta onboarding’in görünmesini; dört sayfanın yatay kaydırma ve İleri/Geri düğmeleriyle çalışmasını doğrulayın.
2. Onboarding’i yarıda kapatıp yeniden açın; tekrar başlamalıdır. Atla veya Tutar’ı Kullanmaya Başla sonrasında yeniden görünmemelidir.
3. Ayarlar → Bilgi → Tutar’ı Tanı ile onboarding’i tekrar açın; kapatınca Ayarlar’a dönmelidir.
4. Uygulama Kilidi açıksa önce yalnız kilit ekranının görünmesini, doğrulama başarıyla bitince onboarding’in açılmasını kontrol edin.
5. Türkçe/English, açık/koyu görünüm, büyük metin ve VoiceOver ile sayfaları; monokrom kontrolleri ve taşmayan kaydırılabilir içeriği doğrulayın.

1. Gider, gelir veya kategori filtresi seçin; sağ üst filtre simgesinin monokrom temizleme simgesine dönüştüğünü ve tek dokunuşla filtreyi kaldırdığını doğrulayın.
2. Yeni işlemde boş sağ kenarda sola, boş sol kenarda sağa kaydırın; Gider/Gelir türünün değiştiğini, numaratör veya form üzerindeki hareketlerin türü değiştirmediğini doğrulayın.
3. Analiz'in aylık görünümünde sütunların ve eksen etiketlerinin çakışmadığını doğrulayın; gerçek bir sütuna dokunup doğru işlem satırlarının üç saniye kenarlıkla vurgulandığını kontrol edin.
4. Grafiğin boş bir gününe dokunun; sekmenin değişmediğini doğrulayın.
5. Yaklaşanlar, Bugün, Dün ve tarih başlıklarına dokunarak her grubun diğerlerinden bağımsız açılıp kapandığını doğrulayın.
6. Yaklaşan satırlarda emoji dahil tüm bilgi hiyerarşisinin geçmiş kayıtlardan daha pasif, fakat okunabilir olduğunu doğrulayın.
7. Bütçeler ekranında bilgi düğmesine dokunun; açıklama balonunun açılıp dışarı dokununca kapandığını doğrulayın.
8. İşlem ve bütçe tutarında 425 yazın; 425,00 gösterildiğini ve değerin silme düğmesine rağmen ekranın ortasında kaldığını doğrulayın.

1. Ayarlar → Kategoriler ekranında Gider/Gelir seçiminin listeleri doğru ayırdığını doğrulayın.
2. Önerilenler başlığındaki göz düğmesiyle listeyi gizleyip yeniden gösterin; düğmenin her iki durumda da erişilebilir kaldığını doğrulayın.
3. Önerilenler bölümünden Konut ve Serbest Çalışma kategorilerini ekleyin; tek dokunuşla Kategorilerin bölümüne taşındıklarını ve önerilerden kaybolduklarını doğrulayın.
4. Yeni kategori ekranında renk seçiminin bulunmadığını, emoji klavyesinin açıldığını ve kullanımda olan bir emojinin ikinci kez kaydedilemediğini doğrulayın.
5. Kalem düğmesine dokunun; sıralama sırasında onay işaretine dönüştüğünü ve tamamlanınca yeniden kalem olduğunu doğrulayın.
6. Uygulama dilini Türkçe ve English arasında değiştirin; öneriden eklenen kategori adlarının çevrildiğini doğrulayın.
7. Kategori ekranını açık/koyu modda, büyük metinde, VoiceOver ile ve iPhone/iPad üzerinde kontrol edin; satıra dokunmanın düzenleyiciyi açtığını doğrulayın.
5. Kayıtlar ekranında net toplamın birincil odak olduğunu; seçili ay rozetinin, monokrom eğilim çizgisinin ve ikincil harcama/gelir değerlerinin açık ve koyu modda okunabildiğini doğrulayın.
6. Yeni kayıt düğmesinin sağ altta, sekme çubuğunun üstünde ve kolay erişilebilir kaldığını doğrulayın.
7. İşlem satırında notun üstte; kategori, kısa gün/ay tarihi ve taksit sırasının altta; tutarın sağda okunaklı göründüğünü kontrol edin. Tarihte yıl görünmemeli.
8. Kayıt, kategori ve bütçe satırlarını sola kaydırın; yalnız kırmızı Sil eyleminin hem açık hem koyu modda belirgin ve okunaklı olduğunu doğrulayın.
9. Ay özetini sağa/sola kaydırın; özet verilerinin ve çizginin seçilen aya güncellendiğini, animasyonlu geçişi ve dört sekmenin görünür kaldığını kontrol edin.
10. Ayarlar ekranını koyu modda inceleyin; başlıkların, seçimlerin, anahtarların ve para birimi kodunun okunaklı olduğunu doğrulayın.
11. İşlem editöründe Tuş titreşimi açıkken rakam ve silme tuşlarına basın; her dokunuşta hafif dokunsal geri bildirim gelmeli.
12. Türkçe ve English arayüzü, açık/koyu görünümü ve en büyük Dynamic Type boyutunu deneyin; en büyük boyutta özet ve işlem satırı okunabilir dikey düzene geçmeli.
13. Uygulama Kilidi'ni etkinleştirin; Face ID sırasında kilit ekranının arkada kaldığını, başarı işareti görünürken uygulamanın çizilmeye başladığını ve tek doğrulama sonrası yeniden kilitlenmediğini kontrol edin.
14. 3.000 TL, 3 taksit ve 18 Ağustos seçerek 18 Ağustos, 18 Eylül ve 18 Ekim'de tam üç bağlı işlem oluştuğunu doğrulayın.
15. Plan alanından tekrar oluşturun; aynı vade için mükerrer işlem oluşmadığını kontrol edin.
16. Özel emojili kategoriyle CSV ve tam JSON yedeğini dışa ve içe aktarın; emojinin korunduğunu doğrulayın.
17. TRY dışında bir ISO para birimi seçin ve seçimin uygulama yeniden açıldığında korunduğunu doğrulayın.
18. VoiceOver ile sekmeleri, ay düğmelerini, net toplamı, işlem satırlarını, kilit ekranını ve numaratörü gezin.

## Beta Description — English

Tutar is a completely free, ad-free, open-source iOS app for tracking income, expenses, budgets, repeats, and installments. Four concise first-launch pages explain records, repeat/installment options in Schedule, why budgets do not create transactions, and Tutar’s privacy model. Installments live in the transaction Schedule field rather than in a separate tab. Dime/Tutar CSV import, CSV export, complete JSON backup, local storage, and optional private iCloud sync are included.

Tutar is a GPLv3 modified work based on Dime, originally created by Rafael Soh and contributors. This build was modified on 5 August 2026. Complete source: https://github.com/furkancak1r/tutar-ios

## What to Test — English

Build 24 makes the onboarding navigation more minimal. The first-page Next button is now truly centered; the large filled Back control is replaced by a plain chevron that keeps a 44-point accessible touch target. Next and Start actions now use compact content-width capsules. The complete suite of 36 unit and 21 UI tests passed. Tutar is a GPLv3 derivative of Dime by Rafael Soh and contributors. Modified 5 August 2026. Source: https://github.com/furkancak1r/tutar-ios

1. After updating, confirm onboarding appears once and all four pages work with horizontal swipes and the Back/Next buttons.
2. Quit midway and relaunch; onboarding should return. After Skip or Start Using Tutar, it should stay completed.
3. Reopen it from Settings → Information → How Tutar Works and confirm closing it returns to Settings.
4. With App Lock enabled, confirm only the lock screen appears first and onboarding opens after one successful authentication.
5. Check Turkish/English, light/dark appearance, large text, VoiceOver, monochrome controls, and scrollable content without clipping.

1. Select an expense, income, or category filter; confirm the top-right filter icon becomes a monochrome clear icon and removes the filter with one tap.
2. In a new transaction, swipe left from the empty right edge and right from the empty left edge; confirm the type changes while gestures on the keypad and form do not.
3. In monthly Analysis, confirm bars and axis labels do not overlap; tap a real bar and verify the exact contributing Records rows receive a border for three seconds.
4. Tap an empty day in the chart and confirm the selected tab does not change.
5. Tap Upcoming, Today, Yesterday, and date headers; confirm every group expands and collapses independently.
6. Confirm upcoming rows, including their emoji, are quieter than historical rows while remaining readable.
7. In Budgets, tap the info button; confirm the explanation appears in a popover and dismisses when tapping outside.
8. Type 425 in transaction and budget amount fields; confirm 425.00 appears centered despite the delete button.

1. In Settings → Categories, confirm the Expense/Income control separates the lists correctly.
2. Hide and show the list with the eye button in Suggested; confirm the button remains accessible in both states.
3. Add Housing and Freelance from Suggested; confirm each moves into Your categories with one tap and disappears from Suggested.
4. In New Category, confirm there is no colour picker, the emoji keyboard opens, and an emoji already in use cannot be saved again.
5. Tap the pencil button; confirm it changes to a checkmark while reordering and returns to a pencil when finished.
6. Switch the app between Turkish and English; confirm suggested categories that were added change to the correct localized name.
7. Check Categories in light/dark appearance, large text, VoiceOver, and iPhone/iPad layouts; confirm tapping a row opens its editor.
5. Confirm net total is the primary focus and that the selected-month pill, monochrome trend, and secondary spent/income values remain readable in light and dark appearance.
6. Confirm the add button stays at the bottom-right above the tab bar and remains easy to reach.
7. In each record, verify the note is on top; category, abbreviated day/month date, and installment position are below; and the amount is readable on the right. The date must not include a year.
8. Swipe record, category, and budget rows left; confirm the single red Delete action is distinct and readable in both light and dark appearance.
9. Swipe the month summary left and right; confirm the values and trend update for the selected month, the transition animates, and all four tabs remain visible.
10. Inspect Settings in dark mode and confirm headings, picker values, switches, and the currency code are readable.
11. With Key haptics enabled, press number and delete keys in the editor; each tap should produce light haptic feedback.
12. Test Turkish and English, light and dark appearance, and the largest Dynamic Type size. At the largest size, summary values and records should adapt to a readable vertical layout.
13. Enable App Lock; confirm the lock screen stays behind Face ID, app content starts rendering during the success checkmark, and one successful authentication does not relock the app.
14. Enter 3,000, choose 3 installments and 18 August, then verify exactly three linked entries on 18 August, 18 September, and 18 October.
15. Create a repeat from Schedule and confirm a due date is materialized only once.
16. Export and import CSV and complete JSON backup with a custom category emoji; confirm the emoji is preserved.
17. Choose a non-default ISO currency and confirm the choice persists after relaunch.
18. Navigate tabs, month controls, net total, transaction rows, the lock screen, and the keypad with VoiceOver.

Feedback email: furkancakr7@gmail.com

Source and GPLv3 license: https://github.com/furkancak1r/tutar-ios
