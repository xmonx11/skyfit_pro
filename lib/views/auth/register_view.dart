import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/auth_viewmodel.dart';
import '../widgets/sky_button.dart';
import '../widgets/sky_text_field.dart';
import '../widgets/sky_snackbar.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  String? _selectedGoal;
  String? _weightError;
  String? _heightError;
  String? _ageError;

  final List<String> _goals = [
    'Weight Loss',
    'Muscle Gain',
    'Endurance',
    'Flexibility',
    'General Fitness',
  ];

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  double _passwordStrength = 0;
  String _passwordStrengthLabel = '';
  Color _passwordStrengthColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _fadeCtrl.forward();
    _passwordCtrl.addListener(_evaluatePassword);
    _weightCtrl.addListener(_onBiometricChanged);
    _heightCtrl.addListener(_onBiometricChanged);
    _ageCtrl.addListener(_onAgeChanged);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _onAgeChanged() {
    final text = _ageCtrl.text;
    if (text.isEmpty) {
      setState(() => _ageError = null);
      return;
    }
    final age = int.tryParse(text);
    setState(() {
      if (age == null) {
        _ageError = 'Invalid number';
      } else if (age < 10 || age > 100) {
        _ageError = 'Must be 10–100';
      } else {
        _ageError = null;
      }
    });
  }

  void _onBiometricChanged() {
    final wText = _weightCtrl.text;
    final hText = _heightCtrl.text;
    final w = double.tryParse(wText);
    final h = double.tryParse(hText);

    String? weightErr;
    String? heightErr;

    if (wText.isNotEmpty) {
      if (w == null) {
        weightErr = 'Invalid number';
      } else if (w < 30 || w > 300) {
        weightErr = 'Must be 30–300 kg';
      }
    }

    if (hText.isNotEmpty) {
      if (h == null) {
        heightErr = 'Invalid number';
      } else if (h < 100 || h > 250) {
        heightErr = 'Must be 100–250 cm';
      }
    }

    final double? bmi =
        (w != null && h != null && h > 0 && weightErr == null && heightErr == null)
            ? w / ((h / 100) * (h / 100))
            : null;

    // Auto-clear selected goal if it becomes invalid with new BMI
    if (_selectedGoal != null &&
        bmi != null &&
        _isGoalDisabled(_selectedGoal!, bmi)) {
      _selectedGoal = null;
    }

    setState(() {
      _weightError = weightErr;
      _heightError = heightErr;
    });
  }

  void _evaluatePassword() {
    final p = _passwordCtrl.text;
    double strength = 0;
    if (p.length >= 8) strength += 0.25;
    if (p.contains(RegExp(r'[A-Z]'))) strength += 0.25;
    if (p.contains(RegExp(r'[0-9]'))) strength += 0.25;
    if (p.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) strength += 0.25;

    String label;
    Color color;
    if (strength <= 0.25) {
      label = 'Weak';
      color = const Color(0xFFFF4757);
    } else if (strength <= 0.5) {
      label = 'Fair';
      color = const Color(0xFFFFA502);
    } else if (strength <= 0.75) {
      label = 'Good';
      color = const Color(0xFF00C6FF);
    } else {
      label = 'Strong';
      color = const Color(0xFF2ECC71);
    }

    setState(() {
      _passwordStrength = strength;
      _passwordStrengthLabel = p.isEmpty ? '' : label;
      _passwordStrengthColor = color;
    });
  }

  bool _isGoalDisabled(String goal, double bmi) {
    switch (goal) {
      case 'Weight Loss':
        return bmi < 18.5;
      case 'Muscle Gain':
        return bmi >= 30;
      case 'Endurance':
        return bmi >= 25;
      default:
        return false;
    }
  }

  String _goalDisabledReason(String goal, double bmi) {
    switch (goal) {
      case 'Weight Loss':
        return 'Not safe — BMI already Underweight';
      case 'Muscle Gain':
        return 'Reduce weight first (BMI ≥ 30)';
      case 'Endurance':
        return bmi >= 30
            ? 'Not recommended — BMI Obese'
            : 'Not recommended — BMI Overweight';
      default:
        return '';
    }
  }

  double? get _currentBmi {
    final w = double.tryParse(_weightCtrl.text);
    final h = double.tryParse(_heightCtrl.text);
    if (w == null || h == null || h <= 0) return null;
    if (_weightError != null || _heightError != null) return null;
    if (w < 30 || w > 300 || h < 100 || h > 250) return null;
    return w / ((h / 100) * (h / 100));
  }

  Future<void> _goToLogin() async {
    final vm = context.read<AuthViewModel>();
    if (vm.isAuthenticated) await vm.signOut();
    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _showAlreadyExistsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1E1E30)),
        ),
        title: const Text(
          'Email Already Registered',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'This email is already linked to an account. Would you like to sign in instead?',
          style: TextStyle(color: Color(0xFF8888AA), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Stay Here',
              style: TextStyle(color: Color(0xFF8888AA)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _goToLogin();
            },
            child: const Text(
              'Sign In',
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

  Future<void> _onRegister() async {
    // Trigger real-time validators before submit check
    _onAgeChanged();
    _onBiometricChanged();

    if (!_formKey.currentState!.validate()) return;
    if (_weightError != null || _heightError != null || _ageError != null) return;

    final vm = context.read<AuthViewModel>();
    final ok = await vm.registerWithEmail(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      age: int.parse(_ageCtrl.text.trim()),
      weightKg: double.parse(_weightCtrl.text.trim()),
      heightCm: double.parse(_heightCtrl.text.trim()),
      fitnessGoal: _selectedGoal,
    );

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      final msg = vm.errorMessage ?? 'Registration failed.';
      debugPrint('REGISTER ERROR: $msg');
      SkySnackbar.error(context, msg);
      if (msg.toLowerCase().contains('already in use') ||
          msg.toLowerCase().contains('already exists')) {
        _showAlreadyExistsDialog();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    final currentBmi = _currentBmi;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: Stack(
        children: [
          // Background glows
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF00C6FF).withOpacity(0.10),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF0072FF).withOpacity(0.10),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: IconButton(
                icon: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A28),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2A2A3A)),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                onPressed: _goToLogin,
              ),
            ),
          ),

          // Main scrollable content
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 0 : 24,
                vertical: 80,
              ),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          const Center(
                            child: Column(
                              children: [
                                Text(
                                  'Create Account',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Start your fitness journey today',
                                  style: TextStyle(
                                    color: Color(0xFF8888AA),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // ── PERSONAL INFO ──────────────────────────────
                          const _SectionLabel(label: 'PERSONAL INFO'),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: _cardDecor(),
                            child: Column(
                              children: [
                                SkyTextField(
                                  label: 'FULL NAME',
                                  controller: _nameCtrl,
                                  hint: 'Juan dela Cruz',
                                  prefixIcon: Icons.person_outline_rounded,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Name is required';
                                    }
                                    if (v.trim().length < 2) {
                                      return 'At least 2 characters';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                SkyTextField(
                                  label: 'EMAIL',
                                  controller: _emailCtrl,
                                  hint: 'your@email.com',
                                  prefixIcon: Icons.mail_outline_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
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
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ── SECURITY ───────────────────────────────────
                          const _SectionLabel(label: 'SECURITY'),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: _cardDecor(),
                            child: Column(
                              children: [
                                SkyTextField(
                                  label: 'PASSWORD',
                                  controller: _passwordCtrl,
                                  hint: '••••••••',
                                  prefixIcon: Icons.lock_outline_rounded,
                                  isPassword: true,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Password is required';
                                    }
                                    if (v.length < 8) {
                                      return 'Min 8 characters';
                                    }
                                    if (!RegExp(r'[A-Z]').hasMatch(v)) {
                                      return 'Need at least 1 uppercase letter';
                                    }
                                    if (!RegExp(r'[0-9]').hasMatch(v)) {
                                      return 'Need at least 1 number';
                                    }
                                    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]')
                                        .hasMatch(v)) {
                                      return 'Need at least 1 special character';
                                    }
                                    return null;
                                  },
                                ),
                                if (_passwordCtrl.text.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: _passwordStrength,
                                            backgroundColor:
                                                const Color(0xFF1E1E30),
                                            valueColor:
                                                AlwaysStoppedAnimation(
                                              _passwordStrengthColor,
                                            ),
                                            minHeight: 4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _passwordStrengthLabel,
                                        style: TextStyle(
                                          color: _passwordStrengthColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 16),
                                SkyTextField(
                                  label: 'CONFIRM PASSWORD',
                                  controller: _confirmCtrl,
                                  hint: '••••••••',
                                  prefixIcon: Icons.lock_outline_rounded,
                                  isPassword: true,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Please confirm your password';
                                    }
                                    if (v != _passwordCtrl.text) {
                                      return 'Passwords do not match';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ── FITNESS PROFILE ────────────────────────────
                          const _SectionLabel(label: 'FITNESS PROFILE'),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: _cardDecor(),
                            child: Column(
                              children: [
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: SkyTextField(
                                        label: 'AGE',
                                        controller: _ageCtrl,
                                        hint: '25',
                                        prefixIcon: Icons.cake_outlined,
                                        keyboardType: TextInputType.number,
                                        errorText: _ageError,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(3),
                                        ],
                                        validator: (v) {
                                          if (v == null || v.isEmpty) {
                                            return 'Required';
                                          }
                                          final age = int.tryParse(v);
                                          if (age == null ||
                                              age < 10 ||
                                              age > 100) {
                                            return 'Must be 10–100';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: SkyTextField(
                                        label: 'WEIGHT (KG)',
                                        controller: _weightCtrl,
                                        hint: '70.0',
                                        prefixIcon:
                                            Icons.monitor_weight_outlined,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        errorText: _weightError,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d{0,3}\.?\d{0,1}$'),
                                          ),
                                          LengthLimitingTextInputFormatter(5),
                                        ],
                                        validator: (v) {
                                          if (v == null || v.isEmpty) {
                                            return 'Required';
                                          }
                                          final wv = double.tryParse(v);
                                          if (wv == null ||
                                              wv < 30 ||
                                              wv > 300) {
                                            return '30–300 kg';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SkyTextField(
                                  label: 'HEIGHT (CM)',
                                  controller: _heightCtrl,
                                  hint: '170',
                                  prefixIcon: Icons.straighten_rounded,
                                  keyboardType: const TextInputType
                                      .numberWithOptions(decimal: true),
                                  errorText: _heightError,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d{0,3}\.?\d{0,1}$'),
                                    ),
                                    LengthLimitingTextInputFormatter(5),
                                  ],
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Required';
                                    }
                                    final hv = double.tryParse(v);
                                    if (hv == null || hv < 100 || hv > 250) {
                                      return '100–250 cm';
                                    }
                                    return null;
                                  },
                                ),

                                // BMI Preview — only shows when values are valid
                                if (currentBmi != null)
                                  _BmiPreview(
                                    weightKg: double.parse(_weightCtrl.text),
                                    heightCm: double.parse(_heightCtrl.text),
                                    fitnessGoal: _selectedGoal,
                                  ),

                                const SizedBox(height: 16),

                                // ── Fitness Goal Dropdown
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'FITNESS GOAL',
                                      style: TextStyle(
                                        color: Color(0xFF8888AA),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Theme(
                                      data: Theme.of(context).copyWith(
                                        canvasColor:
                                            const Color(0xFF12121E),
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF12121E),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: const Color(0xFF2A2A3A),
                                          ),
                                        ),
                                        child: DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          value: _selectedGoal,
                                          hint: Text(
                                            'Select your goal (optional)',
                                            style: TextStyle(
                                              color: const Color(0xFF8888AA)
                                                  .withOpacity(0.6),
                                              fontSize: 14,
                                            ),
                                          ),
                                          dropdownColor:
                                              const Color(0xFF12121E),
                                          style: const TextStyle(
                                            color: Color(0xFFE0E0F0),
                                            fontSize: 14,
                                          ),
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            color: Color(0xFF555570),
                                          ),
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            prefixIcon: Icon(
                                              Icons.flag_outlined,
                                              color: Color(0xFF555570),
                                              size: 20,
                                            ),
                                          ),
                                          items: _goals.map((g) {
                                            final disabled = currentBmi != null
                                                ? _isGoalDisabled(g, currentBmi)
                                                : false;
                                            final reason =
                                                currentBmi != null && disabled
                                                    ? _goalDisabledReason(
                                                        g, currentBmi)
                                                    : null;

                                            return DropdownMenuItem<String>(
                                              value: g,
                                              enabled: !disabled,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    disabled
                                                        ? Icons.block_rounded
                                                        : Icons
                                                            .check_circle_outline_rounded,
                                                    size: 15,
                                                    color: disabled
                                                        ? const Color(
                                                            0xFF555570)
                                                        : const Color(
                                                            0xFF00C6FF),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          g,
                                                          style: TextStyle(
                                                            color: disabled
                                                                ? const Color(
                                                                    0xFF555570)
                                                                : const Color(
                                                                    0xFFE0E0F0),
                                                            fontSize: 14,
                                                            fontWeight: disabled
                                                                ? FontWeight
                                                                    .normal
                                                                : FontWeight
                                                                    .w500,
                                                          ),
                                                        ),
                                                        if (reason != null)
                                                          Text(
                                                            reason,
                                                            style:
                                                                const TextStyle(
                                                              color: Color(
                                                                  0xFF555570),
                                                              fontSize: 10,
                                                              height: 1.3,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (v) =>
                                              setState(() => _selectedGoal = v),
                                        ),
                                      ),
                                    ),

                                    // Warning box for not-recommended selected goal
                                    if (_selectedGoal != null &&
                                        currentBmi != null &&
                                        _isGoalDisabled(
                                            _selectedGoal!, currentBmi)) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF4757)
                                              .withOpacity(0.06),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: const Color(0xFFFF4757)
                                                .withOpacity(0.35),
                                            width: 1.2,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.info_outline_rounded,
                                              color: Color(0xFFFF4757),
                                              size: 18,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Goal Not Recommended',
                                                    style: TextStyle(
                                                      color: Color(0xFFFF4757),
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _goalDisabledReason(
                                                      _selectedGoal!,
                                                      currentBmi,
                                                    ),
                                                    style: const TextStyle(
                                                      color: Color(0xFFCC3344),
                                                      fontSize: 13,
                                                      height: 1.4,
                                                    ),
                                                    softWrap: true,
                                                    overflow:
                                                        TextOverflow.visible,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 28),

                          Consumer<AuthViewModel>(
                            builder: (_, vm, __) => SkyButton(
                              label: 'Create Account',
                              onPressed: _onRegister,
                              isLoading: vm.isLoading,
                            ),
                          ),

                          const SizedBox(height: 20),

                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Already have an account? ',
                                  style: TextStyle(
                                    color: Color(0xFF8888AA),
                                    fontSize: 14,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _goToLogin,
                                  child: const Text(
                                    'Sign In',
                                    style: TextStyle(
                                      color: Color(0xFF00C6FF),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 40),
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
    );
  }

  BoxDecoration _cardDecor() => BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E1E30), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );
}

// ── BMI Preview ───────────────────────────────────────────────────────────────

class _BmiPreview extends StatelessWidget {
  const _BmiPreview({
    required this.weightKg,
    required this.heightCm,
    this.fitnessGoal,
  });

  final double weightKg;
  final double heightCm;
  final String? fitnessGoal;

  @override
  Widget build(BuildContext context) {
    if (heightCm <= 0 || weightKg <= 0) return const SizedBox.shrink();

    final heightM = heightCm / 100;
    final bmi = weightKg / (heightM * heightM);

    if (bmi > 60 || bmi < 10) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF4757).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFFF4757).withOpacity(0.3),
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.error_outline, color: Color(0xFFFF4757), size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'BMI result seems incorrect. Please check your values.',
                style: TextStyle(color: Color(0xFFFF4757), fontSize: 12),
                softWrap: true,
              ),
            ),
          ],
        ),
      );
    }

    final String category;
    final Color color;

    if (bmi < 18.5) {
      category = 'Underweight';
      color = const Color(0xFF00C6FF);
    } else if (bmi < 25.0) {
      category = 'Normal';
      color = const Color(0xFF2ECC71);
    } else if (bmi < 30.0) {
      category = 'Overweight';
      color = const Color(0xFFFFA502);
    } else {
      category = 'Obese';
      color = const Color(0xFFFF4757);
    }

    final hint = _activityHint(bmi, fitnessGoal);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                'BMI: ${bmi.toStringAsFixed(1)}',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  category,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                hint,
                style: const TextStyle(
                  color: Color(0xFF8888AA),
                  fontSize: 11,
                  height: 1.4,
                ),
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _activityHint(double bmi, String? goal) {
    switch (goal) {
      case 'Weight Loss':
        if (bmi < 18.5) return 'Too lean to cut';
        if (bmi < 25.0) return 'Light cardio + diet';
        if (bmi < 30.0) return 'Cardio + calorie deficit';
        return 'Start with walking';
      case 'Muscle Gain':
        if (bmi < 18.5) return 'Eat more + lift weights';
        if (bmi < 25.0) return 'Ideal for bulking';
        if (bmi < 30.0) return 'Lean bulk recommended';
        return 'Cardio first, then lift';
      case 'Endurance':
        if (bmi < 18.5) return 'Increase calorie intake first';
        if (bmi < 25.0) return 'Long-distance cardio';
        if (bmi < 30.0) return 'Try swimming';
        return 'Build base fitness first';
      case 'Flexibility':
        if (bmi < 18.5) return 'Yoga + nutrition focus';
        if (bmi < 25.0) return 'Stretching + mobility';
        if (bmi < 30.0) return 'Yoga + light cardio';
        return 'Warm up + gentle stretching';
      case 'General Fitness':
        if (bmi < 18.5) return 'Build strength first';
        if (bmi < 25.0) return 'Keep it up!';
        if (bmi < 30.0) return 'Try swimming';
        return 'Start with gentle exercise';
      default:
        if (bmi < 18.5) return 'Build strength';
        if (bmi < 25.0) return 'Keep it up!';
        if (bmi < 30.0) return 'Try swimming';
        return 'Start with gentle exercise';
    }
  }
}

// ── Section Label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8888AA),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}