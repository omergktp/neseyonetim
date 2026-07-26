-- =====================================================================
-- 0011_giris_kuyruk_saha.sql — Uzman paneli "Hemen" maddeleri (sunucu ayağı)
--
-- 1) Giriş kilidi: login Edge Function için (anahtar bazlı) deneme sayacı.
--    5 hatalı deneme / 15 dk kilit. Yalnız service_role çağırabilir.
-- 2) Şifre politikası: admin_personel_ekle/guncelle min 10 karakter.
-- 3) Saha doğrulama: QR ile başlatmada da konum zorunlu (tesis koordinatı
--    varsa); tamamlanmada konum_dogrulandi bayrağı; siteler'e 0 koordinat
--    yasağı (CHECK) + mevcut 0/0 verinin NULL'a çekilmesi.
-- 4) Idempotency: report_fault / add_expense istemci istek_id'siyle mükerrer
--    kayda kapatıldı; save_task "zaten tamamlandı" durumunda hata yerine
--    başarı döner (offline kuyruk güvenle tekrar deneyebilir).
-- 5) set_fcm_token: cihaz temizliği artık yalnız aynı firma içinde.
-- 6) qr_kod gizliliği: siteler/is_emirleri SELECT grant'ları kolon düzeyine
--    indirildi (saha personeli QR değerini indiremez); yönetici paneli için
--    admin_qr_goster RPC'si eklendi; v_is_emri qr_kod'suz yeniden tanımlandı.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Giriş kilidi
-- ---------------------------------------------------------------------
create table if not exists app.login_kilit (
    anahtar      text primary key,          -- firma_kodu|telefon|ip
    sayac        integer not null default 0,
    ilk_deneme   timestamptz not null default now(),
    kilit_bitis  timestamptz
);

-- p_olay: 'kontrol' -> {kilitli, kalan_sn} | 'hata' -> sayaç artar,
-- 5. hatada 15 dk kilit | 'basari' -> kayıt silinir.
create or replace function public.login_guard(p_anahtar text, p_olay text)
returns jsonb
    language plpgsql security definer
    set search_path = app, public
    as $$
declare
    r app.login_kilit;
begin
    if coalesce(btrim(p_anahtar),'') = '' then
        return jsonb_build_object('kilitli', false);
    end if;

    select * into r from app.login_kilit where anahtar = p_anahtar;

    if p_olay = 'basari' then
        delete from app.login_kilit where anahtar = p_anahtar;
        return jsonb_build_object('kilitli', false);
    end if;

    if p_olay = 'hata' then
        if r is null or r.ilk_deneme < now() - interval '15 minutes' then
            insert into app.login_kilit (anahtar, sayac, ilk_deneme, kilit_bitis)
            values (p_anahtar, 1, now(), null)
            on conflict (anahtar) do update
               set sayac = 1, ilk_deneme = now(), kilit_bitis = null;
            return jsonb_build_object('kilitli', false);
        end if;
        update app.login_kilit
           set sayac = sayac + 1,
               kilit_bitis = case when sayac + 1 >= 5 then now() + interval '15 minutes' else kilit_bitis end
         where anahtar = p_anahtar
         returning * into r;
        return jsonb_build_object(
            'kilitli', r.kilit_bitis is not null and r.kilit_bitis > now(),
            'kalan_sn', coalesce(extract(epoch from (r.kilit_bitis - now()))::int, 0));
    end if;

    -- 'kontrol'
    if r.kilit_bitis is not null and r.kilit_bitis > now() then
        return jsonb_build_object('kilitli', true,
            'kalan_sn', extract(epoch from (r.kilit_bitis - now()))::int);
    end if;
    return jsonb_build_object('kilitli', false);
end $$;

revoke all on function public.login_guard(text, text) from public, anon, authenticated;
grant execute on function public.login_guard(text, text) to service_role;

