import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../services/api_service.dart';
import '../services/camera_service.dart';
import '../services/offline_queue.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/ui_utils.dart';

class ExpenseScreen extends StatefulWidget {
  final int? isEmriId; // İş emrine bağlı masraf
  final int? arizaId;  // Arızaya bağlı masraf
  const ExpenseScreen({Key? key, this.isEmriId, this.arizaId}) : super(key: key);

  @override
  _ExpenseScreenState createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final _kalemAdiController = TextEditingController();
  final _tutarController = TextEditingController();
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _camError = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (mounted && _camError) setState(() => _camError = false);
    try {
      final cameras = await CameraService.getCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _camError = true);
        return;
      }
      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.veryHigh, // Fiş/fatura okunabilirliği için yüksek çözünürlük
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint('Kamera başlatılamadı: $e');
      if (mounted) setState(() => _camError = true);
      UiUtils.showSnackBar('Kamera başlatılamadı, izinleri kontrol edin.', isError: true);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _submitExpense() async {
    if (_kalemAdiController.text.isEmpty || _tutarController.text.isEmpty) {
      UiUtils.showSnackBar('Malzeme adı ve tutar boş bırakılamaz.', isError: true);
      return;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      UiUtils.showSnackBar('Fiş/Fatura fotoğrafı için kamera gerekli.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final XFile photo = await _cameraController!.takePicture();
      final bytes = await File(photo.path).readAsBytes();
      String base64Image = base64Encode(bytes);

      final body = <String, dynamic>{
        if (widget.isEmriId != null) 'is_emri_id': widget.isEmriId,
        if (widget.arizaId != null) 'ariza_id': widget.arizaId,
        'kalem_adi': _kalemAdiController.text.trim(),
        'tutar': _tutarController.text.trim(),
        'fis_fotograf_url': base64Image,
      };

      // KURAL 3 (Offline-first): İnternet yoksa/sunucuya ulaşılamazsa fiş kaybolmasın.
      if (!await SyncService.hasInternet()) {
        await OfflineQueue.addRequest('add_expense.php', body);
        if (!mounted) return;
        UiUtils.showSnackBar('İnternet yok: masraf kuyruğa alındı, bağlantı gelince gönderilecek.');
        Navigator.pop(context);
        return;
      }

      final sonuc = await ApiService.postQueued('add_expense.php', body);
      if (!mounted) return;

      if (sonuc == 'ok') {
        UiUtils.showSnackBar('Masraf formu gönderildi ve onaya sunuldu.');
        Navigator.pop(context);
      } else if (sonuc == 'retry') {
        await OfflineQueue.addRequest('add_expense.php', body);
        if (!mounted) return;
        UiUtils.showSnackBar('Sunucuya ulaşılamadı: masraf kuyruğa alındı, bağlantı gelince gönderilecek.');
        Navigator.pop(context);
      } else {
        UiUtils.showSnackBar('Masraf kaydedilemedi. Tutarı ve bilgileri kontrol edin.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showSnackBar('Hata: $e', isError: true);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// Alan başlığı: AppTheme.sectionLabel + opsiyonel zorunlu (*) işareti.
  Widget _fieldLabel(String text, {IconData? icon, bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          AppTheme.sectionLabel(text, icon: icon),
          if (required)
            const Text(' *', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Masraf / Malzeme Girişi'),
        flexibleSpace: AppTheme.appBarFlex(primary),
      ),
      body: _isLoading
          ? AppTheme.loadingBox('Gönderiliyor...', color: primary)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bilgi paneli — AppTheme.infoPanel ile standardize edildi
                  AppTheme.infoPanel(
                    icon: Icons.receipt_long_outlined,
                    color: primary,
                    title: 'Masraf / Malzeme Girişi',
                    text: 'Malzeme/masraf kalemini, tutarını gir ve fiş/fatura fotoğrafını çek. Yönetici onayına gönderilecek.',
                  ),
                  const SizedBox(height: 20),

                  // Kalem adı alanı
                  _fieldLabel('Alınan Malzeme / Yapılan Masraf', icon: Icons.shopping_bag_outlined, required: true),
                  TextField(
                    controller: _kalemAdiController,
                    decoration: const InputDecoration(hintText: 'Örn: PVC boru, temizlik bezi, vida...'),
                  ),
                  const SizedBox(height: 16),

                  // Tutar alanı
                  _fieldLabel('Tutar (TL)', icon: Icons.payments_outlined, required: true),
                  TextField(
                    controller: _tutarController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Örn: 150.50', prefixIcon: Icon(Icons.payments_outlined)),
                  ),
                  const SizedBox(height: 20),

                  // Kamera başlığı — zorunlu alan işareti AppTheme.danger ile
                  _fieldLabel('Fiş / Fatura Fotoğrafı', icon: Icons.camera_alt_outlined, required: true),

                  // Kamera önizlemesi veya yükleme durumu
                  if (_isCameraInitialized)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          SizedBox(
                            height: 250,
                            width: double.infinity,
                            child: CameraPreview(_cameraController!),
                          ),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.receipt_long, color: Colors.white, size: 14),
                                  SizedBox(width: 6),
                                  Text('Fiş/fatura', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      height: 250,
                      decoration: BoxDecoration(
                        color: AppTheme.fieldFill,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: _camError
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.no_photography_outlined, size: 36, color: AppTheme.textMuted),
                                  const SizedBox(height: 8),
                                  const Text('Kamera açılamadı — fiş fotoğrafı zorunludur',
                                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: _initCamera,
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Tekrar Dene'),
                                  ),
                                ],
                              ),
                            )
                          : AppTheme.loadingBox('Kamera hazırlanıyor...'),
                    ),

                  const SizedBox(height: 24),

                  // Gönder butonu
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _submitExpense,
                      icon: const Icon(Icons.send),
                      label: const Text('Masrafı Onaya Gönder', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
