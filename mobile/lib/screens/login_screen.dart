import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../utils/ui_utils.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _firmaKoduController = TextEditingController();
  final _telefonController = TextEditingController();
  final _sifreController = TextEditingController();
  final _ipController = TextEditingController();
  bool _isLoading = false;
  bool _sifreGizli = true;

  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _ipController.text = ApiService.serverIp;
    
    // Arka plan animasyonu için kontrolcü
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgController.dispose();
    _firmaKoduController.dispose();
    _telefonController.dispose();
    _sifreController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  void _login() async {
    setState(() => _isLoading = true);
    await ApiService.setServerIp(_ipController.text.trim());
    final result = await ApiService.login(
      _firmaKoduController.text.trim(),
      _telefonController.text.trim(),
      _sifreController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success']) {
      FcmService.syncToken();
      final prefs = await SharedPreferences.getInstance();
      final colorHex = prefs.getString('theme_color') ?? '#3B82F6';
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (_, __, ___) => HomeScreen(themeColor: colorHex),
          transitionsBuilder: (_, anim, __, child) {
            return FadeTransition(opacity: anim, child: child);
          },
        ),
      );
    } else {
      UiUtils.showSnackBar(result['message'], isError: true);
    }
  }

  Widget _buildGlassInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType type = TextInputType.text,
    String? helperText,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && _sifreGizli,
        keyboardType: type,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          helperText: helperText,
          helperStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
          prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.7)),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(_sifreGizli ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white.withValues(alpha: 0.5)),
                  onPressed: () => setState(() => _sifreGizli = !_sifreGizli),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Dinamik Animasyonlu Arka Plan
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    top: -150 + (50 * _bgController.value),
                    left: -100 - (30 * _bgController.value),
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF3B82F6).withValues(alpha: 0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -150 - (50 * _bgController.value),
                    right: -100 + (30 * _bgController.value),
                    child: Container(
                      width: 450,
                      height: 450,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          
          // Glassmorphism Blur Katmanı
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: const SizedBox(),
            ),
          ),

          // İçerik
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo Animasyonu
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(seconds: 1),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF60A5FA), Color(0xFFA78BFA)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                        ),
                        child: const Center(
                          child: Text('G', style: TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'GLOW SAHA',
                      style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Premium Mobil Portal',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 48),

                    // Glassmorphism Form Kartı
                    ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 30)
                            ],
                          ),
                          child: Column(
                            children: [
                              _buildGlassInput(
                                controller: _ipController,
                                label: 'Sunucu (IP)',
                                icon: Icons.dns_rounded,
                                type: TextInputType.url,
                              ),
                              const SizedBox(height: 16),
                              _buildGlassInput(
                                controller: _firmaKoduController,
                                label: 'Firma Kodu',
                                icon: Icons.business_rounded,
                              ),
                              const SizedBox(height: 16),
                              _buildGlassInput(
                                controller: _telefonController,
                                label: 'Telefon Numarası',
                                icon: Icons.phone_rounded,
                                type: TextInputType.phone,
                              ),
                              const SizedBox(height: 16),
                              _buildGlassInput(
                                controller: _sifreController,
                                label: 'Şifre',
                                icon: Icons.lock_rounded,
                                isPassword: true,
                              ),
                              const SizedBox(height: 32),

                              // Gradient Buton
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: double.infinity,
                                height: 60,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: LinearGradient(
                                    colors: _isLoading 
                                      ? [Colors.grey.shade600, Colors.grey.shade700]
                                      : [const Color(0xFF3B82F6), const Color(0xFF8B5CF6)],
                                  ),
                                  boxShadow: _isLoading ? [] : [
                                    BoxShadow(
                                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    )
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: _isLoading ? null : _login,
                                    child: Center(
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 28, height: 28,
                                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                          : const Text(
                                              'GİRİŞ YAP',
                                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
