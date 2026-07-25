-- 0009_auth_bridge.sql
--
-- GoTrue köprüsü: proje ES256 asimetrik imzalama kullandığı için özel HS256
-- JWT üretimi geçersiz. login Edge Function artık personeli GoTrue'da bir
-- gölge kullanıcıya eşler (e-posta: p<id>@personel.glowsaha.app) ve gerçek
-- Supabase oturumu döndürür. Özel claim'ler (firma_id/personel_id/rol) GoTrue
-- token'ında app_metadata altında taşınır; claim yardımcıları buna göre
-- güncellenir. Eski düz claim'li token'larla geriye dönük uyumludur.

-- Personel <-> GoTrue kullanıcı eşlemesi (ilk girişte doldurulur).
alter table public.personeller
    add column if not exists auth_user_id uuid unique;

-- Claim yardımcıları: önce app_metadata, yoksa düz claim.
create or replace function app.current_firma_id() returns bigint
    language sql stable
    as $$ select nullif(coalesce(auth.jwt() -> 'app_metadata' ->> 'firma_id',
                                 auth.jwt() ->> 'firma_id'), '')::bigint $$;

create or replace function app.current_personel_id() returns bigint
    language sql stable
    as $$ select nullif(coalesce(auth.jwt() -> 'app_metadata' ->> 'personel_id',
                                 auth.jwt() ->> 'personel_id'), '')::bigint $$;

create or replace function app.current_rol() returns text
    language sql stable
    as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'rol',
                          auth.jwt() ->> 'rol') $$;

create or replace function app.is_yonetici() returns boolean
    language sql stable
    as $$ select coalesce(auth.jwt() -> 'app_metadata' ->> 'rol',
                          auth.jwt() ->> 'rol', '') = 'yonetici' $$;
