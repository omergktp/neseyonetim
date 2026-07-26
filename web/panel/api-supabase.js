// =====================================================================
// api-supabase.js — Panel için Supabase uyumluluk katmanı
//
// Panel kodu eski PHP uçlarını (admin/*.php) çağırmaya devam eder;
// buradaki apiFetch() her yolu ilgili PostgREST view / RPC çağrısına
// çevirir ve PHP dönemindeki yanıt şekillerini aynen üretir.
// Böylece dashboard.html / rapor_pdf.html iş mantığı hiç değişmez.
//
// Fotoğraflar: DB'de "bucket/obje_yolu" saklanır; listelerde kısa ömürlü
// imzalı URL'e çevrilir. fotoUrl() mutlak URL'leri olduğu gibi geçirir.
// =====================================================================

const SUPABASE_URL = 'https://bfkiifbzxwhbviluyzcp.supabase.co';
const SUPABASE_KEY = 'sb_publishable_HdcOSN5v1E4YBoQok996Mg_W1i1xnGx';

let token = localStorage.getItem('glow_token');
if (!token) { window.location.href = 'index.html'; }

function _cikis() { localStorage.clear(); window.location.href = 'index.html'; }

// ---- Sessiz oturum yenileme (refresh_token) ----
// 401 alınınca bir kez yenileme denenir ve istek tekrarlanır; yenileme de
// başarısızsa login'e dönülür. Aynı anda gelen 401'ler tek yenilemeyi bekler
// (GoTrue refresh token'ları döndürümlüdür; yarış oturumu geçersiz kılar).
let _yenilemeUcusta = null;
function _oturumYenile() {
    if (_yenilemeUcusta) return _yenilemeUcusta;
    _yenilemeUcusta = (async () => {
        const rt = localStorage.getItem('glow_refresh');
        if (!rt) return false;
        try {
            const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
                method: 'POST',
                headers: { 'apikey': SUPABASE_KEY, 'Content-Type': 'application/json' },
                body: JSON.stringify({ refresh_token: rt }),
            });
            if (!res.ok) {
                // 4xx: refresh token geçersiz/iptal; ağ dışı kalıcı hata.
                if (res.status >= 400 && res.status < 500) localStorage.removeItem('glow_refresh');
                return false;
            }
            const d = await res.json();
            if (!d.access_token) return false;
            token = d.access_token;
            localStorage.setItem('glow_token', token);
            if (d.refresh_token) localStorage.setItem('glow_refresh', d.refresh_token);
            return true;
        } catch (_) { return false; }
    })().finally(() => { _yenilemeUcusta = null; });
    return _yenilemeUcusta;
}

async function _sbFetch(path, options = {}) {
    const istek = () => fetch(`${SUPABASE_URL}${path}`, {
        ...options,
        headers: {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json',
            ...(options.headers || {}),
        },
    });
    let res = await istek();
    if (res.status === 401 && await _oturumYenile()) res = await istek();
    if (res.status === 401) { _cikis(); throw new Error('Yetkisiz'); }
    return res;
}

// PostgREST view/tablo okuma → dizi
async function _sbList(query) {
    const res = await _sbFetch(`/rest/v1/${query}`);
    if (!res.ok) throw new Error('Sorgu başarısız: ' + query);
    return res.json();
}

// RPC çağrısı → {ok, status, body}
async function _sbRpc(fn, params = {}) {
    const res = await _sbFetch(`/rest/v1/rpc/${fn}`, { method: 'POST', body: JSON.stringify(params) });
    let body = {};
    try { body = await res.json(); } catch (_) {}
    // PostgREST hata gövdesi {message,...} — PHP ile aynı alan adı.
    return { ok: res.ok, status: res.status, body };
}

// "bucket/obje_yolu" → kısa ömürlü imzalı mutlak URL (yoksa null)
async function _imzali(stored) {
    if (!stored || /^https?:/.test(stored)) return stored || null;
    const i = stored.indexOf('/');
    if (i <= 0) return null;
    try {
        const res = await _sbFetch(`/storage/v1/object/sign/${stored.substring(0, i)}/${stored.substring(i + 1)}`, {
            method: 'POST', body: JSON.stringify({ expiresIn: 3600 }),
        });
        if (!res.ok) return null;
        const d = await res.json();
        return d.signedURL ? `${SUPABASE_URL}/storage/v1${d.signedURL}` : null;
    } catch (_) { return null; }
}

