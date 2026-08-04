# Tutar 1.0 (1) — TestFlight metadata

## Beta Description — Turkish

Tutar; gelir, gider ve taksitleri takip etmek için tamamen ücretsiz, reklamsız ve açık kaynak bir iOS uygulamasıdır. Ayırt edici Taksitler ekranı, toplamı kuruşu kuruşuna korur; bağlı işlemleri 1/3, 2/3, 3/3 biçiminde gösterir ve tek taksit ya da bu ve sonraki taksitleri düzenleme/silme seçenekleri sunar. Yerel saklama ve isteğe bağlı özel iCloud eşzamanlaması kullanır.

Tutar, Rafael Soh ve katkıda bulunanların oluşturduğu Dime temel alınarak değiştirilmiş GPLv3 çalışmasıdır. Değişiklik tarihi: 4 Ağustos 2026. Tam kaynak: https://github.com/furkancak1r/tutar-ios

## What to Test — Turkish

1. 3.000 TL, 3 taksit ve ilk tarih 18 Ağustos seçerek tam üç işlemin 18 Ağustos, 18 Eylül ve 18 Ekim’e oluşturulduğunu doğrulayın.
2. Kuruşla tam bölünmeyen bir tutarda farkın yalnız son taksite verildiğini kontrol edin.
3. Tek taksiti ve “bu ve sonrası” kapsamını ayrı ayrı düzenleyin/silin; mükerrer kayıt oluşmamalı.
4. Gelecek taksitlerin ayrı bölümde kaldığını ve yalnız ait oldukları ayın analizine girdiğini kontrol edin.
5. Ayarlar’dan Sistem, Türkçe ve English seçeneklerini; açık/koyu modu; iCloud kapatma/açma sonrası yeniden başlatmayı deneyin.
6. iPhone ve iPad’de büyük metin/VoiceOver ile taşma veya etiketsiz denetim bildirin.

## Beta Description — English

Tutar is a completely free, ad-free, open-source iOS app for tracking income, expenses, and installments. Its distinctive Installments screen preserves the exact total, labels linked transactions as 1/3, 2/3, 3/3, and supports editing or deleting one installment or the selected installment and all following ones. Data is stored locally with optional private iCloud sync.

Tutar is a GPLv3 modified work based on Dime, originally created by Rafael Soh and contributors. Modification date: 4 August 2026. Complete source: https://github.com/furkancak1r/tutar-ios

## What to Test — English

1. Enter a total of 3,000, choose 3 installments and 18 August, then verify exactly three linked entries on 18 August, 18 September, and 18 October.
2. Use a total that does not divide evenly into cents and confirm only the last installment receives the remainder.
3. Edit/delete one installment and “this and following”; no duplicate entries should appear.
4. Confirm future installments are separate and affect only their own calendar month.
5. Test System, Turkish, and English language choices, light/dark appearance, and an iCloud sync change followed by relaunch.
6. Report clipping or unlabeled controls with large text or VoiceOver on iPhone and iPad.

Feedback email: furkancakr7@gmail.com

Source and GPLv3 license: https://github.com/furkancak1r/tutar-ios
