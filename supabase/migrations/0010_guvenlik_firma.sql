-- =====================================================================
-- 0010_guvenlik_firma.sql  —  Güvenlik sıkılaştırmaları + Firma ayarları
--
-- 1) Konum doğrulaması sunucuya taşınır (KURAL 4'ün sunucu ayağı):
--    * app.mesafe_metre — ortak Haversine yardımcısı
--    * start_task: eşik 100m -> 50m (plan.md FAZ 4 ile uyumlu)
--    * save_task: görev TAMAMLAMA artık sunucuda da mesafe doğrular
--      (önceden yalnız istemci kontrol ediyordu; istemci baypas edilebilirdi)
-- 2) personeller: tablo düzeyi SELECT grant'ı kolon düzeyine indirilir.
--    'sifre' (bcrypt hash) ve 'fcm_token' PostgREST'ten okunamaz olur.
--    (RLS satırı filtreler ama kolonu filtreleyemez; yönetici token'ıyla
--    firma personelinin hash'leri sızıyordu.)
-- 3) Storage: masraf-fis bucket'ını yalnız teknik + yonetici okur.
--    (Önceden aynı firmadaki temizlik personeli de fiş görsellerini
--    görebiliyordu.)
-- 4) admin_rapor: ay sınırı Europe/Istanbul'da hesaplanır (önceden UTC'de
--    çözülüyordu; ay başı/sonu 3 saat kayıyordu).
-- 5) Firma ayarları RPC'si: admin_firma_guncelle (ad / tema rengi / logo).
--    Okuma RPC gerektirmez: RLS zaten yalnız kendi firmasını gösterir
--    (PostgREST: firmalar?select=*).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1a) Ortak mesafe yardımcısı (Haversine, metre; R=6371000)
-- ---------------------------------------------------------------------
create or replace function app.mesafe_metre(
    p_lat1 numeric, p_lng1 numeric, p_lat2 numeric, p_lng2 numeric
) returns double precision
    language plpgsql immutable
    as $$
declare
    v_lat1 double precision := radians(p_lat1::double precision);
    v_lng1 double precision := radians(p_lng1::double precision);
    v_lat2 double precision := radians(p_lat2::double precision);
    v_lng2 double precision := radians(p_lng2::double precision);
    v_a double precision;
begin
    v_a := sin((v_lat2 - v_lat1)/2)^2 + cos(v_lat1) * cos(v_lat2) * sin((v_lng2 - v_lng1)/2)^2;
    return 6371000 * 2 * atan2(sqrt(v_a), sqrt(1 - v_a));
end $$;

-- Tesis yakınlık eşiği (metre). Mobil istemcideki değerle aynı tutulmalı.
create or replace function app.konum_esigi_metre() returns integer
    language sql immutable
    as $$ select 50 $$;

-- ---------------------------------------------------------------------
-- 1b) start_task — eşik 50m'ye çekildi, Haversine ortak yardımcıya taşındı
-- ---------------------------------------------------------------------
create or replace function public.start_task(
    p_is_emri_id bigint,
    p_yontem     text,
    p_qr_deger   text default null,
    p_enlem      numeric default null,
    p_boylam     numeric default null
) returns jsonb
    language plpgsql security definer
    set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_firma();
    v_pid   bigint := app.current_personel_id();
    v_gorev record;
    v_kodlar text[];
    v_mesafe double precision;
    v_n integer;
begin
    if p_is_emri_id is null or coalesce(p_yontem,'') = '' then
        raise exception 'Eksik bilgi. (is_emri_id, yontem gerekli)' using errcode = 'PT400';
    end if;
    if p_yontem not in ('qr','konum') then
        raise exception 'Geçersiz yöntem. (qr veya konum)' using errcode = 'PT400';
    end if;

    -- Görev + tesis (sahiplik: kendi görevi)
    select ie.id, ie.durum, ie.qr_kod as gorev_qr,
           s.qr_kod as site_qr, s.enlem as site_enlem, s.boylam as site_boylam
      into v_gorev
      from is_emirleri ie
      left join siteler s on ie.site_id = s.id
     where ie.id = p_is_emri_id and ie.firma_id = v_firma and ie.personel_id = v_pid
     limit 1;

    if not found then
        raise exception 'Görev bulunamadı veya size ait değil.' using errcode = 'PT404';
    end if;
    if v_gorev.durum in ('tamamlandi','iptal') then
        raise exception 'Bu görev zaten kapatılmış.' using errcode = 'PT409';
    end if;

    if p_yontem = 'qr' then
        v_kodlar := array_remove(array_remove(array[v_gorev.gorev_qr, v_gorev.site_qr], null), '');
        if array_length(v_kodlar, 1) is null then
            raise exception 'Bu görev veya tesis için QR tanımlı değil. Lütfen ''Konumla Başlat'' seçeneğini kullanın.' using errcode = 'PT422';
        end if;
        if coalesce(btrim(p_qr_deger),'') = '' or not (btrim(p_qr_deger) = any(v_kodlar)) then
            raise exception 'Okutulan QR kodu bu görevin tesisine ait değil.' using errcode = 'PT422';
        end if;

    else  -- konum
        -- Yalnız tesis koordinatı geçerliyse (null/0 değil) mesafe doğrulanır.
        if v_gorev.site_enlem is not null and v_gorev.site_boylam is not null
           and v_gorev.site_enlem::double precision <> 0 and v_gorev.site_boylam::double precision <> 0 then
            if p_enlem is null or p_boylam is null then
                raise exception 'Konumla başlatmak için konum verisi gerekli. Lütfen uygulamayı güncelleyin.' using errcode = 'PT422';
            end if;
            v_mesafe := app.mesafe_metre(p_enlem, p_boylam, v_gorev.site_enlem, v_gorev.site_boylam);
            if v_mesafe > app.konum_esigi_metre() then
                raise exception 'Tesise yeterince yakın değilsiniz (ölçülen: % m).', round(v_mesafe) using errcode = 'PT422';
            end if;
        end if;
    end if;

    update is_emirleri set durum = 'devam_ediyor'
     where id = p_is_emri_id and firma_id = v_firma and personel_id = v_pid
       and durum in ('bekliyor','devam_ediyor');
    get diagnostics v_n = row_count;
    if v_n = 0 then
        raise exception 'Görev başlatılamadı (durumu değişmiş olabilir).' using errcode = 'PT409';
    end if;

    return jsonb_build_object('message', 'Görev başlatıldı.', 'durum', 'devam_ediyor');
