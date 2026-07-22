# GLOW SAHA - Test ve Kurulum Rehberi

Projemiz üç ana bileşenden oluşmaktadır: **PHP/MySQL Backend**, **Web Paneli (Frontend)** ve **Flutter Mobil Uygulaması**. Projeyi bilgisayarınızda test etmek için aşağıdaki adımları sırasıyla uygulayabilirsiniz.

---

## ADIM 1: Veritabanını Kurma (MySQL)

Backend PHP'nin çalışması için öncelikle veritabanının ayakta olması gerekir. Bunun için XAMPP, WAMP veya Laragon gibi bir yerel sunucu yazılımı kullanabilirsiniz.

1. **XAMPP/Laragon** programını açın ve **Apache** ile **MySQL** servislerini başlatın.
2. Tarayıcınızda `http://localhost/phpmyadmin` adresine gidin.
3. Yeni bir veritabanı oluşturun ve adını `glow_saha` yapın. (Karakter setini `utf8mb4_unicode_ci` seçin).
4. Oluşturduğunuz veritabanına tıklayın ve üst menüden **İçe Aktar (Import)** sekmesine geçin.
5. Dosya seç bölümünden `c:\Users\omerg\Desktop\neseyonetim\db\schema.sql` dosyasını seçip içeri aktarın. Tablolarınız otomatik olarak kurulacaktır.

**Test Verisi Ekleme:**  
Sisteme giriş yapabilmek için `phpmyadmin` üzerinden `firmalar` tablosuna bir örnek firma ve `personeller` tablosuna bir personel kaydı eklemelisiniz.

---

## ADIM 2: Backend (PHP API) Testi

PHP dosyalarının yerel sunucunuzda çalışabilmesi için projeyi doğru klasöre taşımanız gerekir.

1. `neseyonetim` klasörünü (şu an masaüstünüzde bulunan) kopyalayın.
2. XAMPP kullanıyorsanız `C:\xampp\htdocs\` klasörünün içine, Laragon kullanıyorsanız `C:\laragon\www\` klasörünün içine yapıştırın.
3. `backend/config.php` dosyasını bir kod editöründe açın. Veritabanı şifreniz varsa `DB_PASS` kısmına yazın. XAMPP için varsayılan şifre boştur (`''`).
4. Tarayıcınızı açıp `http://localhost/neseyonetim/backend/api/login.php` adresine gitmeyi deneyin. "Eksik bilgi gönderildi" gibi bir JSON hatası görüyorsanız, API'niz sorunsuz çalışıyor demektir.

---

## ADIM 3: Web Panelini (Frontend) Test Etme

Web paneli saf HTML ve Tailwind CSS kullandığı için doğrudan tarayıcıda çalışabilir.

1. `C:\xampp\htdocs\neseyonetim\frontend\` klasörüne gidin.
2. `index.html` dosyasına çift tıklayarak tarayıcıda açın. Muazzam giriş (Login) ekranını göreceksiniz.
3. Formu doldurup "Giriş Yap" butonuna bastığınızda sizi otomatik olarak Yönetici Paneline (`dashboard.html`) yönlendirecektir.
4. Raporlama modülünü test etmek için `rapor_pdf.html` dosyasına çift tıklayın ve açılan ekranda "Yazdır" butonuna basarak PDF önizlemesini görün.

---

## ADIM 4: Flutter Mobil Uygulamasını Test Etme

Mobil uygulamayı test edebilmek için Android Studio, Visual Studio Code ve cihaz emülatörü gereklidir.

1. Komut satırını (Terminal) açın ve mobil uygulamanın olduğu dizine gidin:
   ```bash
   cd C:\Users\omerg\Desktop\neseyonetim\mobile
   ```
2. Eksik paketler varsa yüklemek için şu komutu çalıştırın:
   ```bash
   flutter pub get
   ```
3. Bir Android Emülatörü çalıştırın (veya telefonunuzu USB ile bağlayıp USB Hata Ayıklama modunu açın).
4. Uygulamayı derlemek ve başlatmak için:
   ```bash
   flutter run
   ```
   *Not: API bağlantı URL'si `api_service.dart` içerisinde `http://10.0.2.2/neseyonetim/...` olarak ayarlanmıştır. (10.0.2.2 adresi Android Emülatör'ün localhost'a erişim adresidir).*

**Kamera ve GPS Testi:**  
Emülatörlerde kamera ve GPS özellikleri simüle edilebilir. Kamerayı açtığınızda emülatörün sanal odasını göreceksiniz. GPS (Konum) menüsünden ise sahte bir konum girerek "50 metre" kuralını test edebilirsiniz.
