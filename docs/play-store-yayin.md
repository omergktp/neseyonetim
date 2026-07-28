# Glow Saha — Google Play Yayın Dosyası

Hazırlayan: Claude (2026-07-28). Play Console'da ilgili alanlara kopyalanacak metinler ve yayın adımları.

## Kimlik / İmza

| Alan | Değer |
|---|---|
| Paket adı (applicationId) | `com.glowsaha.app` |
| Upload keystore | `C:\Users\omerg\keystores\glowsaha-upload.jks` |
| Alias | `upload` |
| Şifre | `C:\Users\omerg\keystores\glowsaha-upload-BILGILER.txt` dosyasında — **yedekleyin!** |
| key.properties | `mobile\android\key.properties` (git'e girmez) |
| Sürüm | 1.0.0+1 (pubspec.yaml) |

## Mağaza Metinleri (kopyala-yapıştır)

**Uygulama adı (30 karakter):**
> Glow Saha — Saha Görev Takibi

**Kısa açıklama (80 karakter):**
> Site ve tesis personeli için görev takibi, QR/konum doğrulama ve arıza bildirimi

**Uzun açıklama:**
> Glow Saha, site ve tesis yönetim firmalarının saha operasyonlarını uçtan uca yönetmesini sağlayan kurumsal görev takip uygulamasıdır.
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
> Glow Saha kapalı bir kurumsal sistemdir: hesaplar yönetici firmanız tarafından oluşturulur, uygulama içinden üyelik alınmaz. Yönetici web paneli ile birlikte çalışır.

**Kategori:** İş (Business)
**E-posta:** omergktp@gmail.com
**Gizlilik politikası URL'si:** Vercel yayınından sonra `https://<domain>/landing/gizlilik` (dosya: `web/landing/gizlilik.html`)

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
- Demo firma kodu + telefon + şifre girilecek (demo tenant oluşturulmalı — denetim raporundaki karar da buydu)

## Yayın Adımları

1. **Firebase:** Console → glow-saha projesi → Project settings → Add app (Android) → paket: `com.glowsaha.app` → yeni `google-services.json`'ı indir → `mobile\android\app\google-services.json` üzerine yaz → AAB'yi yeniden derle.
2. **Play Console:** Uygulama oluştur (Türkçe, Uygulama, Ücretsiz).
3. Store listing metinlerini ve görselleri gir (512×512 ikon, 1024×500 feature graphic, en az 2 telefon ekran görüntüsü).
4. Data safety + App access + İçerik derecelendirmesi (herkes) formlarını doldur.
5. **Kapalı test:** AAB'yi Closed testing → yeni sürüme yükle.
   - ⚠️ **Bireysel (kişisel) geliştirici hesabıysa:** Üretime geçmeden önce en az **12 testçiyle 14 gün kesintisiz kapalı test** zorunlu. Kurumsal hesapta bu şart yok.
6. Test bitince Production'a terfi ettir.

## Eksikler / Yapılacaklar

- [ ] Uygulama ikonu hâlâ varsayılan Flutter logosu — gerçek logo gerekiyor (`flutter_launcher_icons` ile üretilebilir)
- [ ] `google-services.json` yeni paket adıyla yenilenecek (şu anki dosya geçici, elle yamalı)
- [ ] Gizlilik sayfası Vercel'e deploy edilecek, URL Play Console'a girilecek
- [ ] Demo tenant (App access için test hesabı)
- [ ] Ekran görüntüleri (emülatörden alınabilir)
- [ ] Denetim raporundaki kritik güvenlik maddeleri (seed_data.sql sırları vb.) yayın öncesi ele alınmalı
