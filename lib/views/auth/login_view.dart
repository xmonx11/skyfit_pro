import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/auth_viewmodel.dart';
import '../widgets/sky_button.dart';
import '../widgets/sky_text_field.dart';
import '../widgets/sky_snackbar.dart';
import 'register_view.dart';

class LoginView extends StatefulWidget {
  final bool sessionExpired;

  const LoginView({super.key, this.sessionExpired = false});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool _biometricTapped = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _fadeCtrl.forward();

    if (widget.sessionExpired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SkySnackbar.error(
          context,
          'Your session has expired. Please sign in again.',
        );
      });
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _onEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final vm = context.read<AuthViewModel>();
    if (vm.isLoading) return;
    final ok = await vm.signInWithEmail(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!mounted) return;
    if (!ok) {
      SkySnackbar.error(context, vm.errorMessage ?? 'Login failed.');
    }
  }

  Future<void> _onGoogleLogin() async {
    final vm = context.read<AuthViewModel>();
    if (vm.isLoading) return;
    final ok = await vm.signInWithGoogle();
    if (!mounted) return;
    if (!ok) {
      SkySnackbar.error(context, vm.errorMessage ?? 'Google Sign-In failed.');
    }
  }

  Future<void> _onBiometricLogin() async {
    if (_biometricTapped) return;
    _biometricTapped = true;
    try {
      final vm = context.read<AuthViewModel>();
      if (vm.isLoading) return;
      final ok = await vm.signInWithBiometrics();
      if (!mounted) return;
      if (!ok) {
        SkySnackbar.error(
          context,
          vm.errorMessage ?? 'Biometric authentication failed.',
        );
      }
    } finally {
      if (mounted) _biometricTapped = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    // Scale everything relative to screen width — clamp so it
    // never gets too huge on tablets or too tiny on small phones.
    final double w = size.width.clamp(320.0, 600.0);
    final double scale = w / 390.0; // 390 = baseline (iPhone 14 width)

    // Responsive helpers
    double sp(double base) => (base * scale).clamp(base * 0.82, base * 1.15);
    double dp(double base) => (base * scale).clamp(base * 0.80, base * 1.20);

    return MediaQuery(
      // Clamp system text scaling to prevent oversized UI on accessibility fonts
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(
          MediaQuery.of(context).textScaler.scale(1.0).clamp(0.85, 1.10),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A14),
        body: Stack(
          children: [
            // Background glow top-right
            Positioned(
              top: -100,
              right: -80,
              child: Container(
                width: dp(350),
                height: dp(350),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF0072FF).withOpacity(0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Background glow bottom-left
            Positioned(
              bottom: -60,
              left: -60,
              child: Container(
                width: dp(280),
                height: dp(280),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF00C6FF).withOpacity(0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Main content
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 0 : dp(24),
                  vertical: dp(40),
                ),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Logo + Title
                            Center(
                              child: Column(
                                children: [
                                  Container(
                                    width: dp(68),
                                    height: dp(68),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF00C6FF),
                                          Color(0xFF0072FF),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(dp(18)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF0072FF)
                                              .withOpacity(0.4),
                                          blurRadius: dp(24),
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.bolt_rounded,
                                      color: Colors.white,
                                      size: dp(34),
                                    ),
                                  ),
                                  SizedBox(height: dp(18)),
                                  Text(
                                    'SkyFit Pro',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: sp(28),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  SizedBox(height: dp(5)),
                                  Text(
                                    'Your weather-aware fitness companion',
                                    style: TextStyle(
                                      color: const Color(0xFF8888AA),
                                      fontSize: sp(13),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(height: dp(32)),

                            // Login card
                            Container(
                              padding: EdgeInsets.all(dp(24)),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F0F1E),
                                borderRadius: BorderRadius.circular(dp(22)),
                                border: Border.all(
                                  color: const Color(0xFF1E1E30),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.4),
                                    blurRadius: dp(30),
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome back',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: sp(20),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: dp(3)),
                                  Text(
                                    'Sign in to continue',
                                    style: TextStyle(
                                      color: const Color(0xFF8888AA),
                                      fontSize: sp(12),
                                    ),
                                  ),
                                  SizedBox(height: dp(24)),

                                  // Email field
                                  SkyTextField(
                                    label: 'EMAIL',
                                    controller: _emailCtrl,
                                    hint: 'your@email.com',
                                    prefixIcon: Icons.mail_outline_rounded,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    textInputAction: TextInputAction.next,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Email is required';
                                      }
                                      if (!RegExp(
                                              r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$')
                                          .hasMatch(v.trim())) {
                                        return 'Enter a valid email';
                                      }
                                      return null;
                                    },
                                  ),
                                  SizedBox(height: dp(16)),

                                  // Password field
                                  SkyTextField(
                                    label: 'PASSWORD',
                                    controller: _passwordCtrl,
                                    hint: '••••••••',
                                    prefixIcon: Icons.lock_outline_rounded,
                                    isPassword: true,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _onEmailLogin(),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Password is required';
                                      }
                                      return null;
                                    },
                                  ),

                                  SizedBox(height: dp(8)),

                                  // Forgot password
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _showForgotPassword,
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          color: const Color(0xFF00C6FF),
                                          fontSize: sp(12),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),

                                  SizedBox(height: dp(20)),

                                  // Sign In button
                                  Consumer<AuthViewModel>(
                                    builder: (_, vm, __) => SkyButton(
                                      label: 'Sign In',
                                      onPressed: _onEmailLogin,
                                      isLoading: vm.isLoading,
                                    ),
                                  ),

                                  SizedBox(height: dp(14)),

                                  // Divider
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Divider(
                                            color: Color(0xFF2A2A3A)),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: dp(12)),
                                        child: Text(
                                          'or',
                                          style: TextStyle(
                                            color: const Color(0xFF555570),
                                            fontSize: sp(12),
                                          ),
                                        ),
                                      ),
                                      const Expanded(
                                        child: Divider(
                                            color: Color(0xFF2A2A3A)),
                                      ),
                                    ],
                                  ),

                                  SizedBox(height: dp(14)),

                                  // Google button
                                  Consumer<AuthViewModel>(
                                    builder: (_, vm, __) => SkyButton(
                                      label: 'Continue with Google',
                                      onPressed: _onGoogleLogin,
                                      variant: SkyButtonVariant.google,
                                      isLoading: vm.isLoading,
                                    ),
                                  ),

                                  // Biometrics section
                                  Consumer<AuthViewModel>(
                                    builder: (_, vm, __) {
                                      // Show forced-login banner when biometric
                                      // is locked out due to too many failures
                                      // or credential/session errors.
                                      if (vm.forcedPasswordLogin) {
                                        return Padding(
                                          padding: EdgeInsets.only(top: dp(14)),
                                          child: Container(
                                            width: double.infinity,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: dp(14),
                                              vertical: dp(10),
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFAA44)
                                                  .withOpacity(0.10),
                                              borderRadius:
                                                  BorderRadius.circular(dp(10)),
                                              border: Border.all(
                                                color: const Color(0xFFFFAA44)
                                                    .withOpacity(0.35),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color:
                                                      const Color(0xFFFFAA44),
                                                  size: dp(16),
                                                ),
                                                SizedBox(width: dp(8)),
                                                Expanded(
                                                  child: Text(
                                                    // Provider-aware message —
                                                    // Google users have no password.
                                                    vm.isGoogleUser
                                                        ? 'Please sign in with Google to continue.'
                                                        : 'Please sign in with your password to continue.',
                                                    style: TextStyle(
                                                      color: const Color(
                                                          0xFFFFAA44),
                                                      fontSize: sp(11.5),
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      // Hide biometric button if not visible.
                                      if (!vm.biometricButtonVisible) {
                                        return const SizedBox.shrink();
                                      }

                                      final name = vm.lastLoggedInName;
                                      final label = (name != null &&
                                              name.trim().isNotEmpty)
                                          ? 'Continue as ${name.trim().split(' ').first}'
                                          : 'Use Biometrics';

                                      return Column(
                                        children: [
                                          SizedBox(height: dp(10)),
                                          if (vm.biometricFailCount > 0)
                                            Padding(
                                              padding: EdgeInsets.only(
                                                  bottom: dp(6)),
                                              child: Text(
                                                '${vm.biometricAttemptsRemaining} attempt${vm.biometricAttemptsRemaining == 1 ? '' : 's'} remaining',
                                                style: TextStyle(
                                                  color: const Color(
                                                      0xFFFFAA44),
                                                  fontSize: sp(11),
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          SkyButton(
                                            label: label,
                                            onPressed: _onBiometricLogin,
                                            variant: SkyButtonVariant.outlined,
                                            isLoading: vm.isLoading,
                                            icon: Icon(
                                              Icons.fingerprint_rounded,
                                              color: const Color(0xFF00C6FF),
                                              size: dp(20),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(height: dp(20)),

                            // Register link
                            Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Don't have an account? ",
                                    style: TextStyle(
                                      color: const Color(0xFF8888AA),
                                      fontSize: sp(13),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const RegisterView(),
                                      ),
                                    ),
                                    child: Text(
                                      'Sign Up',
                                      style: TextStyle(
                                        color: const Color(0xFF00C6FF),
                                        fontSize: sp(13),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Forgot Password dialog ────────────────────────────────────────────────

  void _showForgotPassword() {
    final emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1E1E30)),
        ),
        title: const Text(
          'Reset Password',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email to receive a password reset link.',
              style: TextStyle(
                color: Color(0xFF8888AA),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            SkyTextField(
              label: 'EMAIL',
              controller: emailCtrl,
              hint: 'your@email.com',
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF8888AA)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final vm = context.read<AuthViewModel>();
              final ok = await vm.sendPasswordReset(emailCtrl.text.trim());
              if (!mounted) return;
              if (ok) {
                SkySnackbar.success(
                    context, 'Reset email sent! Check your inbox.');
              } else {
                SkySnackbar.error(
                    context,
                    vm.errorMessage ?? 'Failed to send reset email.');
              }
            },
            child: const Text(
              'Send',
              style: TextStyle(
                color: Color(0xFF00C6FF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}