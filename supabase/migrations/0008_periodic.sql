-- =====================================================================
-- 0008_periodic.sql  —  Periyodik iş emri üretimi + pg_cron
--
-- PHP: core/PeriodicGenerator::uret() + cron/periodic_tasks.php (00:01).
-- Tarih kuralları Europe/Istanbul yerel gününe göre hesaplanır.
--
-- Dönüş sözleşmesi (generate_periodic):
--   >0   -> üretildi (yeni is_emri id)
--   0    -> bugün zaten üretilmiş (mükerrer)
--   null -> atanan site/personel pasif veya silinmiş
-- =====================================================================

create extension if not exists pg_cron;

-- ---------------------------------------------------------------------
-- app.generate_periodic — tek şablondan atomik üretim (cron + manuel ortak)
-- ---------------------------------------------------------------------
create or replace function app.generate_periodic(p_sablon_id bigint, p_tarih date)
returns bigint
    language plpgsql security definer
    set search_path = app, public
    as $$
declare
    s        periyodik_sablonlar%rowtype;
    v_n      int;
    v_id     bigint;
begin
    select * into s from periyodik_sablonlar where id = p_sablon_id;
    if not found then return null; end if;

    -- Site & personel aktif + firmaya ait mi?
    if not exists (select 1 from siteler where id=s.site_id and firma_id=s.firma_id and aktif)
       or not exists (select 1 from personeller where id=s.personel_id and firma_id=s.firma_id and aktif) then
        return null;
    end if;

    -- Atomik "günü kap": bugün zaten üretilmişse 0.
    update periyodik_sablonlar
       set son_uretim_tarihi = p_tarih
     where id = p_sablon_id
       and (son_uretim_tarihi is null or son_uretim_tarihi <> p_tarih);
    get diagnostics v_n = row_count;
    if v_n = 0 then return 0; end if;

    -- İş emri (durum 'bekliyor', planlanan = o gün 08:00; termin YOK).
    insert into is_emirleri (firma_id, site_id, personel_id, sablon_id, baslik, aciklama, durum, planlanan_baslangic_tarihi)
    values (s.firma_id, s.site_id, s.personel_id, s.id, s.baslik, s.aciklama, 'bekliyor',
            (p_tarih::timestamp + time '08:00'))
    returning id into v_id;

    -- Checklist maddeleri (satır satır; boşları atla).
    if coalesce(btrim(s.alt_gorevler),'') <> '' then
        insert into is_emirleri_alt_gorevler (firma_id, is_emri_id, gorev_metni)
        select s.firma_id, v_id, btrim(satir)
          from regexp_split_to_table(s.alt_gorevler, '\r\n|\r|\n') as satir
         where btrim(satir) <> '';
    end if;

    -- FCM (best-effort)
    perform app.notify_personel(s.personel_id, 'Yeni Periyodik Görev', s.baslik,
                                jsonb_build_object('tip','yeni_gorev','is_emri_id',v_id));
    return v_id;
end $$;

-- ---------------------------------------------------------------------
-- app.run_periodic_cron — her gece: bugüne denk gelen aktif şablonları üret
-- ---------------------------------------------------------------------
create or replace function app.run_periodic_cron()
returns integer
    language plpgsql security definer
    set search_path = app, public
    as $$
declare
    v_now       timestamp := (now() at time zone 'Europe/Istanbul');
    v_date      date       := v_now::date;
    v_isodow    int        := extract(isodow from v_now);      -- 1=Pzt .. 7=Paz
    v_gun       int        := extract(day from v_now);
    v_ay_son    int        := extract(day from (date_trunc('month', v_now) + interval '1 month - 1 day'));
    r           record;
    v_uretilen  int := 0;
    v_sonuc     bigint;
begin
    for r in
        select id, tekrar_tipi, tekrar_gunu
          from periyodik_sablonlar
         where aktif
           and (son_uretim_tarihi is null or son_uretim_tarihi <> v_date)
           and (
                tekrar_tipi = 'gunluk'
             or (tekrar_tipi = 'haftalik' and tekrar_gunu = v_isodow)
             or (tekrar_tipi = 'aylik' and (
                    (tekrar_gunu = v_gun)
                 or (tekrar_gunu > v_ay_son and v_gun = v_ay_son)   -- 31 -> ayın son günü
                 ))
           )
    loop
        v_sonuc := app.generate_periodic(r.id, v_date);
        if v_sonuc is not null and v_sonuc > 0 then
            v_uretilen := v_uretilen + 1;
        end if;
    end loop;
    return v_uretilen;
end $$;

-- Günlük zamanlama: 00:01 UTC (~03:01 İstanbul). Üretim tarihi İstanbul
-- yerel gününe göre hesaplanır (run_periodic_cron içinde).
select cron.schedule('periyodik-gorev-uret', '1 0 * * *', $$select app.run_periodic_cron()$$);