async function _imzalaAlan(liste, alanlar) {
    await Promise.all(liste.map(async (kayit) => {
        for (const a of alanlar) kayit[a] = await _imzali(kayit[a]);
    }));
    return liste;
}

// Panel fotoğraf yolları: imzalı URL'ler zaten mutlaktır, aynen geçir.
function fotoUrl(x) { return x || ''; }

// "firma-logo/{firma_id}/..." -> public URL (bucket herkese açık)
function firmaLogoUrl(stored) {
    if (!stored) return null;
    if (/^https?:/.test(stored)) return stored;
    return `${SUPABASE_URL}/storage/v1/object/public/${stored}`;
}

// Logo dosyasını Storage'a yükler; DB'de saklanacak "firma-logo/..." yolu döner.
async function firmaLogoYukle(firmaId, file) {
    const uzanti = (file.name.split('.').pop() || 'png').toLowerCase();
    const yol = `firma-logo/${firmaId}/logo_${Date.now()}.${uzanti}`;
    const res = await _sbFetch(`/storage/v1/object/${yol}`, {
        method: 'POST',
        headers: { 'Content-Type': file.type || 'image/png' },
        body: file,
    });
    if (!res.ok) {
        const d = await res.json().catch(() => ({}));
        throw new Error(d.message || 'Logo yüklenemedi.');
    }
    return yol;
}

// ---- Yardımcılar: PHP gövdesindeki serbest tipleri RPC tiplerine çevir ----
const _int = (v) => (v === undefined || v === null || v === '' ? null : parseInt(v, 10));
const _num = (v) => (v === undefined || v === null || v === '' ? null : parseFloat(v));
const _str = (v) => (v === undefined || v === null || v === '' ? null : String(v));
// "YYYY-MM-DD HH:MM:SS" (yerel) → ISO (timestamptz için doğru an)
function _tsz(v) {
    if (!v) return null;
    const d = new Date(String(v).replace(' ', 'T'));
    return isNaN(d) ? null : d.toISOString();
}

// Response benzeri nesne (panel res.ok / res.status / res.json() kullanır)
function _yanit(ok, status, body) {
    return { ok, status, json: async () => body };
}
function _rpcYanit(r) { return _yanit(r.ok, r.status, r.body); }