-- ---------------------------------------------------------------------
-- 2) Şifre politikası (min 10 karakter)
-- ---------------------------------------------------------------------
create or replace function public.admin_personel_ekle(
    p_ad_soyad text, p_telefon text, p_sifre text, p_rol text
) returns jsonb
    language plpgsql security definer set search_path = public, app, extensions
    as $$
declare v_firma bigint := app.require_yonetici(); v_id bigint;
begin
    if coalesce(btrim(p_ad_soyad),'')='' or coalesce(btrim(p_telefon),'')=''
       or coalesce(btrim(p_sifre),'')='' or coalesce(p_rol,'')='' then
        raise exception 'Eksik bilgi. (ad_soyad, telefon, sifre, rol gerekli)' using errcode='PT400';
    end if;
    if length(p_sifre) < 10 then
        raise exception 'Şifre en az 10 karakter olmalı.' using errcode='PT400';
    end if;
    if p_rol not in ('yonetici','temizlik','teknik') then
        raise exception 'Geçersiz rol.' using errcode='PT400';
    end if;
    begin
        insert into personeller (firma_id, ad_soyad, telefon, sifre, rol)
        values (v_firma, btrim(p_ad_soyad), btrim(p_telefon),
                extensions.crypt(p_sifre, extensions.gen_salt('bf')), p_rol::personel_rol)
        returning id into v_id;
    exception when unique_violation then
        raise exception 'Bu telefon numarası firmanızda zaten kayıtlı.' using errcode='PT409';
    end;
    perform app.log_action('personel_ekle','personel',v_id,'rol: '||p_rol);
    return jsonb_build_object('message','Personel eklendi.','id',v_id);
end $$;

create or replace function public.admin_personel_guncelle(
    p_id bigint, p_ad_soyad text, p_telefon text, p_rol text, p_sifre text default null
) returns jsonb
    language plpgsql security definer set search_path = public, app, extensions
    as $$
declare v_firma bigint := app.require_yonetici(); v_sifre_var boolean := coalesce(btrim(p_sifre),'')<>''; v_n int;
begin
    if not exists (select 1 from personeller where id=p_id and firma_id=v_firma) then
        raise exception 'Personel bulunamadı.' using errcode='PT404';
    end if;
    if coalesce(btrim(p_ad_soyad),'')='' or coalesce(btrim(p_telefon),'')='' or coalesce(p_rol,'')='' then
        raise exception 'Eksik bilgi. (ad_soyad, telefon, rol gerekli)' using errcode='PT400';
    end if;
    if v_sifre_var and length(p_sifre) < 10 then
        raise exception 'Şifre en az 10 karakter olmalı.' using errcode='PT400';
    end if;
    if p_rol not in ('yonetici','temizlik','teknik') then
        raise exception 'Geçersiz rol.' using errcode='PT400';
    end if;
    begin
        update personeller
           set ad_soyad = btrim(p_ad_soyad),
               telefon  = btrim(p_telefon),
               rol      = p_rol::personel_rol,
               sifre    = case when v_sifre_var
                               then extensions.crypt(p_sifre, extensions.gen_salt('bf'))
                               else sifre end
         where id = p_id and firma_id = v_firma;
        get diagnostics v_n = row_count;
    exception when unique_violation then
        raise exception 'Bu telefon numarası firmanızda zaten kayıtlı.' using errcode='PT409';
    end;
    perform app.log_action('personel_guncelle','personel',p_id,
                           case when v_sifre_var then 'şifre de değiştirildi' else null end);
    return jsonb_build_object('message','Personel güncellendi.');
end $$;

-- ---------------------------------------------------------------------
-- 3a) siteler: 0 koordinat yasağı + mevcut verinin temizliği
-- ---------------------------------------------------------------------
update siteler set enlem = null, boylam = null
 where (enlem is not null and enlem = 0) or (boylam is not null and boylam = 0);

alter table siteler drop constraint if exists siteler_koordinat_gecerli;
alter table siteler add constraint siteler_koordinat_gecerli
    check ((enlem is null or enlem <> 0) and (boylam is null or boylam <> 0));

