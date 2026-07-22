# PROJE DOSYASI: GLOW SAHA (SaaS Tesis ve Saha Yönetim Sistemi)

## 1. PROJE ÖZETİ VE MİMARİ
Bu proje, tesis ve apartman yönetim şirketlerinin sahadaki temizlik ve teknik personellerini takip etmesini, iş atamasını ve raporlamasını sağlayan Çoklu Müşteri (Multi-Tenant) yapısına sahip bir SaaS yazılımıdır. 
Proje tek bir merkezi mobil uygulama üzerinden çalışacak, müşteriler (firmalar) kendi firma kodlarıyla sisteme girdiğinde dinamik arayüz (kendi logo ve renkleri) ile karşılaşacaktır.

## 2. TEKNOLOJİ YIĞINI (TECH STACK)
*   **Arka Uç (Backend):** PHP (8.0+), MySQL. Veritabanı bağlantıları KESİNLİKLE PDO ve Prepared Statements kullanılarak yazılacaktır.
*   **Ön Yüz (Yönetici Paneli):** HTML, CSS, JavaScript (Tercihe göre Bootstrap/Tailwind).
*   **Mobil Uygulama:** Flutter (Cross-platform, tek kod tabanı).
*   **Bildirim Sistemi:** Firebase Cloud Messaging (FCM).
*   **Mobil Yerel Veritabanı (Offline Mod için):** SQLite (sqflite paketi).

## 3. KESİN KURALLAR (AI İÇİN TALİMATLAR)
*   **KURAL 1 (Multi-Tenant):** Veritabanındaki tüm ana tablolarda `firma_id` sütunu bulunmak zorundadır. PHP API yazılırken istisnasız tüm SELECT, UPDATE, DELETE sorgularına `WHERE firma_id = ?` şartı eklenecektir. Çapraz veri sızıntısı kabul edilemez.
*   **KURAL 2 (Galeri İptali):** Mobil uygulamada (Flutter) fotoğraf yükleme işlemlerinde cihaz galerisine erişim KESİNLİKLE kapalı olacaktır. Sadece anlık kamera (`camera` paketi) tetiklenecektir.
*   **KURAL 3 (Çevrimdışı Çalışma):** Mobil uygulama internet bağlantısını kontrol edecektir. İnternet yoksa atılan istekler (fotoğraf, konum, tamamlanan görev) yerel SQLite veritabanında "Kuyruk (Queue)" tablosuna kaydedilecek, cihaz internete bağlandığı an arka planda API'ye POST edilecektir.
*   **KURAL 4 (Doğrulama):** Görev kapanışlarında sahte GPS kullanımını engellemek için konum verisi donanımsal olarak alınacak, çekilen fotoğrafların üzerine tarih, saat ve koordinat bilgisi filigran (watermark) olarak eklenecektir.

## 4. TEMEL MODÜLLER VE KULLANICI ROLLERİ
*   **Yönetici (Web Paneli):** Personel ekler, firma ayarlarını (logo/renk) yapar, iş atar, tekrarlayan görevleri ayarlar, arıza ve masrafları onaylar, apartman bazlı PDF rapor alır.
*   **Çalışan Rolü (Temizlik):** Görev listesini görür, QR veya Konum ile görevi başlatır, checklist doldurur, arıza/malzeme bildirir, fotoğraf çekip işi bitirir.
*   **Çalışan Rolü (Teknik/Tesisat):** Arıza kayıtlarını görür. İşi bitirirken masraf yapıldıysa Tutar, Malzeme Kalemi ve Fiş/Fatura fotoğrafı girmek zorundadır.

## 5. MOBİL UYGULAMA GİRİŞ AKIŞI
1.  **Splash Screen:** API'ye `app_version` kontrolü yapılır. Sürüm eskiyse "Güncelleme Zorunlu" uyarısı verilir.
2.  **Login Screen:** 3 input istenir: Firma Kodu, Telefon Numarası, Şifre. ("Kayıt Ol" butonu yoktur).
3.  **Dinamik UI Yükleme:** Login başarılıysa, API'den dönen firma logosu ve `hex_color` ile uygulamanın renk teması anında değiştirilir.

## 6. GELİŞTİRME FAZLARI VE YOL HARİTASI

### FAZ 1: Veritabanı ve Altyapı
*   `firmalar`, `personeller`, `siteler`, `is_emirleri`, `arizalar`, `malzeme_talepleri`, `is_emirleri_alt_gorevler` tablolarının `firma_id` FK (Foreign Key) mantığıyla MySQL'de oluşturulması.
*   Rol yapısının (`rol_id` veya `departman` ENUM) kurgulanması.

### FAZ 2: PHP REST API ve Web Paneli İskeleti
*   JWT veya Token tabanlı güvenli API altyapısının kurulması.
*   Giriş (Login), Görev Çekme, Fotoğraf/Veri Kaydetme API uç noktalarının yazılması.
*   FCM sunucu anahtarının (Server Key) PHP'ye entegre edilmesi.

### FAZ 3: Flutter Mobil Uygulama (Temel)
*   Projenin oluşturulması, Login ekranı ve Dinamik Tema yapısının kurulması.
*   FCM entegrasyonu (Cihaz Token alma ve bildirime tıklanınca sayfaya gitme).
*   Günün görevleri listesinin API'den çekilmesi.

### FAZ 4: Flutter Donanım ve Çevrimdışı (Offline) Mantığı
*   Kamera entegrasyonu ve filigran (watermark) ekleme fonksiyonu.
*   Geolocator ile konum alma ve Site konumuyla mesafe hesaplama (Maks 50 metre kuralı).
*   QR Kod okuyucu entegrasyonu ve "QR Hasarlı (Konumla Kapat)" senaryosunun yazılması.
*   İnternetsiz ortamlar için SQLite veri kuyruğu mimarisinin (Offline-first) kodlanması.

### FAZ 5: İleri Düzey Modüller (Web + Mobil)
*   Teknik personelin masraf/fiş giriş arayüzü.
*   Yönetici paneli PDF Raporlama modülü.
*   Tekrarlayan (Periyodik) görevler için PHP Cron Job yazılımı.