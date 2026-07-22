import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/camera_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_utils.dart';
import 'expense_screen.dart';
import 'camera_capture_screen.dart';

// Teknik personelin kendisine atanmış arızaları gördüğü liste ekranı.
class FaultsScreen extends StatefulWidget {
  const FaultsScreen({Key? key}) : super(key: key);

  @override
  State<FaultsScreen> createState() => _FaultsScreenState();
}

class _FaultsScreenState extends State<FaultsScreen> {
  List<dynamic> _faults = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final f = await ApiService.getFaults();
    if (mounted) {
      setState(() {
        if (f != null) _faults = f; // null: yüklenemedi, eldeki listeyi koru
        _loading = false;
      });
      if (f == null) {
        UiUtils.showSnackBar('Arıza listesi yüklenemedi, bağlantıyı kontrol edin.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arızalarım', style: TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: AppTheme.appBarFlex(Theme.of(context).colorScheme.primary),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _faults.isEmpty
                ? AppTheme.emptyState(
                    icon: Icons.handyman_outlined,
                    title: 'Açık arıza yok',
                    subtitle: 'Sana atanmış açık bir arıza kaydı bulunmuyor. Aşağı çekerek yenileyebilirsin.',
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _faults.length,
                    itemBuilder: (context, i) {
                      final a = _faults[i];
                      final bekliyor = a['durum'] == 'bekliyor';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: AppTheme.cardDecoration,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => FaultDetailScreen(fault: a)),
                              );
                              _load(); // Dönüşte listeyi tazele
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: AppTheme.danger.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(bekliyor ? Icons.hourglass_bottom : Icons.warning_amber_rounded, color: AppTheme.danger),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(a['baslik'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                                        const SizedBox(height: 4),
                                        Text(a['site_adi'] ?? 'Tesis belirtilmemiş', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                                        const SizedBox(height: 8),
                                        StatusUi.chip(a['durum']),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

// Tek bir arızanın detayı: foto, açıklama + "Masraf Ekle" ve "Çözüldü işaretle".
class FaultDetailScreen extends StatefulWidget {
  final Map<String, dynamic> fault;
  const FaultDetailScreen({Key? key, required this.fault}) : super(key: key);

  @override
  State<FaultDetailScreen> createState() => _FaultDetailScreenState();
}

class _FaultDetailScreenState extends State<FaultDetailScreen> {
  bool _loading = false;
  late final TextEditingController _notController;

  @override
  void initState() {
    super.initState();
    _notController = TextEditingController(text: widget.fault['teknik_notu']?.toString() ?? '');
  }

  @override
  void dispose() {
    _notController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String durum) async {
    // Dış destek için neden gerektiğini not olarak iste
    if (durum == 'dis_destek' && _notController.text.trim().isEmpty) {
      UiUtils.showSnackBar('Lütfen neden dış destek gerektiğini not olarak yazın.', isError: true);
      return;
    }

    String? cozumFoto;

    // Çözüldü: kamera açılır, çözüm fotoğrafı zorunlu
    if (durum == 'cozuldu') {
      final path = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const CameraCaptureScreen(title: 'Çözüm Fotoğrafı')),
      );
      if (path == null) return; // kullanıcı çekmeden çıktı

      setState(() => _loading = true);
      try {
        // Filigran her zaman basılır (Kural 4); konum alınamazsa en az tarih/saat damgalanır.
        final pos = await LocationService.getCurrentLocation();
        await CameraService.addWatermark(path, pos?.latitude, pos?.longitude);
        final bytes = await File(path).readAsBytes();
        cozumFoto = base64Encode(bytes);
      } catch (e) {
        if (mounted) setState(() => _loading = false);
        if (mounted) {
          UiUtils.showSnackBar('Fotoğraf işlenemedi: $e', isError: true);
        }
        return;
      }
    } else {
      setState(() => _loading = true);
    }

    final id = int.tryParse(widget.fault['id'].toString()) ?? 0;
    final res = await ApiService.updateFault(id, durum, not: _notController.text.trim(), cozumFotograf: cozumFoto);
    if (!mounted) return;
    setState(() => _loading = false);
    UiUtils.showSnackBar(res['message'], isError: !res['success']);
    if (res['success']) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.fault;
    final fotoUrl = (a['fotograf_url'] != null && a['fotograf_url'] != '') ? ApiService.fileUrl(a['fotograf_url']) : null;
    final arizaId = int.tryParse(a['id'].toString()) ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(a['baslik'] ?? 'Arıza'),
        flexibleSpace: AppTheme.appBarFlex(Theme.of(context).colorScheme.primary),
      ),
      body: _loading
          ? Center(child: AppTheme.loadingBox('İşleniyor...', color: Theme.of(context).colorScheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Başlık kartı: tesis + durum rozeti + açıklama
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 18, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(a['site_adi'] ?? 'Tesis',
                                  style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600, fontSize: 15)),
                            ),
                            StatusUi.chip(a['durum']),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(a['aciklama'] ?? 'Açıklama yok', style: const TextStyle(fontSize: 15, color: AppTheme.textDark, height: 1.4)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (fotoUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          Image.network(
                            fotoUrl,
                            height: 240,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              height: 240,
                              color: AppTheme.fieldFill,
                              child: const Center(child: Text('Fotoğraf yüklenemedi', style: TextStyle(color: AppTheme.textMuted))),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                              child: const Text('Arıza fotoğrafı', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ExpenseScreen(arizaId: arizaId)),
                        );
                      },
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Masraf / Malzeme Ekle'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppTheme.sectionLabel('Teknik Not', icon: Icons.notes),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notController,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Örn: Yedek parça sipariş edildi, bekliyor'),
                  ),
                  const SizedBox(height: 20),
                  AppTheme.sectionLabel('Durumu Güncelle', icon: Icons.update),
                  const SizedBox(height: 10),
                  AppTheme.infoPanel(
                    icon: Icons.camera_alt_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    text: '"Çözüldü" seçilince kamera açılır ve çözüm fotoğrafı çekmen gerekir.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: () => _updateStatus('bekliyor'),
                            icon: const Icon(Icons.hourglass_bottom, color: AppTheme.warning),
                            label: const Text('Malzeme Bekliyor', style: TextStyle(color: AppTheme.warning)),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.warning)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () => _updateStatus('cozuldu'),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Çözüldü'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => _updateStatus('dis_destek'),
                      icon: const Icon(Icons.engineering),
                      label: const Text('Çözülemedi – Dış Destek Gerekli'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.info, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
