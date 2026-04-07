import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/user_viewmodel.dart';
import '../widgets/sky_button.dart';
import '../widgets/sky_text_field.dart';
import '../widgets/sky_snackbar.dart';

/// Shown after Google Sign-In (or any auth path) when
/// [UserModel.isProfileComplete] is false.
/// Saves age, weightKg, heightCm, fitnessGoal → Firestore,
/// then sets isProfileComplete: true → AuthGate rebuilds → HomeView shown.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  String? _selectedGoal;
  String? _ageError;
  String? _weightError;
  String? _heightError;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final List<String> _goals = [
    'Weight Loss',
    'Muscle Gain',
    'Endurance',
    'Flexibility',
    'General Fitness',
  ];

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

    _ageCtrl.addListener(_onAgeChanged);
    _weightCtrl.addListener(_onBiometricChanged);
    _heightCtrl.addListener(_onBiometricChanged);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  // ── Real-time validators ──────────────────────────────────────────────────

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

    final bmi = (w != null && h != null && h > 0 && weightErr == null && heightErr == null)
        ? w / ((h / 100) * (h / 100))
        : null;
    if (_selectedGoal != null && bmi != null && _isGoalDisabled(_selectedGoal!, bmi)) {
      _selectedGoal = null;
    }

    setState(() {
      _weightError = weightErr;
      _heightError = heightErr;
    });
  }

  // ── BMI helpers ───────────────────────────────────────────────────────────

  double? get _currentBmi {
    final w = double.tryParse(_weightCtrl.text);
    final h = double.tryParse(_heightCtrl.text);
    if (w == null || h == null || h <= 0) return null;
    if (_weightError != null || _heightError != null) return null;
    if (w < 30 || w > 300 || h < 100 || h > 250) return null;
    return w / ((h / 100) * (h / 100));
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

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _onContinue() async {
    _onAgeChanged();
    _onBiometricChanged();

    if (!_formKey.currentState!.validate()) return;
    if (_ageError != null || _weightError != null || _heightError != null) return;

    final uvm = context.read<UserViewModel>();

    // ← isProfileComplete: true marks onboarding as done
    // AuthGate will rebuild automatically via Firestore stream → HomeView
    final ok = await uvm.updateProfile(
      displayName: uvm.user?.displayName ?? '',
      age: int.parse(_ageCtrl.text.trim()),
      weightKg: double.parse(_weightCtrl.text.trim()),
      heightCm: double.parse(_heightCtrl.text.trim()),
      fitnessGoal: _selectedGoal,
      isProfileComplete: true, // ← IMPORTANT: this triggers AuthGate to show HomeView
    );

    if (!mounted) return;

    if (!ok) {
      SkySnackbar.error(context, uvm.errorMessage ?? 'Failed to save profile.');
    }
    // No navigation needed — AuthGate listens to UserViewModel stream
    // and will automatically switch to HomeView once isProfileComplete = true
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    final currentBmi = _currentBmi;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: Stack(
        children: [
          // Background glow — top left
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
          // Background glow — bottom right
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

          // Main content
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
                          // ── Header ──────────────────────────────────────
                          Center(
                            child: Column(
                              children: [
                                // Logo
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF00C6FF),
                                        Color(0xFF0072FF),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF0072FF)
                                            .withOpacity(0.4),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.bolt_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Complete Your Profile',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Help us personalise your fitness experience',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF8888AA),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // ── Step indicator ───────────────────────────────
                          _StepIndicator(currentStep: 1, totalSteps: 1),

                          const SizedBox(height: 24),

                          // ── FITNESS PROFILE card ─────────────────────────
                          _SectionLabel(label: 'FITNESS PROFILE'),
                          const SizedBox(height: 12),

                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: _cardDecor(),
                            child: Column(
                              children: [
                                // Age + Weight row
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(3),
                                        ],
                                        validator: (v) {
                                          if (v == null || v.isEmpty) return 'Required';
                                          final age = int.tryParse(v);
                                          if (age == null || age < 10 || age > 100) {
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
                                        prefixIcon: Icons.monitor_weight_outlined,
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
                                          if (v == null || v.isEmpty) return 'Required';
                                          final wv = double.tryParse(v);
                                          if (wv == null || wv < 30 || wv > 300) {
                                            return '30–300 kg';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Height
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
                                    if (v == null || v.isEmpty) return 'Required';
                                    final hv = double.tryParse(v);
                                    if (hv == null || hv < 100 || hv > 250) {
                                      return '100–250 cm';
                                    }
                                    return null;
                                  },
                                ),

                                // BMI Preview
                                if (currentBmi != null) ...[
                                  const SizedBox(height: 12),
                                  _BmiPreview(bmi: currentBmi),
                                ],

                                const SizedBox(height: 16),

                                // ── Fitness Goal dropdown ────────────────
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        canvasColor: const Color(0xFF12121E),
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF12121E),
                                          borderRadius: BorderRadius.circular(14),
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
                                          dropdownColor: const Color(0xFF12121E),
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
                                            contentPadding: EdgeInsets.symmetric(
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
                                            final reason = currentBmi != null && disabled
                                                ? _goalDisabledReason(g, currentBmi)
                                                : null;

                                            return DropdownMenuItem<String>(
                                              value: g,
                                              enabled: !disabled,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    disabled
                                                        ? Icons.block_rounded
                                                        : Icons.check_circle_outline_rounded,
                                                    size: 15,
                                                    color: disabled
                                                        ? const Color(0xFF555570)
                                                        : const Color(0xFF00C6FF),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          g,
                                                          style: TextStyle(
                                                            color: disabled
                                                                ? const Color(0xFF555570)
                                                                : const Color(0xFFE0E0F0),
                                                            fontSize: 14,
                                                            fontWeight: disabled
                                                                ? FontWeight.normal
                                                                : FontWeight.w500,
                                                          ),
                                                        ),
                                                        if (reason != null)
                                                          Text(
                                                            reason,
                                                            style: const TextStyle(
                                                              color: Color(0xFF555570),
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

                                    // Warning if disabled goal somehow selected
                                    if (_selectedGoal != null &&
                                        currentBmi != null &&
                                        _isGoalDisabled(_selectedGoal!, currentBmi)) ...[
                                      const SizedBox(height: 12),
                                      _GoalWarning(
                                        reason: _goalDisabledReason(
                                            _selectedGoal!, currentBmi),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── Continue button ──────────────────────────────
                          Consumer<UserViewModel>(
                            builder: (_, uvm, __) => SkyButton(
                              label: 'Continue to SkyFit Pro',
                              onPressed: _onContinue,
                              isLoading: uvm.isUpdating,
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Skip option — skips goal only, still needs age/weight/height
                          Center(
                            child: GestureDetector(
                              onTap: () async {
                                setState(() => _selectedGoal = null);
                                await _onContinue();
                              },
                              child: const Text(
                                'Skip for now',
                                style: TextStyle(
                                  color: Color(0xFF555570),
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Color(0xFF555570),
                                ),
                              ),
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
  const _BmiPreview({required this.bmi});
  final double bmi;

  @override
  Widget build(BuildContext context) {
    if (bmi > 60 || bmi < 10) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF4757).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFF4757).withOpacity(0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.error_outline, color: Color(0xFFFF4757), size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'BMI result seems incorrect. Please check your values.',
                style: TextStyle(color: Color(0xFFFF4757), fontSize: 12),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
    );
  }
}

// ── Goal Warning ──────────────────────────────────────────────────────────────

class _GoalWarning extends StatelessWidget {
  const _GoalWarning({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4757).withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF4757).withOpacity(0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFFF4757), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Goal Not Recommended',
                  style: TextStyle(
                    color: Color(0xFFFF4757),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: const TextStyle(
                    color: Color(0xFFCC3344),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step Indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.currentStep,
    required this.totalSteps,
  });
  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (i) {
        final active = i < currentStep;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < totalSteps - 1 ? 6 : 0),
            height: 4,
            decoration: BoxDecoration(
              gradient: active
                  ? const LinearGradient(
                      colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                    )
                  : null,
              color: active ? null : const Color(0xFF1E1E30),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
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