end $$;

-- ---------------------------------------------------------------------
-- 1c) save_task — tamamlama konumu artık SUNUCUDA doğrulanır
--     (tesiste koordinat tanımlıysa 50m kuralı; yoksa eskisi gibi geçer)
-- ---------------------------------------------------------------------
create or replace function public.save_task(
    p_is_emri_id            bigint,
    p_enlem                 numeric,
    p_boylam                numeric,
    p_kapanis_fotograf_path text default null
) returns jsonb
    language plpgsql security definer
    set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_firma();
    v_pid   bigint := app.current_personel_id();
    v_site  record;
    v_mesafe double precision;
    v_n     integer;
begin
    if p_is_emri_id is null or p_enlem is null or p_boylam is null then
        raise exception 'Eksik bilgi gönderildi. (is_emri_id, tamamlanma_enlem, tamamlanma_boylam gerekli)' using errcode = 'PT400';
    end if;

    select s.enlem, s.boylam
      into v_site
      from is_emirleri ie
      left join siteler s on ie.site_id = s.id
     where ie.id = p_is_emri_id and ie.firma_id = v_firma and ie.personel_id = v_pid
     limit 1;

    if not found then
        raise exception 'Görev güncellenemedi. Görev bulunamadı veya size ait değil.' using errcode = 'PT400';
    end if;

    if v_site.enlem is not null and v_site.boylam is not null
       and v_site.enlem::double precision <> 0 and v_site.boylam::double precision <> 0 then
        v_mesafe := app.mesafe_metre(p_enlem, p_boylam, v_site.enlem, v_site.boylam);
        if v_mesafe > app.konum_esigi_metre() then
            raise exception 'Görev tesiste kapatılmalı; tesise yeterince yakın değilsiniz (ölçülen: % m).', round(v_mesafe) using errcode = 'PT422';
        end if;
    end if;

    update is_emirleri
       set durum                = 'tamamlandi',
           tamamlanma_tarihi    = now(),
           tamamlanma_enlem     = p_enlem,
           tamamlanma_boylam    = p_boylam,
           kapanis_fotograf_url = p_kapanis_fotograf_path
     where id = p_is_emri_id
       and firma_id = v_firma
       and personel_id = v_pid
       and durum in ('bekliyor','devam_ediyor');
    get diagnostics v_n = row_count;

    if v_n = 0 then
        raise exception 'Görev güncellenemedi. Görev bulunamadı veya size ait değil.' using errcode = 'PT400';
    end if;
    return jsonb_build_object('message', 'Görev başarıyla tamamlandı ve kaydedildi.');
end $$;

-- ---------------------------------------------------------------------
-- 2) personeller: kolon düzeyi SELECT (sifre + fcm_token + auth_user_id gizli)
-- ---------------------------------------------------------------------
revoke select on personeller from authenticated;
grant select (id, firma_id, ad_soyad, telefon, rol, olusturma_tarihi, aktif)
    on personeller to authenticated;

-- ---------------------------------------------------------------------
-- 3) Storage: masraf-fis yalnız teknik + yonetici okuyabilir
-- ---------------------------------------------------------------------
drop policy if exists "ozel_select" on storage.objects;

create policy "ozel_select" on storage.objects
    for select to authenticated
    using (
        bucket_id in ('is-emri-fotograf', 'ariza-fotograf')
        and (storage.foldername(name))[1] = app.current_firma_id()::text
    );

create policy "masraf_fis_select" on storage.objects
    for select to authenticated
    using (
        bucket_id = 'masraf-fis'
        and (storage.foldername(name))[1] = app.current_firma_id()::text
        and (app.is_yonetici() or app.current_rol() = 'teknik')
    );

