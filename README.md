# Tutar

Tutar, günlük gelir-giderleri ve kredi kartı taksitlerini takip etmek için geliştirilmiş, tamamen ücretsiz ve açık kaynak bir iPhone/iPad uygulamasıdır. Reklam, analitik, izleyici, hesap, satın alma, abonelik, bağış veya paywall içermez.

> English documentation follows the Turkish section.

## Özellikler

- Yazarken kuruşları otomatik kaydıran hızlı numaratör; istenirse ondalık giriş
- Not ve kategori önerileriyle hızlı gelir/gider kaydı
- Haftalık, aylık ve yıllık analiz; arama ve kategori kırılımları
- Ay özetini sağa/sola kaydırarak veya oklarla ay değiştirme
- Günlük, haftalık, aylık ve yıllık genel/kategori bütçeleri
- Düzenlenebilir, sıralanabilir gelir ve gider kategorileri
- Tek sefer, tekrar veya taksit seçeneklerini aynı **Plan** menüsünden ayarlama
- Toplam tutarı kuruşu kuruşuna koruyan bağlı taksit planları
- Her taksitte sıra göstergesi (`1/3`, `2/3`, `3/3`)
- Tek taksiti veya seçili taksit ve sonrasını düzenleme/silme
- Gelecek taksitleri geçmiş işlemlerden ayrı gösterme
- Dime/Tutar CSV içe aktarma, işlem CSV dışa aktarma ve tam JSON yedekleme/geri yükleme
- Türkçe ve İngilizce; Sistem / Türkçe / English dil seçimi
- Tüm ISO para birimleri; Türkçede varsayılan TRY ve seçimi koruyan yerel biçimlendirme
- Düz siyah-beyaz vurgu sistemi; gradient içermeyen açık/koyu görünüm
- Koyu/açık mod, Dynamic Type, VoiceOver etiketleri ve iPhone/iPad düzenleri
- Yerel Core Data saklama ve isteğe bağlı özel iCloud/CloudKit eşzamanlama
- İsteğe bağlı aygıt kilidi, yerelleştirilmiş widget ve günlük yerel hatırlatıcı

Taksitler ayrı bir sekme değildir. Yeni veya mevcut bir işlemin **Plan** alanında, “Tek sefer” ve “Tekrar” seçeneklerinin yanında ayarlanır; oluşan taksitler ait oldukları aylardaki normal işlem listesinde görünür.

## Kurulum ve geliştirme

Gereksinimler: macOS, Xcode 26 veya daha yeni sürüm ve [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone https://github.com/furkancak1r/tutar-ios.git
cd tutar-ios
xcodegen generate
open Tutar.xcodeproj
```

Simülatör derlemesi ve testler:

```sh
xcodebuild build -project Tutar.xcodeproj -scheme Tutar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO

xcodebuild test -project Tutar.xcodeproj -scheme Tutar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Kendi cihazınızda çalıştırmak için bundle ID, App Group, iCloud container ve geliştirme takımını kendi Apple Developer hesabınızla değiştirin.

CloudKit development şemasını oluşturmak için Debug çalıştırmasına `-initialize-cloudkit-schema` argümanını bir kez ekleyin; TestFlight veya App Store dağıtımından önce CloudKit Console’daki şema değişikliklerini production’a dağıtın.

## Kaynak, atıf ve lisans

Tutar, [Dime](https://github.com/rafsoh/dimeApp) temel alınarak oluşturulmuş değiştirilmiş bir çalışmadır. Dime’ın özgün yaratıcısı Rafael Soh’tur; önceki katkılar Git geçmişinde kendi yazarlarıyla korunmaktadır. Bu türev ilk kez **4 Ağustos 2026** tarihinde Tutar olarak değiştirilmiştir ve dayandığı upstream revizyonu `0463cb8caba237de781ae02e70a2ec82ae900c67`’dir.

Kaynak geçmişi yeniden yazılmamıştır. `upstream` uzaktaki özgün projeyi, `origin` ise bu açık kaynak türevi gösterir. Ayrıntılı bildirimler için [NOTICE.md](NOTICE.md) dosyasına bakın.

Tutar ve tüm türev kod GNU General Public License v3.0 altında yayımlanır. Tam metin [LICENSE](LICENSE) dosyasındadır. Önceki katkıların telif hakları kendi sahiplerinde, 2026 Tutar değişikliklerinin telif hakkı Furkan Çakır’dadır. Bu yazılım hiçbir garanti olmadan sunulur.

## Gizlilik ve destek

- [Gizlilik politikası](https://furkancak1r.github.io/tutar-ios/privacy.html)
- [Destek](https://furkancak1r.github.io/tutar-ios/support.html)
- E-posta: [furkancakr7@gmail.com](mailto:furkancakr7@gmail.com)

---

## English

Tutar is a completely free and open-source iPhone/iPad app for tracking everyday income, expenses, and card installments. It contains no advertising, analytics, tracking, account system, purchases, subscriptions, donations, or paywalls.

The automatic-cents keypad makes amount entry immediate, with an optional decimal mode. Past-entry suggestions, editable categories, swipeable months, search, weekly/monthly/yearly analysis, all ISO currencies, and general or category budgets cover everyday tracking. Dime/Tutar CSV import, transaction CSV export, and a complete JSON backup provide local data portability. The interface uses a flat monochrome accent system with no gradients.

Installments are configured inside the transaction **Schedule** menu beside One time and Repeat, not in a separate tab. The flow creates exactly the selected number of linked transactions, assigns any rounding remainder to the final installment, shows positions such as `1/3`, and supports editing or deleting one installment or the selected installment and all following ones. Future installments are shown separately and count toward spending only in their own calendar month.

Tutar supports complete Turkish and English localization, locale-aware dates and money, Dynamic Type, VoiceOver, dark mode, iPhone/iPad layouts, local Core Data storage, optional private iCloud/CloudKit sync, optional device authentication, a localized widget, and local reminders.

Tutar is a modified work based on [Dime](https://github.com/rafsoh/dimeApp), originally created by Rafael Soh with contributions preserved in Git history. It was first modified as Tutar on **4 August 2026**, based on upstream revision `0463cb8caba237de781ae02e70a2ec82ae900c67`. The complete source is available in this repository and remains licensed under GNU GPLv3; see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

Support and privacy pages are linked above. Build instructions are identical to the Turkish section. Initialize the development CloudKit schema once with the `-initialize-cloudkit-schema` Debug launch argument, then deploy the schema changes to production in CloudKit Console before TestFlight or App Store distribution.