-- 3b) is_emirleri: tamamlanma konumunun doğrulanıp doğrulanamadığı
alter table is_emirleri add column if not exists konum_dogrulandi boolean;

-- ---------------------------------------------------------------------
-- 3c) start_task — QR dalında da konum doğrulaması (tesis koordinatı varsa).
--     "QR değerini bilen ofisten görev başlatır" senaryosunu kapatır.
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
    v_konum_gerekli boolean;
    v_n integer;
begin
    if p_is_emri_id is null or coalesce(p_yontem,'') = '' then
        raise exception 'Eksik bilgi. (is_emri_id, yontem gerekli)' using errcode = 'PT400';
    end if;
    if p_yontem not in ('qr','konum') then
        raise exception 'Geçersiz yöntem. (qr veya konum)' using errcode = 'PT400';
    end if;

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

    v_konum_gerekli := v_gorev.site_enlem is not null and v_gorev.site_boylam is not null;

    if p_yontem = 'qr' then
        v_kodlar := array_remove(array_remove(array[v_gorev.gorev_qr, v_gorev.site_qr], null), '');
        if array_length(v_kodlar, 1) is null then
            raise exception 'Bu görev veya tesis için QR tanımlı değil. Lütfen ''Konumla Başlat'' seçeneğini kullanın.' using errcode = 'PT422';
        end if;
        if coalesce(btrim(p_qr_deger),'') = '' or not (btrim(p_qr_deger) = any(v_kodlar)) then
            raise exception 'Okutulan QR kodu bu görevin tesisine ait değil.' using errcode = 'PT422';
        end if;
    end if;

    -- Her iki yöntemde de tesis koordinatı tanımlıysa 50 m kuralı uygulanır.
    if v_konum_gerekli then
        if p_enlem is null or p_boylam is null then
            raise exception 'Görevi başlatmak için konum bilgisi gerekli. Lütfen konumu açın.' using errcode = 'PT422';
        end if;
        v_mesafe := app.mesafe_metre(p_enlem, p_boylam, v_gorev.site_enlem, v_gorev.site_boylam);
        if v_mesafe > app.konum_esigi_metre() then
            raise exception 'Tesise yeterince yakın değilsiniz (ölçülen: % m).', round(v_mesafe) using errcode = 'PT422';
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
-- 4a) save_task — idempotent + konum_dogrulandi bayrağı.
--     Koordinatsız tesiste artık sessizce geçmek yerine bayrak false yazılır
--     (yönetici panelde/raporda görebilir).
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
    v_hedef record;
    v_mesafe double precision;
    v_dogrulandi boolean;
    v_n     integer;
begin
    if p_is_emri_id is null or p_enlem is null or p_boylam is null then
        raise exception 'Eksik bilgi gönderildi. (is_emri_id, tamamlanma_enlem, tamamlanma_boylam gerekli)' using errcode = 'PT400';
    end if;

    select ie.durum, s.enlem as site_enlem, s.boylam as site_boylam
      into v_hedef
      from is_emirleri ie
      left join siteler s on ie.site_id = s.id
     where ie.id = p_is_emri_id and ie.firma_id = v_firma and ie.personel_id = v_pid
     limit 1;

    if not found then
        raise exception 'Görev güncellenemedi. Görev bulunamadı veya size ait değil.' using errcode = 'PT400';
    end if;

    -- Offline kuyruk tekrarı: aynı personel görevi zaten tamamladıysa hata
    -- değil başarı dön (ilk istek gitmiş, yanıtı kaybolmuş olabilir).
    if v_hedef.durum = 'tamamlandi' then
        return jsonb_build_object('message', 'Görev zaten tamamlanmış.', 'zaten', true);
    end if;
    if v_hedef.durum = 'iptal' then
        raise exception 'Görev iptal edilmiş; tamamlanamaz.' using errcode = 'PT409';
    end if;

    if v_hedef.site_enlem is not null and v_hedef.site_boylam is not null then
        v_mesafe := app.mesafe_metre(p_enlem, p_boylam, v_hedef.site_enlem, v_hedef.site_boylam);
        if v_mesafe > app.konum_esigi_metre() then
            raise exception 'Görev tesiste kapatılmalı; tesise yeterince yakın değilsiniz (ölçülen: % m).', round(v_mesafe) using errcode = 'PT422';
        end if;
        v_dogrulandi := true;
    else
        v_dogrulandi := false;  -- tesise koordinat tanımlanmamış; doğrulanamadı
    end if;

    update is_emirleri
       set durum                = 'tamamlandi',
           tamamlanma_tarihi    = now(),
           tamamlanma_enlem     = p_enlem,
           tamamlanma_boylam    = p_boylam,
           kapanis_fotograf_url = p_kapanis_fotograf_path,
           konum_dogrulandi     = v_dogrulandi
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
-- 4b) Idempotency kolonları + report_fault / add_expense yeniden imzası
-- ---------------------------------------------------------------------
alter table arizalar          add column if not exists istek_id uuid;
alter table malzeme_talepleri add column if not exists istek_id uuid;

