import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/construction_backdrop.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey    = GlobalKey<FormState>();
  final _userCtrl   = TextEditingController();
  final _passCtrl   = TextEditingController();
  bool  _obscure    = true;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final auth = context.read<AuthService>();
    final ok   = await auth.login(_userCtrl.text, _passCtrl.text);

    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(auth.error ?? 'Login failed',
                  style: const TextStyle(color: Colors.white)),
            ),
          ]),
          backgroundColor: AppTheme.accentRed,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // AuthService notifies listeners after loading the profile.
    // The root widget (_Root in main.dart) owns role-based navigation.
    // Avoid pushing a second dashboard route here.
    return;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle,
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: ConstructionBackdrop(
          child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(children: [
                  const SizedBox(height: 52),
                  _logo(),
                  const SizedBox(height: 16),
                  Text('CMS Site Manager AI',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      )),
                  const SizedBox(height: 5),
                  Text('Solar Site Construction Management',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 48),
                  _card(),
                  const SizedBox(height: 24),
                  _footer(),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _logo() => Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            colors: [AppTheme.primary, AppTheme.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(AppTheme.isLight ? 0.22 : 0.5),
              blurRadius: 28, spreadRadius: 4,
            ),
          ],
        ),
        child: const Icon(Icons.engineering_rounded, color: Colors.white, size: 44),
      );

  Widget _card() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: AppTheme.isLight ? const Color(0x1A0F172A) : Colors.black.withOpacity(0.4),
            blurRadius: 24, offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(26),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // "SECURE LOGIN" chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.accentGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.accentGreen.withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _PulseDot(),
              SizedBox(width: 6),
              Text('SECURE LOGIN',
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1,
                  )),
            ]),
          ),
          const SizedBox(height: 24),

          // Username
          Text('Username',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4,
              )),
          const SizedBox(height: 8),
          TextFormField(
            controller: _userCtrl,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16, fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. john_engineer',
              prefixIcon: Icon(Icons.person_rounded, color: AppTheme.accent, size: 22),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Username is required' : null,
          ),
          const SizedBox(height: 20),

          // Password
          Text('Password',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4,
              )),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _login(),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16, fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Your password',
              prefixIcon:
                  Icon(Icons.lock_rounded, color: AppTheme.accent, size: 22),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppTheme.textMuted,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Password is required' : null,
          ),
          const SizedBox(height: 28),

          // Submit button
          Consumer<AuthService>(
            builder: (_, auth, __) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: auth.loading
                  ? Container(
                      key: const ValueKey('loading'),
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      key: const ValueKey('btn'),
                      onPressed: _login,
                      icon: const Icon(Icons.login_rounded, size: 20),
                      label: const Text('SIGN IN'),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _footer() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard.withOpacity(0.86),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Authorised personnel only',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shield_outlined, color: AppTheme.textMuted, size: 13),
            const SizedBox(width: 5),
            Text('CMS v11.0  •  Solar Site Platform',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ]),
        ]),
      );
}

/// Tiny pulsing green dot shown in the "SECURE LOGIN" chip
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.accentGreen.withOpacity(0.5 + _c.value * 0.5),
        ),
      ),
    );
  }
}
