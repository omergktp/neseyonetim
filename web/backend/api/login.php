<?php
// backend/api/login.php

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Max-Age: 3600");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

require_once '../config.php';
require_once '../core/Database.php';
require_once '../core/JwtHandler.php';

$database = new Database();
$db = $database->getConnection();

$data = json_decode(file_get_contents("php://input"));

if (isset($data->firma_kodu) && isset($data->telefon) && isset($data->sifre)) {
    $firma_kodu = htmlspecialchars(strip_tags($data->firma_kodu));
    $telefon = htmlspecialchars(strip_tags($data->telefon));
    $sifre = (string)$data->sifre; // Şifre ham haliyle alınır; hash ile karşılaştırılır (dönüştürme YOK)
    
    // 1. Önce firmayı bul
    $firma_query = "SELECT id, ad, logo, hex_color, aktif FROM firmalar WHERE firma_kodu = :firma_kodu LIMIT 1";
    $stmt = $db->prepare($firma_query);
    $stmt->bindParam(':firma_kodu', $firma_kodu);
    $stmt->execute();
    
    if ($stmt->rowCount() > 0) {
        $firma = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($firma['aktif'] == 0) {
            http_response_code(403);
            echo json_encode(["message" => "Firma hesabı aktif değil."]);
            exit;
        }

        $firma_id = $firma['id'];

        // 2. Personeli bul (Multi-Tenant kuralı: WHERE firma_id = ?)
        $personel_query = "SELECT id, ad_soyad, sifre, rol, aktif FROM personeller WHERE firma_id = :firma_id AND telefon = :telefon LIMIT 1";
        $p_stmt = $db->prepare($personel_query);
        $p_stmt->bindParam(':firma_id', $firma_id);
        $p_stmt->bindParam(':telefon', $telefon);
        $p_stmt->execute();

        if ($p_stmt->rowCount() > 0) {
            $personel = $p_stmt->fetch(PDO::FETCH_ASSOC);

            if ($personel['aktif'] == 0) {
                http_response_code(403);
                echo json_encode(["message" => "Kullanıcı hesabı aktif değil."]);
                exit;
            }

            // Şifre doğrulama: kayıt hash'li ise password_verify; eski düz metin kayıt ise
            // doğrulanır ve başarılı olunca otomatik hash'e yükseltilir (kademeli geçiş).
            $stored = $personel['sifre'];
            $gecerli = false;
            if (preg_match('/^\$2[aby]\$/', $stored) || strpos($stored, '$argon') === 0) {
                $gecerli = password_verify($sifre, $stored);
            } elseif (hash_equals($stored, $sifre)) {
                $gecerli = true;
                $yeniHash = password_hash($sifre, PASSWORD_DEFAULT);
                $upd = $db->prepare("UPDATE personeller SET sifre = :s WHERE id = :id");
                $upd->execute([':s' => $yeniHash, ':id' => $personel['id']]);
            }

            if ($gecerli) {
                $jwtHandler = new JwtHandler(JWT_SECRET);
                $token = $jwtHandler->encode([
                    "personel_id" => $personel['id'],
                    "firma_id" => $firma_id,
                    "rol" => $personel['rol']
                ]);

                http_response_code(200);
                echo json_encode([
                    "message" => "Giriş başarılı.",
                    "token" => $token,
                    "kullanici" => [
                        "ad_soyad" => $personel['ad_soyad'],
                        "rol" => $personel['rol']
                    ],
                    "firma" => [
                        "ad" => $firma['ad'],
                        "logo" => $firma['logo'],
                        "tema_rengi" => $firma['hex_color']
                    ]
                ]);
            } else {
                http_response_code(401);
                echo json_encode(["message" => "Şifre hatalı."]);
            }
        } else {
            http_response_code(404);
            echo json_encode(["message" => "Kullanıcı bulunamadı."]);
        }
    } else {
        http_response_code(404);
        echo json_encode(["message" => "Geçersiz firma kodu."]);
    }
} else {
    http_response_code(400);
    echo json_encode(["message" => "Eksik bilgi gönderildi. (firma_kodu, telefon, sifre gerekli)"]);
}