create unique index if not exists arizalar_istek_uq
    on arizalar (firma_id, istek_id) where istek_id is not null;
create unique index if not exists masraf_istek_uq
    on malzeme_talepleri (firma_id, istek_id) where istek_id is not null;

-- İmza değiştiği için önce eski fonksiyonlar düşürülür (overload kalmasın).
drop function if exists public.report_fault(bigint, text, text, text);
drop function if exists public.add_expense(bigint, bigint, text, numeric, text);

create function public.report_fault(
    p_site_id       bigint,
    p_baslik        text,
    p_aciklama      text default null,
    p_fotograf_path text default null,
    p_istek_id      uuid default null
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

    -- Offline kuyruk tekrarı: aynı istek daha önce işlendiyse başarı dön.
    if p_istek_id is not null then
        select id into v_id from arizalar where firma_id = v_firma and istek_id = p_istek_id;
        if found then
            return jsonb_build_object('message', 'Arıza bildirimi alındı.', 'id', v_id, 'zaten', true);
        end if;
    end if;

    if not exists (select 1 from siteler where id = p_site_id and firma_id = v_firma) then
        raise exception 'Geçersiz tesis.' using errcode = 'PT422';
    end if;

    insert into arizalar (firma_id, site_id, bildiren_personel_id, baslik, aciklama, fotograf_url, durum, istek_id)
    values (v_firma, p_site_id, v_pid, btrim(p_baslik), nullif(btrim(coalesce(p_aciklama,'')),''), p_fotograf_path, 'acik', p_istek_id)
    returning id into v_id;

    return jsonb_build_object('message', 'Arıza bildirimi alındı.', 'id', v_id);
exception when unique_violation then
    -- Yarış: aynı istek eşzamanlı iki kez geldi; ilki kazandı.
    return jsonb_build_object('message', 'Arıza bildirimi alındı.', 'zaten', true);
end $$;

create function public.add_expense(
    p_is_emri_id        bigint default null,
    p_ariza_id          bigint default null,
    p_kalem_adi         text default null,
    p_tutar             numeric default null,
    p_fis_fotograf_path text default null,
    p_istek_id          uuid default null
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

    -- Offline kuyruk tekrarı: aynı istek daha önce işlendiyse başarı dön.
    if p_istek_id is not null and exists (
        select 1 from malzeme_talepleri where firma_id = v_firma and istek_id = p_istek_id
    ) then
        return jsonb_build_object('message', 'Masraf formu başarıyla gönderildi ve onaya sunuldu.', 'zaten', true);
    end if;

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
        (firma_id, personel_id, is_emri_id, ariza_id, kalem_adi, tutar, fis_fatura_fotograf, durum, istek_id)
    values
        (v_firma, v_pid, p_is_emri_id, p_ariza_id, btrim(p_kalem_adi), p_tutar, p_fis_fotograf_path, 'bekliyor', p_istek_id);

    return jsonb_build_object('message', 'Masraf formu başarıyla gönderildi ve onaya sunuldu.');
exception when unique_violation then
    return jsonb_build_object('message', 'Masraf formu başarıyla gönderildi ve onaya sunuldu.', 'zaten', true);
end $$;

-- ---------------------------------------------------------------------
-- 5) set_fcm_token — cihaz temizliği yalnız aynı firmada
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
    update personeller set fcm_token = null
     where fcm_token = p_fcm_token and id <> v_pid and firma_id = v_firma;
    update personeller set fcm_token = p_fcm_token where id = v_pid and firma_id = v_firma;
    return jsonb_build_object('message', 'FCM token kaydedildi.');
end $$;

-- ---------------------------------------------------------------------
-- 6) qr_kod gizliliği
-- ---------------------------------------------------------------------
-- v_is_emri qr_kod'suz yeniden tanımlanır (kolon çıkarma "or replace" ile
-- yapılamaz; önce düşür).
drop view if exists public.v_is_emri;
create view public.v_is_emri
    with (security_invoker = true) as
