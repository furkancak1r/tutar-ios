# Tutar 1.0 (2) — TestFlight metadata

## Beta Description — Turkish

Tutar; gelir, gider, bütçe, tekrar ve taksitleri takip etmek için tamamen ücretsiz, reklamsız ve açık kaynak bir iOS uygulamasıdır. Otomatik kuruşlu numaratör hızlı veri girişi sağlar. Taksitler ayrı bir sekme yerine işlemdeki Plan alanından, Tek sefer ve Tekrar seçeneklerinin yanında ayarlanır. Bağlı işlemler toplamı tam korur, 1/3 gibi sıra bilgisini gösterir ve tek taksit ya da bu ve sonrasını düzenleme/silme seçenekleri sunar. Dime/Tutar CSV içe aktarma, CSV dışa aktarma, tam JSON yedekleme, yerel saklama ve isteğe bağlı özel iCloud eşzamanlaması bulunur.

Tutar, Rafael Soh ve katkıda bulunanların oluşturduğu Dime temel alınarak değiştirilmiş GPLv3 çalışmasıdır. Değişiklik tarihi: 4 Ağustos 2026. Tam kaynak: https://github.com/furkancak1r/tutar-ios

## What to Test — Turkish

1. 3.000 TL, 3 taksit ve ilk tarih 18 Ağustos seçerek tam üç işlemin 18 Ağustos, 18 Eylül ve 18 Ekim’e oluşturulduğunu doğrulayın.
2. Kuruşla tam bölünmeyen bir tutarda farkın yalnız son taksite verildiğini kontrol edin.
3. Tek taksiti ve “bu ve sonrası” kapsamını ayrı ayrı düzenleyin/silin; mükerrer kayıt oluşmamalı.
4. Gelecek taksitlerin ayrı bölümde kaldığını ve yalnız ait oldukları ayın analizine girdiğini kontrol edin.
5. Plan alanında günlük/haftalık/aylık tekrar oluşturun; aynı vade için mükerrer işlem oluşmadığını doğrulayın.
6. Bütçe ve kategori ekleme/düzenlemeyi; bir kategoriyi silince eski işlemlerin korunmasını deneyin.
7. Dime CSV içe aktarmayı iki kez yapıp ikinci geçişte mükerrerlerin atlandığını; CSV ve tam JSON yedeğin dışa aktarılabildiğini kontrol edin.
8. Ayarlar’dan Sistem, Türkçe ve English seçeneklerini; açık/koyu modu; iCloud kapatma/açma sonrası yeniden başlatmayı deneyin.
9. iPhone ve iPad’de büyük metin/VoiceOver ile taşma veya etiketsiz denetim bildirin.

## Beta Description — English

Tutar is a completely free, ad-free, open-source iOS app for tracking income, expenses, budgets, repeats, and installments. Its automatic-cents keypad makes entry fast. Installments live in the transaction Schedule field beside One time and Repeat, rather than in a separate tab. Linked entries preserve the exact total, show positions such as 1/3, and support editing or deleting one installment or the selected installment and all following ones. Dime/Tutar CSV import, CSV export, complete JSON backup, local storage, and optional private iCloud sync are included.

Tutar is a GPLv3 modified work based on Dime, originally created by Rafael Soh and contributors. Modification date: 4 August 2026. Complete source: https://github.com/furkancak1r/tutar-ios

## What to Test — English

1. Enter a total of 3,000, choose 3 installments and 18 August, then verify exactly three linked entries on 18 August, 18 September, and 18 October.
2. Use a total that does not divide evenly into cents and confirm only the last installment receives the remainder.
3. Edit/delete one installment and “this and following”; no duplicate entries should appear.
4. Confirm future installments are separate and affect only their own calendar month.
5. Create daily, weekly, and monthly repeats from Schedule and confirm a due date is materialized only once.
6. Add/edit budgets and categories; deleting a category must preserve its old transactions.
7. Import a Dime CSV twice and confirm duplicates are skipped, then test transaction CSV and complete JSON backup export.
8. Test System, Turkish, and English language choices, light/dark appearance, and an iCloud sync change followed by relaunch.
9. Report clipping or unlabeled controls with large text or VoiceOver on iPhone and iPad.

Feedback email: furkancakr7@gmail.com

Source and GPLv3 license: https://github.com/furkancak1r/tutar-ios
