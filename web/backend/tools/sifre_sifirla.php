<?php
// backend/tools/sifre_sifirla.php
// Yönetici (veya herhangi bir personelin) şifresini komut satırından sıfırlar.
// Yönetici kendi şifresini unutursa tek kurtarma yolu budur (panelde kendi
// şifresini ancak başka bir yönetici sıfırlayabilir).
//
// Kullanım:
//   php sifre_sifirla.php FIRMAKODU 05XXXXXXXXX yeniSifre

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit('Bu araç yalnızca komut satırından çalıştırılabilir.');
}

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../core/Database.php';

if ($argc < 4) {
    echo "Kullanım: php sifre_sifirla.php FIRMAKODU telefon yeniSifre\n";
    exit(1);
}

[$_, $firmaKodu, $telefon, $yeniSifre] = $argv;
$firmaKodu = strtoupper(trim($firmaKodu));
$telefon   = preg_replace('/\D/', '', $telefon);

if (strlen($yeniSifre) < 6) {
    exit("HATA: Şifre en az 6 karakter olmalı.\n");
}

$db = (new Database())->getConnection();

$q = $db->prepare("SELECT p.id, p.ad_soyad, p.rol
                   FROM personeller p
                   JOIN firmalar f ON p.firma_id = f.id
                   WHERE f.firma_kodu = :k AND p.telefon = :tel LIMIT 1");
$q->execute([':k' => $firmaKodu, ':tel' => $telefon]);
$personel = $q->fetch(PDO::FETCH_ASSOC);

if (!$personel) {
    exit("HATA: '$firmaKodu' firmasında '$telefon' numaralı personel bulunamadı.\n");
}

$u = $db->prepare("UPDATE personeller SET sifre = :s WHERE id = :id");
$u->execute([':s' => password_hash($yeniSifre, PASSWORD_DEFAULT), ':id' => $personel['id']]);

echo "Şifre sıfırlandı: {$personel['ad_soyad']} ({$personel['rol']}) — yeni şifreyle giriş yapabilir.\n";
