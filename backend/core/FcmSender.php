<?php
// backend/core/FcmSender.php
// FCM HTTP v1 API ile bildirim gönderir. Servis hesabı JSON'undan OAuth2 access token üretir.
// Eski "server key" yöntemi Google tarafından kapatıldığı için v1 API kullanılır.

require_once __DIR__ . '/../config.php';

class FcmSender {

    // base64url kodlama
    private static function b64url($data) {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    // Servis hesabıyla imzalı JWT üretip OAuth2 access token alır. Token'ı geçici dosyada ~1 saat cache'ler.
    private static function getAccessToken() {
        $saPath = FCM_SERVICE_ACCOUNT;
        if (!is_string($saPath) || !file_exists($saPath)) {
            return null;
        }

        // Basit dosya cache (access token ~3600 sn geçerli)
        $cacheFile = sys_get_temp_dir() . '/glow_fcm_token.json';
        if (file_exists($cacheFile)) {
            $cached = json_decode(file_get_contents($cacheFile), true);
            if (isset($cached['access_token'], $cached['exp']) && $cached['exp'] > time() + 60) {
                return $cached['access_token'];
            }
        }

        $sa = json_decode(file_get_contents($saPath), true);
        if (!isset($sa['client_email'], $sa['private_key'], $sa['token_uri'])) {
            return null;
        }

        $now = time();
        $header = ['alg' => 'RS256', 'typ' => 'JWT'];
        $claims = [
            'iss'   => $sa['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud'   => $sa['token_uri'],
            'iat'   => $now,
            'exp'   => $now + 3600,
        ];

        $unsigned = self::b64url(json_encode($header)) . '.' . self::b64url(json_encode($claims));
        $signature = '';
        if (!openssl_sign($unsigned, $signature, $sa['private_key'], OPENSSL_ALGO_SHA256)) {
            return null;
        }
        $jwt = $unsigned . '.' . self::b64url($signature);

        // Access token al
        $ch = curl_init($sa['token_uri']);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => http_build_query([
                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion'  => $jwt,
            ]),
            CURLOPT_TIMEOUT => 10,
        ]);
        $resp = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($code !== 200) {
            return null;
        }
        $data = json_decode($resp, true);
        if (!isset($data['access_token'])) {
            return null;
        }

        // Cache'e yaz
        @file_put_contents($cacheFile, json_encode([
            'access_token' => $data['access_token'],
            'exp' => $now + (int)($data['expires_in'] ?? 3600),
        ]));

        return $data['access_token'];
    }

    /**
     * Tek bir cihaza bildirim gönderir.
     * @return bool Başarılıysa true. Yapılandırma eksikse/hatada false (çağıran akışı bozmaz).
     */
    public static function send($deviceToken, $title, $body, array $dataPayload = []) {
        if (empty($deviceToken) || FCM_PROJECT_ID === '') {
            return false;
        }

        $accessToken = self::getAccessToken();
        if (!$accessToken) {
            return false;
        }

        // v1 data alanları string olmalı
        $stringData = [];
        foreach ($dataPayload as $k => $v) {
            $stringData[$k] = (string)$v;
        }

        $message = [
            'message' => [
                'token' => $deviceToken,
                'notification' => ['title' => $title, 'body' => $body],
                'data' => $stringData,
                'android' => ['priority' => 'high'],
            ],
        ];

        $url = 'https://fcm.googleapis.com/v1/projects/' . FCM_PROJECT_ID . '/messages:send';
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $accessToken,
                'Content-Type: application/json',
            ],
            CURLOPT_POSTFIELDS => json_encode($message),
            CURLOPT_TIMEOUT => 10,
        ]);
        $resp = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        return $code === 200;
    }
}
