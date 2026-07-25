-- =====================================================================
-- 0003_rpc_mobil.sql  —  Mobil (personel) yazma uçlarının RPC karşılıkları
--
-- Tüm yazmalar SECURITY DEFINER fonksiyonlardan geçer (0002'de tablo
-- düzeyi yazma reddedildi). Fonksiyonlar owner (postgres) olarak çalışır,
-- RLS'i baypas eder; bu yüzden firma_id / personel_id / rol kontrolü
-- BURADA, JWT claim'lerinden (app.current_*) açıkça yapılır.
--
-- Dosyalar: Postgres dosya yazamaz. Flutter fotoğrafı Storage'a yükler
-- (bkz. 0004_storage.sql) ve RPC'ye nesne YOLUNU (path) geçer. 10MB /
-- jpeg-png-webp kuralı istemci + Storage tarafında uygulanır.
--
-- HTTP kodu: PostgREST, 'PTxyz' biçimli SQLSTATE'i HTTP xyz'ye çevirir.
-- =====================================================================

-- Kimlik guard'ı: firma_id claim yoksa (anon) 401.
create or replace function app.require_firma() returns bigint
    language plpgsql stable
    as $$
declare fid bigint := app.current_firma_id();
begin
    if fid is null then
        raise exception 'Oturum bulunamadı.' using errcode = 'PT401';
    end if;
    return fid;
end $$;

-- ---------------------------------------------------------------------
-- 1) report_fault — Arıza bildir  (durum='acik')
-- ---------------------------------------------------------------------
create or replace function public.report_fault(
    p_site_id       bigint,
    p_baslik        text,
    p_aciklama      text default null,
    p_fotograf_path text default null
) returns jsonb
    language plpgsql security definer
    set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_firma();
    v_pid   bigint := app.current_personel_id();
    v_id    bigint;
begin
    if p_site_id is null or coalesce(btrim(p_baslik), '') = '' then
        raise exception 'Eksik bilgi. (site_id, baslik gerekli)' using errcode = 'PT400';
    end if;

    -- Tenant + sahiplik: tesis bu firmaya ait mi?
    if not exists (select 1 from siteler where id = p_site_id and firma_id = v_firma) then
        raise exception 'Geçersiz tesis.' using errcode = 'PT422';
    end if;

    insert into arizalar (firma_id, site_id, bildiren_personel_id, baslik, aciklama, fotograf_url, durum)
    values (v_firma, p_site_id, v_pid, btrim(p_baslik), nullif(btrim(coalesce(p_aciklama,'')),''), p_fotograf_path, 'acik')
    returning id into v_id;

    return jsonb_build_object('message', 'Arıza bildirimi alındı.', 'id', v_id);
end $$;

-- ---------------------------------------------------------------------
-- 2) update_fault — Arıza durumu güncelle (yalnız atanmış teknik)
--    izinli durumlar: cozuldu | bekliyor | dis_destek ; cozuldu ise foto zorunlu
-- ---------------------------------------------------------------------
create or replace function public.update_fault(
    p_ariza_id              bigint,
    p_durum                 text,
    p_not                   text default null,
    p_cozum_fotograf_path   text default null
) returns jsonb
    language plpgsql security definer
    set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_firma();
    v_pid   bigint := app.current_personel_id();
    v_n     integer;
    v_msg   text;
begin
    if p_ariza_id is null or coalesce(p_durum,'') = '' then
        raise exception 'ariza_id ve durum gerekli.' using errcode = 'PT400';
    end if;
    if p_durum not in ('cozuldu','bekliyor','dis_destek') then
        raise exception 'Geçersiz durum.' using errcode = 'PT400';
    end if;
    if p_durum = 'cozuldu' and coalesce(btrim(p_cozum_fotograf_path),'') = '' then
        raise exception 'Çözüm fotoğrafı gerekli.' using errcode = 'PT400';
    end if;

    update arizalar
       set durum              = p_durum::ariza_durum,
           teknik_notu        = p_not,
           cozum_tarihi       = case when p_durum = 'cozuldu' then now() else cozum_tarihi end,
           cozum_fotograf_url = case when p_durum = 'cozuldu' then p_cozum_fotograf_path else cozum_fotograf_url end
     where id = p_ariza_id
       and firma_id = v_firma
       and teknik_personel_id = v_pid
       and durum <> 'cozuldu';
    get diagnostics v_n = row_count;

    if v_n = 0 then
        raise exception 'Arıza güncellenemedi (size ait değil veya zaten çözülmüş).' using errcode = 'PT400';
    end if;

    v_msg := case p_durum
        when 'cozuldu'    then 'Arıza çözüldü olarak kapatıldı.'
        when 'bekliyor'   then 'Arıza ''malzeme bekliyor'' olarak güncellendi.'
        when 'dis_destek' then 'Arıza ''dış destek gerekli'' olarak yöneticiye iletildi.'
    end;
    return jsonb_build_object('message', v_msg);
