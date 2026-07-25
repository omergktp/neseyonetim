-- =====================================================================
-- 0006_admin_rpc.sql  —  Yönetici (admin) yazma uçlarının RPC karşılıkları
--
-- Hepsi SECURITY DEFINER; app.require_yonetici() ile rol/tenant guard.
-- Şifreler pgcrypto bcrypt ($2a$) — login Edge Function ile uyumlu.
-- FCM: app.notify_personel (best-effort). Audit: app.log_action.
-- =====================================================================

-- Ortak atama doğrulaması (firma aidiyeti; rol/aktif kontrolü YOK).
create or replace function app.site_personel_kontrol(
    p_firma bigint, p_site_id bigint, p_personel_id bigint
) returns void
    language plpgsql stable
    set search_path = app, public
    as $$
begin
    if not exists (select 1 from siteler where id = p_site_id and firma_id = p_firma) then
        raise exception 'Seçilen site firmanıza ait değil.' using errcode = 'PT422';
    end if;
    if not exists (select 1 from personeller where id = p_personel_id and firma_id = p_firma) then
        raise exception 'Seçilen personel firmanıza ait değil.' using errcode = 'PT422';
    end if;
end $$;

-- =====================================================================
-- PERSONELLER
-- =====================================================================
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

create or replace function public.admin_personel_aktif_degistir(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici();
begin
    if not exists (select 1 from personeller where id=p_id and firma_id=v_firma) then
        raise exception 'Personel bulunamadı.' using errcode='PT404';
    end if;
    if p_id = app.current_personel_id() then
        raise exception 'Kendi hesabınızı pasifleştiremezsiniz.' using errcode='PT409';
    end if;
    update personeller set aktif = not aktif where id=p_id and firma_id=v_firma;
    perform app.log_action('personel_aktif_degistir','personel',p_id);
    return jsonb_build_object('message','Personel durumu güncellendi.');
end $$;

create or replace function public.admin_personel_sil(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici();
begin
    if not exists (select 1 from personeller where id=p_id and firma_id=v_firma) then
        raise exception 'Personel bulunamadı.' using errcode='PT404';
    end if;
    if p_id = app.current_personel_id() then
        raise exception 'Kendi hesabınızı silemezsiniz.' using errcode='PT409';
    end if;
    if exists (select 1 from is_emirleri where personel_id=p_id)
       or exists (select 1 from arizalar where bildiren_personel_id=p_id or teknik_personel_id=p_id)
       or exists (select 1 from malzeme_talepleri where personel_id=p_id) then
        raise exception 'Bu personele bağlı iş emri/arıza/masraf kayıtları var. Silmek yerine ''Pasif'' yapabilirsiniz.' using errcode='PT409';
    end if;
    delete from personeller where id=p_id and firma_id=v_firma;
    perform app.log_action('personel_sil','personel',p_id);
    return jsonb_build_object('message','Personel silindi.');
end $$;

-- =====================================================================
-- SİTELER
-- =====================================================================
create or replace function public.admin_site_ekle(
    p_ad text, p_adres text default null, p_enlem numeric default null, p_boylam numeric default null
) returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_id bigint; v_qr text;
begin
    if coalesce(btrim(p_ad),'')='' then
        raise exception 'Site adı zorunludur.' using errcode='PT400';
    end if;
    v_qr := app.yeni_site_qr();
    insert into siteler (firma_id, ad, adres, enlem, boylam, qr_kod)
    values (v_firma, btrim(p_ad), nullif(btrim(coalesce(p_adres,'')),''), p_enlem, p_boylam, v_qr)
    returning id into v_id;
    perform app.log_action('site_ekle','site',v_id,btrim(p_ad));
    return jsonb_build_object('message','Tesis eklendi.','id',v_id,'qr_kod',v_qr);
end $$;

create or replace function public.admin_site_guncelle(
    p_id bigint, p_ad text, p_adres text default null, p_enlem numeric default null, p_boylam numeric default null
) returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici();
begin
    if not exists (select 1 from siteler where id=p_id and firma_id=v_firma) then
        raise exception 'Tesis bulunamadı.' using errcode='PT404';
    end if;
    if coalesce(btrim(p_ad),'')='' then
        raise exception 'Site adı zorunludur.' using errcode='PT400';
    end if;
    update siteler set ad=btrim(p_ad), adres=nullif(btrim(coalesce(p_adres,'')),''), enlem=p_enlem, boylam=p_boylam
     where id=p_id and firma_id=v_firma;
    perform app.log_action('site_guncelle','site',p_id);
    return jsonb_build_object('message','Tesis güncellendi.');
end $$;

create or replace function public.admin_site_qr_yenile(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_qr text;
begin
    if not exists (select 1 from siteler where id=p_id and firma_id=v_firma) then
        raise exception 'Tesis bulunamadı.' using errcode='PT404';
    end if;
    v_qr := app.yeni_site_qr();
    update siteler set qr_kod=v_qr where id=p_id and firma_id=v_firma;
    perform app.log_action('site_qr_yenile','site',p_id);
    return jsonb_build_object('message','QR kodu yenilendi.','qr_kod',v_qr);
end $$;

create or replace function public.admin_site_sil(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici();
begin
    if not exists (select 1 from siteler where id=p_id and firma_id=v_firma) then
        raise exception 'Tesis bulunamadı.' using errcode='PT404';
    end if;
    if exists (select 1 from is_emirleri where site_id=p_id)
       or exists (select 1 from arizalar where site_id=p_id)
       or exists (select 1 from periyodik_sablonlar where site_id=p_id) then
        raise exception 'Bu tesise bağlı iş emri, arıza veya periyodik şablon kayıtları var. Önce onları silin.' using errcode='PT409';
    end if;
    delete from siteler where id=p_id and firma_id=v_firma;
    perform app.log_action('site_sil','site',p_id);
    return jsonb_build_object('message','Tesis silindi.');
end $$;

-- =====================================================================
-- İŞ EMİRLERİ
-- =====================================================================
create or replace function public.admin_is_emri_ekle(
    p_site_id bigint, p_personel_id bigint, p_baslik text,
    p_aciklama text default null, p_qr_kod text default null,
    p_planlanan timestamptz default null, p_termin date default null
) returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_id bigint; v_token text;
begin
    if p_site_id is null or p_personel_id is null or coalesce(btrim(p_baslik),'')='' then
        raise exception 'Eksik bilgi. (site_id, personel_id, baslik gerekli)' using errcode='PT400';
    end if;
    perform app.site_personel_kontrol(v_firma, p_site_id, p_personel_id);
    insert into is_emirleri (firma_id, site_id, personel_id, baslik, aciklama, qr_kod, durum, planlanan_baslangic_tarihi, termin_tarihi)
    values (v_firma, p_site_id, p_personel_id, btrim(p_baslik),
            nullif(btrim(coalesce(p_aciklama,'')),''), nullif(btrim(coalesce(p_qr_kod,'')),''),
            'bekliyor', p_planlanan, p_termin)
    returning id into v_id;

    perform app.notify_personel(p_personel_id, 'Yeni Görev Atandı', btrim(p_baslik),
                                jsonb_build_object('tip','yeni_gorev','is_emri_id',v_id));
    perform app.log_action('is_emri_ekle','is_emri',v_id,btrim(p_baslik));
    return jsonb_build_object('message','İş emri oluşturuldu.','id',v_id);
end $$;

create or replace function public.admin_is_emri_guncelle(
    p_id bigint, p_site_id bigint, p_personel_id bigint, p_baslik text,
    p_aciklama text default null, p_qr_kod text default null,
    p_planlanan timestamptz default null, p_termin date default null
) returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici();
begin
    if not exists (select 1 from is_emirleri where id=p_id and firma_id=v_firma) then
        raise exception 'İş emri bulunamadı.' using errcode='PT404';
    end if;
    if p_site_id is null or p_personel_id is null or coalesce(btrim(p_baslik),'')='' then
        raise exception 'Eksik bilgi. (site_id, personel_id, baslik gerekli)' using errcode='PT400';
    end if;
    perform app.site_personel_kontrol(v_firma, p_site_id, p_personel_id);
    update is_emirleri
       set site_id=p_site_id, personel_id=p_personel_id, baslik=btrim(p_baslik),
           aciklama=nullif(btrim(coalesce(p_aciklama,'')),''), qr_kod=nullif(btrim(coalesce(p_qr_kod,'')),''),
           planlanan_baslangic_tarihi=p_planlanan, termin_tarihi=p_termin
     where id=p_id and firma_id=v_firma;
    perform app.log_action('is_emri_guncelle','is_emri',p_id);
    return jsonb_build_object('message','İş emri güncellendi.');
end $$;

create or replace function public.admin_is_emri_sil(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_n int;
begin
    delete from is_emirleri where id=p_id and firma_id=v_firma;  -- alt görev + masraf FK CASCADE
    get diagnostics v_n = row_count;
    if v_n = 0 then
        raise exception 'İş emri bulunamadı.' using errcode='PT404';
    end if;
    perform app.log_action('is_emri_sil','is_emri',p_id);
    return jsonb_build_object('message','İş emri silindi.');
end $$;

-- =====================================================================
-- ARIZALAR
-- =====================================================================
create or replace function public.admin_ariza_ekle(
    p_site_id bigint, p_baslik text, p_aciklama text default null,
    p_teknik_personel_id bigint default null, p_oncelik text default 'normal'
) returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_id bigint;
        v_teknik bigint := null; v_oncelik text;
begin
    if p_site_id is null or coalesce(btrim(p_baslik),'')='' then
        raise exception 'Eksik bilgi. (site_id, baslik gerekli)' using errcode='PT400';
    end if;
    v_oncelik := case when p_oncelik in ('dusuk','normal','yuksek') then p_oncelik else 'normal' end;
    if not exists (select 1 from siteler where id=p_site_id and firma_id=v_firma) then
        raise exception 'Seçilen tesis firmanıza ait değil.' using errcode='PT422';
    end if;
    if p_teknik_personel_id is not null then
        if not exists (select 1 from personeller where id=p_teknik_personel_id and firma_id=v_firma and rol='teknik') then
            raise exception 'Seçilen kişi firmanıza ait bir teknik personel değil.' using errcode='PT422';
        end if;
        v_teknik := p_teknik_personel_id;
    end if;
    insert into arizalar (firma_id, site_id, bildiren_personel_id, teknik_personel_id, baslik, aciklama, durum, oncelik)
    values (v_firma, p_site_id, app.current_personel_id(), v_teknik, btrim(p_baslik),
            nullif(btrim(coalesce(p_aciklama,'')),''), 'acik', v_oncelik::ariza_oncelik)
    returning id into v_id;

    if v_teknik is not null then
        perform app.notify_personel(v_teknik, 'Yeni Arıza Atandı', btrim(p_baslik),
                                    jsonb_build_object('tip','ariza','ariza_id',v_id));
    end if;
    perform app.log_action('ariza_ekle','ariza',v_id);
    return jsonb_build_object('message','Arıza oluşturuldu.','id',v_id);
end $$;

-- Kısmi güncelleme. Açık-null semantiği gereken iki alanda "_set" bayrağı:
--   p_aciklama_set=true -> aciklama gönderildi (null olsa da yaz)
--   p_teknik_set=true   -> teknik atama gönderildi (null ise atamayı kaldır)
create or replace function public.admin_ariza_guncelle(
    p_id bigint,
    p_baslik text default null,
    p_aciklama text default null, p_aciklama_set boolean default false,
    p_site_id bigint default null,
    p_oncelik text default null,
    p_durum text default null,
    p_teknik_personel_id bigint default null, p_teknik_set boolean default false
) returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici();
        v_baslik_eski text; v_atanan bigint := null; v_detay text := '';
begin
    select baslik into v_baslik_eski from arizalar where id=p_id and firma_id=v_firma limit 1;
    if not found then
        raise exception 'Arıza bulunamadı.' using errcode='PT404';
    end if;

    if p_site_id is not null and not exists (select 1 from siteler where id=p_site_id and firma_id=v_firma) then
        raise exception 'Seçilen tesis firmanıza ait değil.' using errcode='PT422';
    end if;
    if p_durum is not null and p_durum not in ('acik','bekliyor','cozuldu','iptal','dis_destek') then
        raise exception 'Geçersiz durum.' using errcode='PT400';
    end if;
    if p_teknik_set and p_teknik_personel_id is not null then
        if not exists (select 1 from personeller where id=p_teknik_personel_id and firma_id=v_firma and rol='teknik') then
            raise exception 'Seçilen kişi firmanıza ait bir teknik personel değil.' using errcode='PT422';
        end if;
        v_atanan := p_teknik_personel_id;
    end if;

    update arizalar set
        baslik   = case when coalesce(btrim(p_baslik),'')<>'' then btrim(p_baslik) else baslik end,
        aciklama = case when p_aciklama_set then nullif(btrim(coalesce(p_aciklama,'')),'') else aciklama end,
        site_id  = coalesce(p_site_id, site_id),
        oncelik  = case when p_oncelik in ('dusuk','normal','yuksek') then p_oncelik::ariza_oncelik else oncelik end,
        durum    = case when p_durum is not null then p_durum::ariza_durum else durum end,
        cozum_tarihi = case when p_durum = 'cozuldu' then now() else cozum_tarihi end,
        teknik_personel_id = case when p_teknik_set then p_teknik_personel_id else teknik_personel_id end
     where id=p_id and firma_id=v_firma;

    if v_atanan is not null then
        perform app.notify_personel(v_atanan, 'Yeni Arıza Atandı', v_baslik_eski,
                                    jsonb_build_object('tip','ariza','ariza_id',p_id));
    end if;
    if p_durum is not null then v_detay := 'durum: '||p_durum; end if;
    if v_atanan is not null then v_detay := v_detay||' teknik atandı: '||v_atanan; end if;
    perform app.log_action('ariza_guncelle','ariza',p_id, nullif(v_detay,''));
    return jsonb_build_object('message','Arıza güncellendi.');
end $$;

create or replace function public.admin_ariza_sil(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_baslik text; v_n int;
begin
    select baslik into v_baslik from arizalar where id=p_id and firma_id=v_firma limit 1;
    if not found then
        raise exception 'Arıza bulunamadı.' using errcode='PT404';
    end if;
    delete from arizalar where id=p_id and firma_id=v_firma;  -- masraf FK CASCADE
    perform app.log_action('ariza_sil','ariza',p_id,v_baslik);
    return jsonb_build_object('message','Arıza silindi.');
end $$;

-- =====================================================================
-- MASRAFLAR (malzeme_talepleri) — onay/ret/sil
-- =====================================================================
create or replace function public.admin_masraf_karar(p_id bigint, p_karar text)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_durum text; v_n int;
begin
    if p_karar not in ('onayla','reddet') then
        raise exception 'Geçersiz işlem. (onayla veya reddet)' using errcode='PT400';
    end if;
    v_durum := case p_karar when 'onayla' then 'onaylandi' else 'reddedildi' end;
    update malzeme_talepleri set durum = v_durum::masraf_durum where id=p_id and firma_id=v_firma;
    get diagnostics v_n = row_count;
    if v_n = 0 then
        raise exception 'Masraf bulunamadı veya zaten güncellenmiş.' using errcode='PT404';
    end if;
    perform app.log_action('masraf_'||p_karar,'masraf',p_id,'yeni durum: '||v_durum);
    return jsonb_build_object('message','Masraf güncellendi.');
end $$;

create or replace function public.admin_masraf_sil(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_n int;
begin
    delete from malzeme_talepleri where id=p_id and firma_id=v_firma;
    get diagnostics v_n = row_count;
    if v_n = 0 then
        raise exception 'Masraf bulunamadı.' using errcode='PT404';
    end if;
    perform app.log_action('masraf_sil','masraf',p_id);
    return jsonb_build_object('message','Masraf silindi.');
end $$;

-- =====================================================================
-- PERİYODİK ŞABLONLAR
-- =====================================================================
-- Ortak girdi doğrulaması -> normalize edilmiş tekrar_gunu döndürür.
create or replace function app.sablon_dogrula(
    p_firma bigint, p_site_id bigint, p_personel_id bigint, p_baslik text,
    p_tekrar_tipi text, p_tekrar_gunu int
) returns int
    language plpgsql stable set search_path = app, public
    as $$
declare v_gun int;
begin
    if p_site_id is null or p_personel_id is null or coalesce(btrim(p_baslik),'')='' or coalesce(p_tekrar_tipi,'')='' then
        raise exception 'Eksik bilgi. (site_id, personel_id, baslik, tekrar_tipi gerekli)' using errcode='PT400';
    end if;
    if p_tekrar_tipi not in ('gunluk','haftalik','aylik') then
        raise exception 'Geçersiz tekrar tipi.' using errcode='PT422';
    end if;
    if p_tekrar_tipi = 'gunluk' then
        v_gun := null;
    elsif p_tekrar_tipi = 'haftalik' then
        v_gun := coalesce(p_tekrar_gunu, 0);
        if v_gun < 1 or v_gun > 7 then
            raise exception 'Haftalık tekrar için gün 1-7 (Pazartesi-Pazar) olmalı.' using errcode='PT422';
        end if;
    else -- aylik
        v_gun := coalesce(p_tekrar_gunu, 0);
        if v_gun < 1 or v_gun > 31 then
            raise exception 'Aylık tekrar için ayın günü 1-31 olmalı.' using errcode='PT422';
        end if;
    end if;
    -- firma aidiyeti (rol/aktif kontrolü yok)
    if not exists (select 1 from siteler where id=p_site_id and firma_id=p_firma) then
        raise exception 'Seçilen site firmanıza ait değil.' using errcode='PT422';
    end if;
    if not exists (select 1 from personeller where id=p_personel_id and firma_id=p_firma) then
        raise exception 'Seçilen personel firmanıza ait değil.' using errcode='PT422';
    end if;
    return v_gun;
end $$;

create or replace function public.admin_sablon_ekle(
    p_site_id bigint, p_personel_id bigint, p_baslik text, p_tekrar_tipi text,
    p_aciklama text default null, p_alt_gorevler text default null, p_tekrar_gunu int default null
) returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_gun int; v_id bigint;
begin
    v_gun := app.sablon_dogrula(v_firma, p_site_id, p_personel_id, p_baslik, p_tekrar_tipi, p_tekrar_gunu);
    insert into periyodik_sablonlar (firma_id, site_id, personel_id, baslik, aciklama, alt_gorevler, tekrar_tipi, tekrar_gunu, aktif)
    values (v_firma, p_site_id, p_personel_id, btrim(p_baslik),
            nullif(btrim(coalesce(p_aciklama,'')),''), nullif(btrim(coalesce(p_alt_gorevler,'')),''),
            p_tekrar_tipi::tekrar_tipi, v_gun, true)
    returning id into v_id;
    perform app.log_action('sablon_ekle','sablon',v_id,btrim(p_baslik));
    return jsonb_build_object('message','Şablon eklendi.','id',v_id);
end $$;

create or replace function public.admin_sablon_guncelle(
    p_id bigint, p_site_id bigint, p_personel_id bigint, p_baslik text, p_tekrar_tipi text,
    p_aciklama text default null, p_alt_gorevler text default null, p_tekrar_gunu int default null
) returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_gun int;
begin
    if not exists (select 1 from periyodik_sablonlar where id=p_id and firma_id=v_firma) then
        raise exception 'Şablon bulunamadı.' using errcode='PT404';
    end if;
    v_gun := app.sablon_dogrula(v_firma, p_site_id, p_personel_id, p_baslik, p_tekrar_tipi, p_tekrar_gunu);
    update periyodik_sablonlar
       set site_id=p_site_id, personel_id=p_personel_id, baslik=btrim(p_baslik),
           aciklama=nullif(btrim(coalesce(p_aciklama,'')),''), alt_gorevler=nullif(btrim(coalesce(p_alt_gorevler,'')),''),
           tekrar_tipi=p_tekrar_tipi::tekrar_tipi, tekrar_gunu=v_gun
     where id=p_id and firma_id=v_firma;   -- son_uretim_tarihi'ne dokunulmaz
    perform app.log_action('sablon_guncelle','sablon',p_id);
    return jsonb_build_object('message','Şablon güncellendi.');
end $$;

create or replace function public.admin_sablon_aktif_degistir(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_n int;
begin
    update periyodik_sablonlar set aktif = not aktif where id=p_id and firma_id=v_firma;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Şablon bulunamadı.' using errcode='PT404'; end if;
    perform app.log_action('sablon_aktif_degistir','sablon',p_id);
    return jsonb_build_object('message','Şablon durumu güncellendi.');
end $$;

create or replace function public.admin_sablon_sil(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_silinen int; v_n int;
begin
    if not exists (select 1 from periyodik_sablonlar where id=p_id and firma_id=v_firma) then
        raise exception 'Şablon bulunamadı.' using errcode='PT404';
    end if;
    delete from is_emirleri where sablon_id=p_id and firma_id=v_firma and durum='bekliyor';
    get diagnostics v_silinen = row_count;
    delete from periyodik_sablonlar where id=p_id and firma_id=v_firma;
    perform app.log_action('sablon_sil','sablon',p_id,
                           case when v_silinen>0 then 'bekleyen '||v_silinen||' görev de silindi' else null end);
    return jsonb_build_object('message', case when v_silinen>0
                              then 'Şablon ve bekleyen '||v_silinen||' görev silindi.'
                              else 'Şablon silindi.' end);
end $$;

-- Manuel üretim (bugüne denk gelme kuralına BAKMAZ; yalnız mükerrer engeli).
create or replace function public.admin_sablon_uret(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public, app
    as $$
declare v_firma bigint := app.require_yonetici(); v_sonuc bigint;
begin
    if not exists (select 1 from periyodik_sablonlar where id=p_id and firma_id=v_firma) then
        raise exception 'Şablon bulunamadı.' using errcode='PT404';
    end if;
    v_sonuc := app.generate_periodic(p_id, current_date);  -- 0008'de tanımlı
    if v_sonuc is null then
        raise exception 'İş emri üretilemedi: atanan site veya personel pasif/silinmiş.' using errcode='PT422';
    elsif v_sonuc = 0 then
        raise exception 'Bu şablondan bugün zaten iş emri üretilmiş. Aynı gün tekrar üretilmez.' using errcode='PT409';
    end if;
    perform app.log_action('sablondan_uret','sablon',p_id,'is_emri_id: '||v_sonuc);
    return jsonb_build_object('message','İş emri üretildi.','is_emri_id',v_sonuc);
end $$;

-- ---------------------------------------------------------------------
-- Yürütme izinleri (yalnız authenticated; rol guard içeride).
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
    for r in
        select p.oid::regprocedure::text as sig
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname like 'admin\_%'
    loop
        execute format('revoke all on function %s from public, anon;', r.sig);
        execute format('grant execute on function %s to authenticated;', r.sig);
    end loop;
end $$;
