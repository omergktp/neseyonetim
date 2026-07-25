<?php
// backend/cron/periodic_tasks.php
// Periyodik (tekrarlayan) görev üreticisi.
// Sunucuda her gece 00:01'de çalışacak şekilde cron'a eklenmelidir: 1 0 * * *
// Çalıştırma: php backend/cron/periodic_tasks.php
//
// Mantık: periyodik_sablonlar tablosundaki AKTİF şablonları tarar; tekrar kuralı
// bugüne denk gelen ve bugün henüz üretilmemiş her şablon için bir iş emri oluşturur,
// checklist maddelerini kopyalar ve atanan personele FCM bildirimi gönderir.

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../core/Database.php';
require_once __DIR__ . '/../core/PeriodicGenerator.php';

$db = (new Database())->getConnection();

$bugun       = date('Y-m-d');
$haftaGunu   = (int)date('N'); // 1 (Pazartesi) - 7 (Pazar)
$ayinGunu    = (int)date('j'); // 1 - 31
$ayinSonGunu = (int)date('t'); // İçinde bulunulan aydaki gün sayısı (28-31)

echo "Cron Job Başladı: " . date('Y-m-d H:i:s') . "\n";

// Bir şablonun tekrar kuralı bugüne denk geliyor mu?
function buguneDenkGeliyorMu(array $s, $haftaGunu, $ayinGunu, $ayinSonGunu) {
    switch ($s['tekrar_tipi']) {
        case 'gunluk':
            return true;
        case 'haftalik':
            return (int)$s['tekrar_gunu'] === $haftaGunu;
        case 'aylik':
            $hedef = (int)$s['tekrar_gunu'];
            // Ayın 31'i seçildiyse ama ay daha kısaysa (örn. Şubat), son güne kaydır.
            if ($hedef > $ayinSonGunu) {
                return $ayinGunu === $ayinSonGunu;
            }
            return $hedef === $ayinGunu;
        default:
            return false;
    }
}

try {
    $sablonlar = $db->query("SELECT * FROM periyodik_sablonlar WHERE aktif = 1")
                    ->fetchAll(PDO::FETCH_ASSOC);

    echo count($sablonlar) . " aktif şablon kontrol ediliyor...\n";

    $uretilen = 0;
    $atlanan  = 0;

    foreach ($sablonlar as $s) {
        // Bugün zaten üretilmişse atla (cron mükerrer çalışsa bile güvenli).
        if (!empty($s['son_uretim_tarihi']) && $s['son_uretim_tarihi'] === $bugun) {
            $atlanan++;
            continue;
        }

        if (!buguneDenkGeliyorMu($s, $haftaGunu, $ayinGunu, $ayinSonGunu)) {
            $atlanan++;
            continue;
        }

        try {
            $yeni_id = PeriodicGenerator::uret($db, $s, $bugun);
            if ($yeni_id === null) {
                echo "  ! Şablon #{$s['id']} ('{$s['baslik']}') atlandı: site/personel pasif veya silinmiş.\n";
                $atlanan++;
                continue;
            }
            if ($yeni_id === 0) {
                // Atomik kapma: bu şablon bugün zaten üretilmiş (paralel çalışma vb.)
                $atlanan++;
                continue;
            }
            $uretilen++;
            echo "  + İş emri #{$yeni_id} üretildi: '{$s['baslik']}' (şablon #{$s['id']})\n";
        } catch (Throwable $e) {
            echo "  ! Şablon #{$s['id']} üretilirken hata: " . $e->getMessage() . "\n";
        }
    }

    echo "Özet: {$uretilen} iş emri üretildi, {$atlanan} şablon atlandı.\n";
    echo "Cron Job Başarıyla Tamamlandı.\n";

} catch (Exception $e) {
    echo "Hata: " . $e->getMessage() . "\n";
}
