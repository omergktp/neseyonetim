-- =====================================================================
-- 0007_views_reports.sql  —  Okuma görünümleri + panel/rapor RPC'leri
--
-- Görünümler security_invoker=true ile tanımlı: alttaki tabloların RLS'i
-- çağıran kullanıcıya göre uygulanır (yönetici tüm firma, personel yalnız
-- kendi/atanmış). Böylece GET uçları doğrudan PostgREST ile karşılanır.
-- Panel/rapor toplulaştırmaları SECURITY DEFINER RPC (yönetici guard'lı).
-- =====================================================================

-- İş emirleri + tesis/personel adı (mobil get_tasks & admin liste)
create or replace view public.v_is_emri
    with (security_invoker = true) as
select ie.*, s.ad as site_adi, p.ad_soyad as personel_adi
  from is_emirleri ie
  left join siteler s     on ie.site_id = s.id
  left join personeller p on ie.personel_id = p.id;

-- Arızalar + tesis/bildiren/teknik adı (mobil get_faults & admin liste)
create or replace view public.v_ariza
    with (security_invoker = true) as
select a.*, s.ad as site_adi,
       pb.ad_soyad as bildiren_adi,
       pt.ad_soyad as teknik_adi
  from arizalar a
  left join siteler s      on a.site_id = s.id
  left join personeller pb on a.bildiren_personel_id = pb.id
  left join personeller pt on a.teknik_personel_id = pt.id;

-- Masraflar + personel/iş emri/arıza/tesis (admin masraflar & rapor)
create or replace view public.v_masraf
    with (security_invoker = true) as
select mt.*,
       p.ad_soyad as personel_adi, p.rol as personel_rol,
       ie.baslik as is_emri_baslik, ar.baslik as ariza_baslik,
       coalesce(sie.ad, sar.ad) as site_adi
  from malzeme_talepleri mt
  left join personeller p  on mt.personel_id = p.id
  left join is_emirleri ie on mt.is_emri_id = ie.id
  left join arizalar ar    on mt.ariza_id = ar.id
  left join siteler sie    on ie.site_id = sie.id
  left join siteler sar    on ar.site_id = sar.id;

-- Periyodik şablonlar + tesis/personel adı (admin liste)
create or replace view public.v_sablon
    with (security_invoker = true) as
select ps.*, s.ad as site_adi, p.ad_soyad as personel_adi
  from periyodik_sablonlar ps
  left join siteler s     on ps.site_id = s.id
  left join personeller p on ps.personel_id = p.id;

grant select on public.v_is_emri, public.v_ariza, public.v_masraf, public.v_sablon to authenticated;

-- ---------------------------------------------------------------------
-- admin_dashboard(p_site_id) — yönetici paneli özeti (dashboard.php)
-- ---------------------------------------------------------------------
create or replace function public.admin_dashboard(p_site_id bigint default null)
returns jsonb
    language plpgsql security definer set search_path = public, app
    as $$
declare
    v_firma  bigint := app.require_yonetici();
    v_ay_bas timestamptz := date_trunc('month', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
    v_tamam int; v_devam int; v_bekle int; v_acik int; v_geciken int; v_personel int;
    v_ort numeric; v_son jsonb; v_ozet jsonb;
begin
    if p_site_id is not null and not exists (select 1 from siteler where id=p_site_id and firma_id=v_firma) then
        raise exception 'Tesis firmanıza ait değil.' using errcode='PT422';
    end if;

    select count(*) filter (where durum='tamamlandi'),
           count(*) filter (where durum='devam_ediyor'),
           count(*) filter (where durum='bekliyor')
      into v_tamam, v_devam, v_bekle
      from is_emirleri
     where firma_id=v_firma and (p_site_id is null or site_id=p_site_id);

    select count(*) into v_acik from arizalar
     where firma_id=v_firma and durum in ('acik','bekliyor','dis_destek')
       and (p_site_id is null or site_id=p_site_id);

    select count(*) into v_geciken from is_emirleri
     where firma_id=v_firma and durum in ('bekliyor','devam_ediyor')
       and termin_tarihi is not null and termin_tarihi < current_date
       and (p_site_id is null or site_id=p_site_id);

    select avg(extract(epoch from (cozum_tarihi - olusturma_tarihi))/3600.0) into v_ort
      from arizalar
     where firma_id=v_firma and durum='cozuldu' and cozum_tarihi is not null
       and cozum_tarihi >= now() - interval '30 days'
       and (p_site_id is null or site_id=p_site_id);

    select count(*) into v_personel from personeller where firma_id=v_firma and aktif;

    select coalesce(jsonb_agg(t order by t.olusturma_tarihi desc), '[]'::jsonb) into v_son
      from (
        select ie.id, ie.baslik, ie.durum, ie.olusturma_tarihi,
               s.ad as site_adi, p.ad_soyad as personel_adi
          from is_emirleri ie
          left join siteler s on ie.site_id=s.id
          left join personeller p on ie.personel_id=p.id
         where ie.firma_id=v_firma and (p_site_id is null or ie.site_id=p_site_id)
         order by ie.olusturma_tarihi desc
         limit 10
      ) t;

    select coalesce(jsonb_agg(z order by z.ad), '[]'::jsonb) into v_ozet
      from (
        select s.id, s.ad,
               (select count(*) from is_emirleri ie where ie.site_id=s.id and ie.durum='devam_ediyor') as devam_eden,
               (select count(*) from arizalar a where a.site_id=s.id and a.durum in ('acik','bekliyor','dis_destek')) as acik_ariza,
               (select count(*) from is_emirleri ie where ie.site_id=s.id and ie.durum='tamamlandi' and ie.tamamlanma_tarihi >= v_ay_bas) as bu_ay_tamamlanan
          from siteler s
         where s.firma_id=v_firma and s.aktif
         order by s.ad
      ) z;

    return jsonb_build_object(
        'istatistik', jsonb_build_object(
            'tamamlanan_is', coalesce(v_tamam,0),
            'devam_eden_is', coalesce(v_devam,0),
            'bekleyen_is',   coalesce(v_bekle,0),
            'acik_ariza',    coalesce(v_acik,0),
            'aktif_personel',coalesce(v_personel,0),
            'geciken_is',    coalesce(v_geciken,0),
            'ort_cozum_saat',case when v_ort is null then null else round(v_ort,1) end
        ),
        'secili_site_id', p_site_id,
        'site_ozet', v_ozet,
        'son_is_emirleri', v_son
    );
end $$;

-- ---------------------------------------------------------------------
-- admin_rapor(p_month 'YYYY-MM', p_site_id) — aylık rapor (rapor.php)
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
    v_bas := (v_month || '-01')::timestamptz;
    v_bit := v_bas + interval '1 month';

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

revoke all on function public.admin_dashboard(bigint), public.admin_rapor(text, bigint) from public, anon;
grant execute on function public.admin_dashboard(bigint), public.admin_rapor(text, bigint) to authenticated;
