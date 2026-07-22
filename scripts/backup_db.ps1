# GLOW SAHA - Gunluk MySQL yedegi
# Zamanlanmis gorev "GlowSaha DB Yedek" tarafindan her gece calistirilir.
# Yedekler db\backups altina tarih damgali yazilir; 14 gunden eskiler silinir.

$ErrorActionPreference = 'Stop'

$mysqldump = 'C:\laragon\bin\mysql\mysql-8.4.3-winx64\bin\mysqldump.exe'
$dbName    = 'glow_saha'
$backupDir = Join-Path $PSScriptRoot '..\db\backups'
$logFile   = Join-Path $backupDir 'backup.log'

if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Force $backupDir | Out-Null }

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$file  = Join-Path $backupDir "glow_saha_$stamp.sql"

try {
    & $mysqldump -u root --port=3306 --single-transaction --routines --triggers $dbName | Out-File -Encoding utf8 $file
    if ((Get-Item $file).Length -lt 1KB) { throw "Yedek dosyasi supheli derecede kucuk." }

    # 14 gunden eski yedekleri temizle
    Get-ChildItem $backupDir -Filter 'glow_saha_*.sql' |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
        Remove-Item -Force -Confirm:$false

    Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') OK  $([IO.Path]::GetFileName($file)) ($([math]::Round((Get-Item $file).Length/1KB)) KB)"
} catch {
    Add-Content $logFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') HATA $($_.Exception.Message)"
    exit 1
}
