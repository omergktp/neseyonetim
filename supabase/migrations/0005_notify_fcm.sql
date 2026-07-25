-- =====================================================================
-- 0005_notify_fcm.sql  —  Bildirim (FCM) + audit + QR altyapısı
--
-- FCM push: DB (RPC/cron) -> pg_net ile "notify" Edge Function -> FCM v1.
-- Edge Function OAuth2 + FCM HTTP v1 detayını üstlenir (bkz.
-- functions/notify/index.ts). DB yalnız {personel_id, baslik, govde, data}
-- gönderir; hata asıl işlemi ASLA bozmaz (yutulur).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;  -- gen_random_bytes
create extension if not exists pg_net;                            -- net.http_post

-- notify Edge Function URL'i ve paylaşılan gizli anahtarı burada tutulur.
-- (app şeması authenticated/anon'a AÇIK DEĞİL — yalnız SECURITY DEFINER
--  fonksiyonlar ve service_role okur.) Değerler kurulumda doldurulur:
--   insert into app.config values
--     ('notify_url','https://<ref>.supabase.co/functions/v1/notify'),
--     ('notify_secret','<uzun-rastgele-deger>');
create table if not exists app.config (
    key   text primary key,
    value text not null
);

-- ---------------------------------------------------------------------
-- app.notify_personel — bir personele push bildirimi (best-effort)
-- ---------------------------------------------------------------------
create or replace function app.notify_personel(
    p_personel_id bigint,
    p_baslik      text,
    p_govde       text,
    p_data        jsonb default '{}'::jsonb
) returns void
    language plpgsql security definer
    set search_path = app, public
    as $$
declare
    v_url    text;
    v_secret text;
begin
    if p_personel_id is null then return; end if;
    select value into v_url    from app.config where key = 'notify_url';
    select value into v_secret from app.config where key = 'notify_secret';
    if v_url is null then return; end if;   -- yapılandırılmamışsa sessizce çık

    perform net.http_post(
        url     := v_url,
        headers := jsonb_build_object(
                       'Content-Type', 'application/json',
                       'x-notify-secret', coalesce(v_secret, '')
                   ),
        body    := jsonb_build_object(
                       'personel_id', p_personel_id,
                       'baslik',      p_baslik,
                       'govde',       p_govde,
                       'data',        coalesce(p_data, '{}'::jsonb)
                   )
    );
exception when others then
    null;  -- bildirim hatası işlemi bozmaz
end $$;

-- ---------------------------------------------------------------------
-- app.log_action — audit_log yardımcısı (hata yutar; işlemi bozmaz)
-- ---------------------------------------------------------------------
create or replace function app.log_action(
    p_eylem     text,
    p_hedef_tip text default null,
    p_hedef_id  bigint default null,
    p_detay     text default null
) returns void
    language plpgsql security definer
    set search_path = app, public
    as $$
begin
    insert into audit_log (firma_id, personel_id, eylem, hedef_tip, hedef_id, detay, ip)
    values (app.current_firma_id(), app.current_personel_id(), p_eylem, p_hedef_tip, p_hedef_id, p_detay,
            inet_client_addr()::text);
exception when others then
    null;
end $$;

-- ---------------------------------------------------------------------
-- app.yeni_site_qr — global benzersiz "SAHA-XXXXXXXXXX" QR üretici
-- ---------------------------------------------------------------------
create or replace function app.yeni_site_qr() returns text
    language plpgsql
    set search_path = app, public, extensions
    as $$
declare k text;
begin
    loop
        k := 'SAHA-' || upper(encode(extensions.gen_random_bytes(5), 'hex'));
        exit when not exists (select 1 from siteler where qr_kod = k);
    end loop;
    return k;
end $$;

-- ---------------------------------------------------------------------
-- app.require_yonetici — yönetici değilse 403; firma yoksa 401
-- ---------------------------------------------------------------------
create or replace function app.require_yonetici() returns bigint
    language plpgsql stable
    set search_path = app, public
    as $$
declare fid bigint := app.current_firma_id();
begin
    if fid is null then
        raise exception 'Oturum bulunamadı.' using errcode = 'PT401';
    end if;
    if not app.is_yonetici() then
        raise exception 'Bu işlem için yönetici yetkisi gereklidir.' using errcode = 'PT403';
    end if;
    return fid;
end $$;