-- ---------------------------------------------------------------------
-- 4) admin_rapor: ay sınırları Europe/Istanbul'da hesaplanır
-- ---------------------------------------------------------------------
create or replace function public.admin_rapor(p_month text default null, p_site_id bigint default null)
returns jsonb
    language plpgsql security definer set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_yonetici();
    v_month text := coalesce(p_month, to_char(now() at time zone 'Europe/Istanbul','YYYY-MM'));
    v_bas timestamptz; v_bit timestamptz;
    v_firma_ad text; v_site_ad text := 'Tüm Tesisler';
    v_gorev int; v_ariza int; v_masraf jsonb; v_toplam numeric;
begin
    if v_month !~ '^\d{4}-\d{2}$' then
        raise exception 'Geçersiz ay formatı. (YYYY-MM bekleniyor)' using errcode='PT400';
    end if;
    -- "yerel saat dilimindeki ay başı" -> timestamptz (önceden sunucu TZ'siydi)
    v_bas := ((v_month || '-01')::timestamp) at time zone 'Europe/Istanbul';
    v_bit := (((v_month || '-01')::date + interval '1 month')::timestamp) at time zone 'Europe/Istanbul';

    select ad into v_firma_ad from firmalar where id=v_firma;
    if p_site_id is not null then
        select ad into v_site_ad from siteler where id=p_site_id and firma_id=v_firma;
        if v_site_ad is null then
            raise exception 'Site firmanıza ait değil.' using errcode='PT422';
        end if;
    end if;

    select count(*) into v_gorev from is_emirleri
     where firma_id=v_firma and durum='tamamlandi'
       and tamamlanma_tarihi >= v_bas and tamamlanma_tarihi < v_bit
       and (p_site_id is null or site_id=p_site_id);

    select count(*) into v_ariza from arizalar
     where firma_id=v_firma and durum='cozuldu'
       and cozum_tarihi >= v_bas and cozum_tarihi < v_bit
       and (p_site_id is null or site_id=p_site_id);

    select coalesce(jsonb_agg(m order by m.olusturma_tarihi), '[]'::jsonb), coalesce(sum(m.tutar),0)
      into v_masraf, v_toplam
      from (
        select mt.id, mt.kalem_adi, mt.tutar, mt.durum, mt.olusturma_tarihi,
               p.ad_soyad as personel_adi, p.rol as personel_rol
          from malzeme_talepleri mt
          left join personeller p  on mt.personel_id=p.id
          left join is_emirleri ie on mt.is_emri_id=ie.id
          left join arizalar ar    on mt.ariza_id=ar.id
         where mt.firma_id=v_firma
           and mt.olusturma_tarihi >= v_bas and mt.olusturma_tarihi < v_bit
           and (p_site_id is null or ie.site_id=p_site_id or ar.site_id=p_site_id)
         order by mt.olusturma_tarihi
      ) m;

    return jsonb_build_object(
        'firma_ad', coalesce(v_firma_ad,''),
        'site_ad', v_site_ad,
        'donem', v_month,
        'istatistik', jsonb_build_object(
            'tamamlanan_gorev', v_gorev,
            'cozulen_ariza', v_ariza,
            'toplam_masraf', round(v_toplam,2)
        ),
        'masraflar', v_masraf
    );
end $$;

-- ---------------------------------------------------------------------
-- 5) admin_firma_guncelle — firma adı / tema rengi / logo (yalnız yönetici)
--    p_logo_set=true iken p_logo_path yazılır (null -> logo kaldırılır).
--    Logo DB'de diğer fotoğraflar gibi "bucket/obje_yolu" olarak saklanır.
-- ---------------------------------------------------------------------
create or replace function public.admin_firma_guncelle(
    p_ad        text,
    p_hex_color text,
    p_logo_path text default null,
    p_logo_set  boolean default false
) returns jsonb
    language plpgsql security definer set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_yonetici();
begin
    if coalesce(btrim(p_ad),'') = '' then
        raise exception 'Firma adı boş olamaz.' using errcode='PT400';
    end if;
    if p_hex_color is null or p_hex_color !~ '^#[0-9A-Fa-f]{6}$' then
        raise exception 'Geçersiz renk. (#RRGGBB bekleniyor)' using errcode='PT400';
    end if;
    if p_logo_set and p_logo_path is not null
       and p_logo_path !~ ('^firma-logo/' || v_firma || '/') then
        raise exception 'Geçersiz logo yolu.' using errcode='PT422';
    end if;

    update firmalar
       set ad        = btrim(p_ad),
           hex_color = p_hex_color,
           logo      = case when p_logo_set then p_logo_path else logo end
     where id = v_firma;

    perform app.log_action('firma_guncelle','firma',v_firma,
                           case when p_logo_set then 'logo da değiştirildi' else null end);
    return jsonb_build_object('message','Firma ayarları güncellendi.');
end $$;

-- ---------------------------------------------------------------------
-- Yürütme izinleri
-- ---------------------------------------------------------------------
revoke all on function
    public.admin_firma_guncelle(text, text, text, boolean)
    from public, anon;
grant execute on function
    public.admin_firma_guncelle(text, text, text, boolean)
    to authenticated;