// =====================================================================
// apiFetch — eski "admin/*.php" yollarını Supabase'e eşler
// =====================================================================
async function apiFetch(path, options = {}) {
    const [yol, sorguStr] = path.split('?');
    const q = new URLSearchParams(sorguStr || '');
    const govde = options.body ? JSON.parse(options.body) : {};
    const islem = govde.islem;

    try {
        switch (yol) {
            // ---------------- DASHBOARD / RAPOR ----------------
            case 'admin/dashboard.php': {
                const r = await _sbRpc('admin_dashboard', { p_site_id: _int(q.get('site_id')) });
                return _rpcYanit(r);
            }
            case 'admin/rapor.php': {
                const r = await _sbRpc('admin_rapor', {
                    p_month: _str(q.get('month')),
                    p_site_id: _int(q.get('site_id')),
                });
                return _rpcYanit(r);
            }

            // ---------------- FİRMA AYARLARI ----------------
            case 'admin/firma.php': {
                if (options.method === 'POST') {
                    const r = await _sbRpc('admin_firma_guncelle', {
                        p_ad: _str(govde.ad),
                        p_hex_color: _str(govde.hex_color),
                        p_logo_path: _str(govde.logo),
                        p_logo_set: 'logo' in govde,
                    });
                    return _rpcYanit(r);
                }
                // RLS zaten yalnız kendi firmayı gösterir.
                const rows = await _sbList('firmalar?select=*&limit=1');
                return _yanit(true, 200, { data: rows[0] || null });
            }

            // ---------------- PERSONELLER ----------------
            case 'admin/personeller.php': {
                if (options.method === 'POST') {
                    let r;
                    if (islem === 'sil') r = await _sbRpc('admin_personel_sil', { p_id: _int(govde.id) });
                    else if (islem === 'aktif_degistir') r = await _sbRpc('admin_personel_aktif_degistir', { p_id: _int(govde.id) });
                    else if (islem === 'guncelle') r = await _sbRpc('admin_personel_guncelle', {
                        p_id: _int(govde.id), p_ad_soyad: _str(govde.ad_soyad),
                        p_telefon: _str(govde.telefon), p_rol: _str(govde.rol), p_sifre: _str(govde.sifre),
                    });
                    else r = await _sbRpc('admin_personel_ekle', {
                        p_ad_soyad: _str(govde.ad_soyad), p_telefon: _str(govde.telefon),
                        p_sifre: _str(govde.sifre), p_rol: _str(govde.rol),
                    });
                    return _rpcYanit(r);
                }
                const data = await _sbList('personeller?select=id,ad_soyad,telefon,rol,aktif&order=ad_soyad.asc');
                return _yanit(true, 200, { data });
            }

            // ---------------- SİTELER ----------------
            case 'admin/siteler.php': {
                if (options.method === 'POST') {
                    let r;
                    if (islem === 'sil') r = await _sbRpc('admin_site_sil', { p_id: _int(govde.id) });
                    else if (islem === 'qr_yenile') r = await _sbRpc('admin_site_qr_yenile', { p_id: _int(govde.id) });
                    else if (islem === 'guncelle') r = await _sbRpc('admin_site_guncelle', {
                        p_id: _int(govde.id), p_ad: _str(govde.ad), p_adres: _str(govde.adres),
                        p_enlem: _num(govde.enlem), p_boylam: _num(govde.boylam),
                    });
                    else r = await _sbRpc('admin_site_ekle', {
                        p_ad: _str(govde.ad), p_adres: _str(govde.adres),
                        p_enlem: _num(govde.enlem), p_boylam: _num(govde.boylam),
                    });
                    return _rpcYanit(r);
                }
                const data = await _sbList('siteler?select=*&order=ad.asc');
                return _yanit(true, 200, { data });
            }

            // ---------------- İŞ EMİRLERİ ----------------
            case 'admin/is_emirleri.php': {
                if (options.method === 'POST') {
                    let r;
                    if (islem === 'sil') r = await _sbRpc('admin_is_emri_sil', { p_id: _int(govde.id) });
                    else {
                        const params = {
                            p_site_id: _int(govde.site_id), p_personel_id: _int(govde.personel_id),
                            p_baslik: _str(govde.baslik), p_aciklama: _str(govde.aciklama),
                            p_qr_kod: _str(govde.qr_kod), p_planlanan: _tsz(govde.planlanan_baslangic_tarihi),
                            p_termin: _str(govde.termin_tarihi),
                        };
                        r = (islem === 'guncelle')
                            ? await _sbRpc('admin_is_emri_guncelle', { p_id: _int(govde.id), ...params })
                            : await _sbRpc('admin_is_emri_ekle', params);
                    }
                    return _rpcYanit(r);
                }
                const durum = q.get('durum');
                const data = await _sbList('v_is_emri?select=*&order=olusturma_tarihi.desc'
                    + (durum ? `&durum=eq.${encodeURIComponent(durum)}` : ''));
                return _yanit(true, 200, { data });
            }
            case 'admin/is_emri_detay.php': {
                const id = _int(q.get('id'));
                const rows = await _sbList(`v_is_emri?select=*&id=eq.${id}&limit=1`);
                if (!rows.length) return _yanit(false, 404, { message: 'İş emri bulunamadı.' });
                const r = rows[0];
                const [alt, masraflar, pers] = await Promise.all([
                    _sbList(`is_emirleri_alt_gorevler?select=id,gorev_metni,yapildi_mi&is_emri_id=eq.${id}&order=id.asc`),
                    _sbList(`v_masraf?select=*&is_emri_id=eq.${id}&order=olusturma_tarihi.desc`),
                    r.personel_id ? _sbList(`personeller?select=telefon&id=eq.${r.personel_id}&limit=1`) : [],
                ]);
                r.alt_gorevler = alt;
                r.masraflar = masraflar;
                r.personel_telefon = pers.length ? pers[0].telefon : null;
                r.kapanis_fotograf_url = await _imzali(r.kapanis_fotograf_url);
                return _yanit(true, 200, { data: r });
            }

            // ---------------- ARIZALAR ----------------
            case 'admin/arizalar.php': {
                const data = await _sbList('v_ariza?select=*&order=olusturma_tarihi.desc');
                await _imzalaAlan(data, ['fotograf_url', 'cozum_fotograf_url']);
                return _yanit(true, 200, { data });
            }
            case 'admin/ariza_ekle.php': {
                const r = await _sbRpc('admin_ariza_ekle', {
                    p_site_id: _int(govde.site_id), p_baslik: _str(govde.baslik),
                    p_aciklama: _str(govde.aciklama),
                    p_teknik_personel_id: _int(govde.teknik_personel_id),
                    p_oncelik: _str(govde.oncelik) || 'normal',
                });
                return _rpcYanit(r);
            }
            case 'admin/ariza_guncelle.php': {
                if (islem === 'sil') {
                    return _rpcYanit(await _sbRpc('admin_ariza_sil', { p_id: _int(govde.id) }));
                }
                const r = await _sbRpc('admin_ariza_guncelle', {
                    p_id: _int(govde.id),
                    p_baslik: _str(govde.baslik),
                    p_aciklama: _str(govde.aciklama),
                    p_aciklama_set: 'aciklama' in govde,
                    p_site_id: _int(govde.site_id),
                    p_oncelik: _str(govde.oncelik),
                    p_durum: _str(govde.durum),
                    p_teknik_personel_id: _int(govde.teknik_personel_id),
                    p_teknik_set: 'teknik_personel_id' in govde,
                });
                return _rpcYanit(r);
            }

            // ---------------- MASRAFLAR ----------------
            case 'admin/masraflar.php': {
                if (options.method === 'POST') {
                    const r = (islem === 'sil')
                        ? await _sbRpc('admin_masraf_sil', { p_id: _int(govde.id) })
                        : await _sbRpc('admin_masraf_karar', { p_id: _int(govde.id), p_karar: islem });
                    return _rpcYanit(r);
                }
                let sorgu = 'v_masraf?select=*&order=olusturma_tarihi.desc';
                if (q.get('durum')) sorgu += `&durum=eq.${encodeURIComponent(q.get('durum'))}`;
                if (q.get('ariza_id')) sorgu += `&ariza_id=eq.${_int(q.get('ariza_id'))}`;
                const data = await _sbList(sorgu);
                await _imzalaAlan(data, ['fis_fatura_fotograf']);
                return _yanit(true, 200, { data });
            }

            // ---------------- PERİYODİK ŞABLONLAR ----------------
            case 'admin/periyodik_gorevler.php': {
                if (options.method === 'POST') {
                    let r;
                    if (islem === 'sil') r = await _sbRpc('admin_sablon_sil', { p_id: _int(govde.id) });
                    else if (islem === 'aktif_degistir') r = await _sbRpc('admin_sablon_aktif_degistir', { p_id: _int(govde.id) });
                    else if (islem === 'uret') r = await _sbRpc('admin_sablon_uret', { p_id: _int(govde.id) });
                    else {
                        const params = {
                            p_site_id: _int(govde.site_id), p_personel_id: _int(govde.personel_id),
                            p_baslik: _str(govde.baslik), p_tekrar_tipi: _str(govde.tekrar_tipi),
                            p_aciklama: _str(govde.aciklama), p_alt_gorevler: _str(govde.alt_gorevler),
                            p_tekrar_gunu: _int(govde.tekrar_gunu),
                        };
                        r = (islem === 'guncelle')
                            ? await _sbRpc('admin_sablon_guncelle', { p_id: _int(govde.id), ...params })
                            : await _sbRpc('admin_sablon_ekle', params);
                    }
                    return _rpcYanit(r);
                }
                const data = await _sbList('v_sablon?select=*&order=id.desc');
                return _yanit(true, 200, { data });
            }

            default:
                return _yanit(false, 404, { message: 'Bilinmeyen uç: ' + yol });
        }
    } catch (e) {
        if (e && e.message === 'Yetkisiz') throw e;
        console.error('apiFetch', path, e);
        return _yanit(false, 500, { message: 'Sunucuya bağlanılamadı.' });
    }
}
