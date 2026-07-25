<?php
// backend/core/AuthMiddleware.php

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/JwtHandler.php';

class AuthMiddleware {
    public static function authenticate() {
        $headers = apache_request_headers();
        $authHeader = null;
        
        if (isset($headers['Authorization'])) {
            $authHeader = $headers['Authorization'];
        } elseif (isset($_SERVER['HTTP_AUTHORIZATION'])) {
            $authHeader = $_SERVER['HTTP_AUTHORIZATION'];
        } elseif (isset($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
            $authHeader = $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
        }

        if (!$authHeader) {
            http_response_code(401);
            echo json_encode(["message" => "Yetkilendirme başlığı (Authorization) eksik."]);
            exit;
        }

        $arr = explode(" ", $authHeader);
        if (count($arr) !== 2 || $arr[0] !== 'Bearer') {
            http_response_code(401);
            echo json_encode(["message" => "Geçersiz token formatı. (Bearer Token bekleniyor)"]);
            exit;
        }

        $jwt = $arr[1];
        $jwtHandler = new JwtHandler(JWT_SECRET);
        $decoded = $jwtHandler->decode($jwt);

        if (!$decoded) {
            http_response_code(401);
            echo json_encode(["message" => "Geçersiz veya süresi dolmuş token."]);
            exit;
        }

        // Başarılıysa kullanıcı bilgilerini döndür
        return $decoded;
    }
}
