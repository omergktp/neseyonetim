<?php
// backend/core/Database.php

require_once __DIR__ . '/../config.php';

class Database {
    private $host = DB_HOST;
    private $db_name = DB_NAME;
    private $username = DB_USER;
    private $password = DB_PASS;
    private $charset = DB_CHARSET;
    public $conn;

    // Veritabanı bağlantısını alır
    public function getConnection() {
        $this->conn = null;

        try {
            $dsn = "mysql:host=" . $this->host . ";dbname=" . $this->db_name . ";charset=" . $this->charset;
            $options = [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION, // Hataları Exception olarak fırlat
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,       // Verileri Associative Array (key-value) olarak getir
                PDO::ATTR_EMULATE_PREPARES   => false,                  // Gerçek Prepared Statements kullan (Güvenlik için önemli)
            ];
            
            $this->conn = new PDO($dsn, $this->username, $this->password, $options);
        } catch(PDOException $exception) {
            // API yapısı için JSON hata dönebiliriz. Şimdilik düz hata mesajı.
            header('Content-Type: application/json');
            echo json_encode(["hata" => "Veritabanı bağlantı hatası: " . $exception->getMessage()]);
            exit;
        }

        return $this->conn;
    }
}
