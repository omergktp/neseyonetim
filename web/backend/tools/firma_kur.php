<?php
// backend/tools/firma_kur.php
// Yeni firma (tenant) + ilk yönetici hesabını TEK komutla kurar.
// Yalnızca komut satırından çalışır (web'den erişilemez) — onboarding aracı.
//
// Kullanım:
//   php firma_kur.php "Firma Adı" FIRMAKODU "#3B82F6" "Yönetici Ad Soyad" 05XXXXXXXXX sifre123
//
// Örnek:
//   php firma_kur.php "Nese Yonetim" NESE2026 "#0EA5E9" "Omer Yilmaz" 05551112233 gizli123

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit('Bu araç yalnızca komut satırından çalıştırılabilir.');
}

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../core/Database.php';

if ($argc < 7) {
    echo "Kullanım: php firma_kur.php \"Firma Adı\" FIRMAKODU \"#RRGGBB\" \"Yönetici Ad Soyad\" telefon sifre\n";
    exit(1);
}

[$_, $firmaAdi, $firmaKodu, $temaRengi, $yoneticiAd, $telefon, $sifre] = $argv;

$firmaKodu = strtoupper(trim($firmaKodu));
$temaRengi = trim($temaRengi);
$telefon   = preg_replace('/\D/', '', $telefon);

// Girdi doğrulama
if (!preg_match('/^[A-Z0-9]{4,20}$/', $firmaKodu)) {
    exit("HATA: Firma kodu 4-20 karakter, yalnızca BÜYÜK harf ve rakam olmalı. (örn: NESE2026)\n");
}
if (!preg_match('/^#[0-9A-Fa-f]{6}$/', $temaRengi)) {
    exit("HATA: Tema rengi #RRGGBB biçiminde olmalı. (örn: #3B82F6)\n");
}
if (strlen($telefon) < 10) {
    exit("HATA: Telefon numarası geçersiz görünüyor.\n");
}
if (strlen($sifre) < 6) {
    exit("HATA: Şifre en az 6 karakter olmalı.\n");
}

$db = (new Database())->getConnection();

// Firma kodu benzersiz mi?
$chk = $db->prepare("SELECT id FROM firmalar WHERE firma_kodu = :k");
$chk->execute([':k' => $firmaKodu]);
if ($chk->fetch()) {
    exit("HATA: '$firmaKodu' firma kodu zaten kayıtlı.\n");
}

$db->beginTransaction();
try {
    $f = $db->prepare("INSERT INTO firmalar (firma_kodu, ad, hex_color, aktif) VALUES (:k, :ad, :renk, 1)");
    $f->execute([':k' => $firmaKodu, ':ad' => trim($firmaAdi), ':renk' => $temaRengi]);
    $firmaId = (int)$db->lastInsertId();

    $p = $db->prepare("INSERT INTO personeller (firma_id, ad_soyad, telefon, sifre, rol, aktif)
                       VALUES (:fid, :ad, :tel, :sifre, 'yonetici', 1)");
    $p->execute([
        ':fid'   => $firmaId,
        ':ad'    => trim($yoneticiAd),
        ':tel'   => $telefon,
        ':sifre' => password_hash($sifre, PASSWORD_DEFAULT),
    ]);
    $yoneticiId = (int)$db->lastInsertId();

    $db->commit();

    echo "==============================================\n";
    echo " FİRMA KURULDU\n";
    echo "==============================================\n";
    echo " Firma ID    : $firmaId\n";
    echo " Firma Adı   : " . trim($firmaAdi) . "\n";
    echo " Firma Kodu  : $firmaKodu   <- personel girişte bunu kullanır\n";
    echo " Tema Rengi  : $temaRengi\n";
    echo " Yönetici    : " . trim($yoneticiAd) . " (id: $yoneticiId)\n";
    echo " Telefon     : $telefon\n";
    echo "----------------------------------------------\n";
    echo " Web paneli girişi: firma kodu + telefon + şifre\n";
    echo " Sonraki adımlar: panelden tesisleri ve personelleri ekleyin.\n";
} catch (Throwable $e) {
    $db->rollBack();
    exit("HATA: Kurulum geri alındı: " . $e->getMessage() . "\n");
}