end $$;

-- ---------------------------------------------------------------------
-- 3) save_task — Görevi tamamla (bekliyor|devam_ediyor -> tamamlandi)
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
    v_n     integer;
begin
    if p_is_emri_id is null or p_enlem is null or p_boylam is null then
        raise exception 'Eksik bilgi gönderildi. (is_emri_id, tamamlanma_enlem, tamamlanma_boylam gerekli)' using errcode = 'PT400';
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
-- 4) start_task — Görevi başlat + QR / Konum(Haversine, >100m red) doğrulama
--    bekliyor|devam_ediyor -> devam_ediyor
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
    v_lat1 double precision; v_lng1 double precision;
    v_lat2 double precision; v_lng2 double precision;
    v_a double precision; v_mesafe double precision;
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
            -- Haversine (metre), R=6371000
            v_lat1 := radians(p_enlem::double precision);  v_lng1 := radians(p_boylam::double precision);
            v_lat2 := radians(v_gorev.site_enlem::double precision); v_lng2 := radians(v_gorev.site_boylam::double precision);
            v_a := sin((v_lat2 - v_lat1)/2)^2 + cos(v_lat1) * cos(v_lat2) * sin((v_lng2 - v_lng1)/2)^2;
            v_mesafe := 6371000 * 2 * atan2(sqrt(v_a), sqrt(1 - v_a));
            if v_mesafe > 100 then
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
-- 5) update_subtask — Checklist adımı işaretle (yalnız kendi görevinin)
-- ---------------------------------------------------------------------
create or replace function public.update_subtask(
    p_alt_gorev_id bigint,
    p_yapildi      boolean
) returns jsonb
    language plpgsql security definer
    set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_firma();
    v_pid   bigint := app.current_personel_id();
    v_durum is_emri_durum;
begin
    if p_alt_gorev_id is null or p_yapildi is null then
        raise exception 'Eksik bilgi. (alt_gorev_id, yapildi gerekli)' using errcode = 'PT400';
    end if;

    select ie.durum into v_durum
      from is_emirleri_alt_gorevler ag
      join is_emirleri ie on ag.is_emri_id = ie.id
     where ag.id = p_alt_gorev_id and ag.firma_id = v_firma and ie.personel_id = v_pid
     limit 1;

    if not found then
        raise exception 'Adım bulunamadı veya size ait değil.' using errcode = 'PT404';
    end if;
    if v_durum in ('tamamlandi','iptal') then
        raise exception 'Bu görev kapatılmış; adımlar güncellenemez.' using errcode = 'PT409';
    end if;

    update is_emirleri_alt_gorevler set yapildi_mi = p_yapildi
     where id = p_alt_gorev_id and firma_id = v_firma;

    return jsonb_build_object('message', 'Adım güncellendi.', 'yapildi_mi', p_yapildi);
end $$;

-- ---------------------------------------------------------------------
-- 6) add_expense — Masraf/malzeme talebi (yalnız teknik|yonetici)
-- ---------------------------------------------------------------------
create or replace function public.add_expense(
    p_is_emri_id      bigint default null,
    p_ariza_id        bigint default null,
    p_kalem_adi       text default null,
    p_tutar           numeric default null,
    p_fis_fotograf_path text default null
) returns jsonb
    language plpgsql security definer
    set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_firma();
    v_pid   bigint := app.current_personel_id();
    v_rol   text   := app.current_rol();
    v_yonetici boolean := (v_rol = 'yonetici');
