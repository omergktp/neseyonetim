import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../widgets/glowing_blob.dart';
import 'login_screen.dart';
import 'home_screen.dart';

/// Açılış ekranı (Splash).
/// 1) Sunucudan sürüm kontrolü yapar. İstemci sürümü MIN_APP_VERSION'dan eskiyse
///    "Güncelleme Zorunlu" ekranını gösterir ve girişi engeller (plan.md §5.1).
/// 2) Aksi halde kayıtlı token'a göre Home veya Login ekranına yönlendirir.
/// Sunucuya ulaşılamazsa (offline) kullanıcı engellenmez; normal akışa devam edilir.
class SplashScreen extends StatefulWidget {
  final String themeColorHex;

  const SplashScreen({Key? key, required this.themeColorHex}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _guncellemeZorunlu = false;
  String _mesaj = '';
  String _storeUrl = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final surum = await ApiService.checkVersion();

    if (surum['ok'] == true && surum['guncellemeZorunlu'] == true) {
      // Zorunlu güncelleme: engelle.
      if (!mounted) return;
      setState(() {
        _guncellemeZorunlu = true;
        _mesaj = surum['mesaj'] ?? 'Lütfen uygulamayı güncelleyin.';
        _storeUrl = surum['storeUrl'] ?? '';
      });
      return;
    }

    // Sürüm uygun (veya kontrol edilemedi): token geçerliliğine göre yönlendir.
    // Süresi dolmuş token'la Home'a gitmek 401 + boş ekran yaşatır; login'e döneriz.
    final tokenGecerli = await ApiService.isTokenValid();
    if (!tokenGecerli) await ApiService.clearSession();

    final prefs = await SharedPreferences.getInstance();
    final themeColor = prefs.getString('theme_color') ?? widget.themeColorHex;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            tokenGecerli ? HomeScreen(themeColor: themeColor) : LoginScreen(),
      ),
    );
  }

  // Login ekranıyla aynı arka plan (marka bütünlüğü).
  BoxDecoration get _bgDecoration => const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );

  Widget _logoKutusu({double size = 84, double fontSize = 44}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Text('G',
            style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold)),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _bgDecoration,
        child: Stack(
          children: [
            const Positioned(top: -60, left: -40, child: GlowingBlob(color: Color(0xFF6366F1))),
            const Positioned(bottom: -80, right: -50, child: GlowingBlob(color: Color(0xFF8B5CF6))),
            _guncellemeZorunlu ? _buildUpdate() : _buildLoading(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _logoKutusu(),
          const SizedBox(height: 22),
          const Text('GLOW SAHA',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
          const SizedBox(height: 6),
          const Text('Tesis ve Saha Yönetim Sistemi',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 36),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF818CF8)),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdate() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _logoKutusu(size: 72, fontSize: 38),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.system_update, size: 56, color: Color(0xFF818CF8)),
                  const SizedBox(height: 18),
                  const Text('Güncelleme Gerekli',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(_mesaj,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.4)),
                  if (_storeUrl.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: SelectableText(_storeUrl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF93C5FD))),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6)),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() => _guncellemeZorunlu = false);
                          _bootstrap();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                        ),
                        child: const Text('Tekrar Dene',
                            style: TextStyle(
                                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('Çıkış', style: TextStyle(color: Colors.white38)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
