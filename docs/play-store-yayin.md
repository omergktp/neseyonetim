# Blokent — Google Play Yayın Dosyası

Hazırlayan: Claude (2026-07-28, marka güncellemesi 2026-07-29). Play Console'da ilgili
alanlara kopyalanacak metinler ve yayın adımları.

> **Marka notu:** Ürün adı **Glow Saha → Blokent** olarak değişti (sektör/isim
> araştırması: `docs/sektor-arastirmasi-2026-07.md`). Paket adı da yayın öncesi
> `com.glowsaha.app` → `com.blokent.app` yapıldı — Play'e yüklendikten sonra
> paket adı **asla** değiştirilemediği için bu değişikliğin son anıydı.

## Kimlik / İmza

| Alan | Değer |
|---|---|
| Paket adı (applicationId) | `com.blokent.app` |
| Upload keystore | `C:\Users\omerg\keystores\glowsaha-upload.jks` (dosya adı kalabilir; **anahtarın kendisi marka değişikliğinden etkilenmez**) |
| Alias | `upload` |
| Şifre | `C:\Users\omerg\keystores\glowsaha-upload-BILGILER.txt` dosyasında — **yedekleyin!** |
| key.properties | `mobile\android\key.properties` (git'e girmez) |
| Sürüm | 1.0.1+2 (pubspec.yaml) |

## Mağaza Metinleri (kopyala-yapıştır)

**Uygulama adı (30 karakter):**
> Blokent — Saha Görev Takibi

**Kısa açıklama (80 karakter):**
> Site ve tesis personeli için görev takibi, QR/konum doğrulama ve arıza bildirimi

**Uzun açıklama:**
> Blokent, site ve tesis yönetim firmalarının saha operasyonlarını uçtan uca yönetmesini sağlayan kurumsal görev takip uygulamasıdır.
>
> ÖZELLİKLER
> • Görev listesi ve görev detayı: personel gün içindeki işlerini tek ekranda görür
> • Fotoğraflı görev kanıtı: iş tamamlanırken kamera ile kanıt fotoğrafı eklenir
> • QR kod ve konum doğrulama: işin gerçekten sahada yapıldığı doğrulanır
> • Arıza bildirimi: sahada tespit edilen arızalar fotoğraflı olarak anında yönetime iletilir
> • Masraf kaydı: saha harcamaları uygulama üzerinden girilir
> • Çevrimdışı çalışma: internet olmayan bodrum/asansör gibi alanlarda kayıtlar kuyruğa alınır, bağlantı gelince otomatik gönderilir
> • Anlık bildirimler: yeni görev atandığında personele bildirim gider
>
> Blokent kapalı bir kurumsal sistemdir: hesaplar yönetici firmanız tarafından oluşturulur, uygulama içinden üyelik alınmaz. Yönetici web paneli ile birlikte çalışır.

**Kategori:** İş (Business)
**E-posta:** omergktp@gmail.com
**Gizlilik politikası URL'si:** `https://neseyonetim.vercel.app/landing/gizlilik`
(kendi alan adına geçince `https://blokent.com/landing/gizlilik` olarak güncelle)

## Data Safety (Veri Güvenliği) formu cevapları

- Veri toplanıyor mu? **Evet**
- Konum → Yaklaşık + Kesin konum: Toplanıyor, paylaşılmıyor, uygulama işlevi için, kullanıcı silme talep edebilir
- Kişisel bilgiler → Ad, Telefon: Toplanıyor (işveren kaydeder), paylaşılmıyor
- Fotoğraflar: Toplanıyor (görev kanıtı), paylaşılmıyor
- Uygulama etkinliği / Çökme günlükleri: Crashlytics — toplanıyor, paylaşılmıyor
- Veriler aktarımda şifreleniyor mu? **Evet (TLS)**
- Kullanıcı veri silme talep edebilir mi? **Evet** (gizlilik sayfasındaki e-posta)

## App Access (kapalı sistem olduğu için zorunlu)

Google incelemesi giriş gerektiren uygulamalarda test hesabı ister:
- "All or some functionality is restricted" seçilecek
- Demo firma kodu + telefon + şifre girilecek (demo tenant: `TEST1234`)

## Yayın Adımları

1. **Firebase (ZORUNLU — yeni paket adı):** Console → `glow-saha` projesi (proje
   kimliği Firebase'de değiştirilemez, sorun değil) → Project settings → Add app
   (Android) → paket: **`com.blokent.app`** → yeni `google-services.json`'ı indir →
   `mobile\android\app\google-services.json` üzerine yaz.
   ⚠️ Repodaki dosya şu an **geçici yamalıdır**: `com.blokent.app` için eski uygulamanın
   `mobilesdk_app_id`'si kopyalanmıştır. Build geçer ama **FCM bildirimleri gerçek dosya
   indirilene kadar güvenilmez**. Yayından önce mutlaka yenileyin.
2. **Play Console:** Uygulama oluştur (Türkçe, Uygulama, Ücretsiz), paket adı `com.blokent.app`.
3. Store listing metinlerini ve görselleri gir (512×512 ikon, 1024×500 feature graphic,
   en az 2 telefon ekran görüntüsü).
   ⚠️ `play-store-assets/` içindeki ikon ve tanıtım görselleri hâlâ eski markaya ait —
   Blokent logosu ile yeniden üretilmeli.
4. Data safety + App access + İçerik derecelendirmesi (herkes) formlarını doldur.
5. **Kapalı test:** AAB'yi Closed testing → yeni sürüme yükle.
   - ⚠️ **Bireysel (kişisel) geliştirici hesabıysa:** Üretime geçmeden önce en az
     **12 testçiyle 14 gün kesintisiz kapalı test** zorunlu. Kurumsal hesapta bu şart yok.
6. Test bitince Production'a terfi ettir.

## Eksikler / Yapılacaklar

- [ ] **Firebase'de `com.blokent.app` uygulaması oluştur ve `google-services.json`'ı yenile** (geçici yama var)
- [ ] Uygulama ikonu Blokent logosuyla yeniden üretilecek (`flutter_launcher_icons`);
      `mobile/assets/icon/` altındaki görseller ve `play-store-assets/` eski markaya ait
- [ ] Ekran görüntüleri Blokent arayüzüyle yeniden alınacak
- [ ] Landing'deki `wa.me/905XXXXXXXXX` placeholder'ları doldurulacak
- [ ] Alan adı: `blokent.com` kaydedilecek, Vercel'e bağlanacak
- [ ] Marka tescili: TÜRKPATENT 9/35/36/37/42. sınıflar