select ie.id, ie.firma_id, ie.site_id, ie.personel_id, ie.sablon_id,
       ie.baslik, ie.aciklama, ie.durum,
       ie.planlanan_baslangic_tarihi, ie.termin_tarihi,
       ie.tamamlanma_tarihi, ie.tamamlanma_enlem, ie.tamamlanma_boylam,
       ie.kapanis_fotograf_url, ie.konum_dogrulandi, ie.olusturma_tarihi,
       s.ad as site_adi, p.ad_soyad as personel_adi
  from is_emirleri ie
  left join siteler s     on ie.site_id = s.id
  left join personeller p on ie.personel_id = p.id;
grant select on public.v_is_emri to authenticated;

revoke select on siteler from authenticated;
grant select (id, firma_id, ad, adres, enlem, boylam, olusturma_tarihi, aktif)
    on siteler to authenticated;

revoke select on is_emirleri from authenticated;
grant select (id, firma_id, site_id, personel_id, sablon_id, baslik, aciklama,
              durum, planlanan_baslangic_tarihi, termin_tarihi,
              tamamlanma_tarihi, tamamlanma_enlem, tamamlanma_boylam,
              kapanis_fotograf_url, konum_dogrulandi, olusturma_tarihi)
    on is_emirleri to authenticated;

-- Yönetici paneli QR görüntüleme/baskı için tek uç.
create or replace function public.admin_qr_goster(p_tip text, p_id bigint)
returns jsonb
    language plpgsql security definer set search_path = public, app
    as $$
declare
    v_firma bigint := app.require_yonetici();
    v_qr text;
begin
    if p_tip = 'site' then
        select qr_kod into v_qr from siteler where id = p_id and firma_id = v_firma;
    elsif p_tip = 'is_emri' then
        select qr_kod into v_qr from is_emirleri where id = p_id and firma_id = v_firma;
    else
        raise exception 'Geçersiz tip.' using errcode = 'PT400';
    end if;
    if not found then
        raise exception 'Kayıt bulunamadı.' using errcode = 'PT404';
    end if;
    return jsonb_build_object('qr_kod', v_qr);
end $$;

-- ---------------------------------------------------------------------
-- Yürütme izinleri
-- ---------------------------------------------------------------------
revoke all on function
    public.report_fault(bigint, text, text, text, uuid),
    public.add_expense(bigint, bigint, text, numeric, text, uuid),
    public.admin_qr_goster(text, bigint)
    from public, anon;

grant execute on function
    public.report_fault(bigint, text, text, text, uuid),
    public.add_expense(bigint, bigint, text, numeric, text, uuid),
    public.admin_qr_goster(text, bigint)
    to authenticated;