begin
    if v_rol not in ('teknik','yonetici') then
        raise exception 'Bu işlem için sadece Teknik Personel yetkilidir.' using errcode = 'PT403';
    end if;
    if (p_is_emri_id is null and p_ariza_id is null)
       or coalesce(btrim(p_kalem_adi),'') = '' or p_tutar is null
       or coalesce(btrim(p_fis_fotograf_path),'') = '' then
        raise exception 'Eksik bilgi gönderildi. (is_emri_id veya ariza_id, kalem_adi, tutar, fis_fotograf_url)' using errcode = 'PT400';
    end if;
    if p_tutar <= 0 then
        raise exception 'Tutar geçerli ve pozitif bir sayı olmalı.' using errcode = 'PT400';
    end if;

    -- Sahiplik: yönetici firma içi her kayda; teknik yalnız kendine atanmışa
    if p_is_emri_id is not null then
        if not exists (
            select 1 from is_emirleri
             where id = p_is_emri_id and firma_id = v_firma
               and (v_yonetici or personel_id = v_pid)
        ) then
            raise exception 'Geçersiz iş emri (size atanmış değil).' using errcode = 'PT422';
        end if;
    end if;
    if p_ariza_id is not null then
        if not exists (
            select 1 from arizalar
             where id = p_ariza_id and firma_id = v_firma
               and (v_yonetici or teknik_personel_id = v_pid)
        ) then
            raise exception 'Geçersiz arıza (size atanmış değil).' using errcode = 'PT422';
        end if;
    end if;

    insert into malzeme_talepleri
        (firma_id, personel_id, is_emri_id, ariza_id, kalem_adi, tutar, fis_fatura_fotograf, durum)
    values
        (v_firma, v_pid, p_is_emri_id, p_ariza_id, btrim(p_kalem_adi), p_tutar, p_fis_fotograf_path, 'bekliyor');

    return jsonb_build_object('message', 'Masraf formu başarıyla gönderildi ve onaya sunuldu.');
end $$;

-- ---------------------------------------------------------------------
-- 7) set_fcm_token — FCM token kaydet (aynı cihazı başka personelden temizle)
-- ---------------------------------------------------------------------
create or replace function public.set_fcm_token(p_fcm_token text)
returns jsonb
    language plpgsql security definer
    set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_firma();
    v_pid   bigint := app.current_personel_id();
begin
    if coalesce(btrim(p_fcm_token),'') = '' then
        raise exception 'fcm_token gerekli.' using errcode = 'PT400';
    end if;
    update personeller set fcm_token = null where fcm_token = p_fcm_token and id <> v_pid;
    update personeller set fcm_token = p_fcm_token where id = v_pid and firma_id = v_firma;
    return jsonb_build_object('message', 'FCM token kaydedildi.');
end $$;

-- ---------------------------------------------------------------------
-- 8) clear_fcm_token — Çıkışta token temizle
-- ---------------------------------------------------------------------
create or replace function public.clear_fcm_token()
returns jsonb
    language plpgsql security definer
    set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_firma();
    v_pid   bigint := app.current_personel_id();
begin
    update personeller set fcm_token = null where id = v_pid and firma_id = v_firma;
    return jsonb_build_object('message', 'Bildirim aboneliği kaldırıldı.');
end $$;

-- ---------------------------------------------------------------------
-- Yürütme izinleri: yalnız authenticated. (anon çağıramaz.)
-- ---------------------------------------------------------------------
revoke all on function
    public.report_fault(bigint, text, text, text),
    public.update_fault(bigint, text, text, text),
    public.save_task(bigint, numeric, numeric, text),
    public.start_task(bigint, text, text, numeric, numeric),
    public.update_subtask(bigint, boolean),
    public.add_expense(bigint, bigint, text, numeric, text),
    public.set_fcm_token(text),
    public.clear_fcm_token()
    from public, anon;

grant execute on function
    public.report_fault(bigint, text, text, text),
    public.update_fault(bigint, text, text, text),
    public.save_task(bigint, numeric, numeric, text),
    public.start_task(bigint, text, text, numeric, numeric),
    public.update_subtask(bigint, boolean),
    public.add_expense(bigint, bigint, text, numeric, text),
    public.set_fcm_token(text),
    public.clear_fcm_token()
    to authenticated;
