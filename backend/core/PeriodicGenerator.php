<?php
// backend/core/PeriodicGenerator.php
// Periyodik şablondan iş emri üreten ortak mantık.
// Hem gece çalışan cron (cron/periodic_tasks.php) hem de panelden "Üret" işlemi
// (api/admin/periyodik_gorevler.php) bu sınıfı kullanır.

require_once __DIR__ . '/FcmSender.php';

class PeriodicGenerator {

    /// Bir şablondan iş emri üretir: kaydı oluşturur, checklist'i kopyalar,
    /// personele FCM gönderir ve şablonun son_uretim_tarihi'ni bugüne çeker.
    /// $s : periyodik_sablonlar satırı (assoc array)
    /// $bugun : 'Y-m-d'
    /// Dönüş: yeni iş emri id'si (>0) | 0 (bugün zaten üretilmiş) | null (site/personel pasif).
    /// "Bugün üretildi mi" kontrolü ATOMİK koşullu UPDATE ile yapılır; böylece cron'un
    /// paralel/tekrar çalışması veya panelden tekrarlı "Üret" mükerrer iş emri ÜRETMEZ.
    public static function uret(PDO $db, array $s, string $bugun) {
        $firma_id    = (int)$s['firma_id'];
        $site_id     = (int)$s['site_id'];
        $personel_id = (int)$s['personel_id'];

        // KURAL 1: site ve personel hâlâ bu firmaya ait ve aktif mi?
        $k = $db->prepare("
            SELECT
                (SELECT COUNT(*) FROM siteler     WHERE id = :sid AND firma_id = :fid  AND aktif = 1) AS site_ok,
                (SELECT COUNT(*) FROM personeller WHERE id = :pid AND firma_id = :fid2 AND aktif = 1) AS personel_ok
        ");
        $k->execute([
            ':sid' => $site_id, ':fid' => $firma_id,
            ':pid' => $personel_id, ':fid2' => $firma_id,
        ]);
        $ok = $k->fetch(PDO::FETCH_ASSOC);
        if ((int)$ok['site_ok'] === 0 || (int)$ok['personel_ok'] === 0) {
            return null;
        }

        $db->beginTransaction();
        try {
            // ATOMİK "günü kap": yalnızca bugün henüz üretilmemişse 1 satır günceller.
            // Eşzamanlı ikinci çağrı satır kilidinde bekler, sonra koşul tutmaz -> 0 satır.
            // Transaction içinde olduğu için INSERT başarısız olursa kapma da geri alınır.
            $claim = $db->prepare("UPDATE periyodik_sablonlar SET son_uretim_tarihi = :b
                                   WHERE id = :id AND (son_uretim_tarihi IS NULL OR son_uretim_tarihi <> :b2)");
            $claim->execute([':b' => $bugun, ':id' => (int)$s['id'], ':b2' => $bugun]);
            if ($claim->rowCount() === 0) {
                $db->rollBack();
                return 0; // bugün zaten üretilmiş
            }

            $ins = $db->prepare("
                INSERT INTO is_emirleri
                    (firma_id, site_id, personel_id, sablon_id, baslik, aciklama, durum, planlanan_baslangic_tarihi)
                VALUES
                    (:firma_id, :site_id, :personel_id, :sablon_id, :baslik, :aciklama, 'bekliyor', :planlanan)
            ");
            $ins->execute([
                ':firma_id'    => $firma_id,
                ':site_id'     => $site_id,
                ':personel_id' => $personel_id,
                ':sablon_id'   => (int)$s['id'],
                ':baslik'      => $s['baslik'],
                ':aciklama'    => $s['aciklama'],
                ':planlanan'   => $bugun . ' 08:00:00',
            ]);
            $yeni_id = (int)$db->lastInsertId();

            // Checklist (alt görevler) kopyala.
            if (!empty($s['alt_gorevler'])) {
                $altIns = $db->prepare("
                    INSERT INTO is_emirleri_alt_gorevler (firma_id, is_emri_id, gorev_metni)
                    VALUES (:fid, :ieid, :metin)
                ");
                foreach (preg_split('/\r\n|\r|\n/', $s['alt_gorevler']) as $satir) {
                    $metin = trim($satir);
                    if ($metin === '') continue;
                    $altIns->execute([':fid' => $firma_id, ':ieid' => $yeni_id, ':metin' => $metin]);
                }
            }

            // (son_uretim_tarihi yukarıdaki atomik "kapma" adımında zaten işaretlendi.)
            $db->commit();
        } catch (Throwable $e) {
            if ($db->inTransaction()) {
                $db->rollBack();
            }
            throw $e;
        }

        // Personele bildirim (opsiyonel; hatası üretimi bozmaz).
        try {
            $t = $db->prepare("SELECT fcm_token FROM personeller WHERE id = :pid AND firma_id = :fid");
            $t->execute([':pid' => $personel_id, ':fid' => $firma_id]);
            $fcm = $t->fetchColumn();
            if (!empty($fcm)) {
                FcmSender::send($fcm, 'Yeni Periyodik Görev', $s['baslik'], [
                    'tip'        => 'yeni_gorev',
                    'is_emri_id' => (string)$yeni_id,
                ]);
            }
        } catch (Throwable $e) {
            // sessizce yut
        }

        return $yeni_id;
    }
}
