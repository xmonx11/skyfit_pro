import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/weather_model.dart';
import '../models/activity_model.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/user_viewmodel.dart';
import '../viewmodels/weather_viewmodel.dart';
import 'widgets/sky_button.dart';
import 'widgets/sky_snackbar.dart';
import 'auth/login_view.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  bool _isEditing = false;

  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  String? _editGoal;

  Timer? _suggestionDebounce;
  int? _lastPreviewAge;
  double? _lastPreviewWeight;
  double? _lastPreviewHeight;
  String? _lastPreviewGoal;

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
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _ageCtrl.addListener(_onProfileFieldChanged);
    _weightCtrl.addListener(_onProfileFieldChanged);
    _heightCtrl.addListener(_onProfileFieldChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthViewModel>().addListener(_onAuthStateChanged);
    });
  }

  @override
  void dispose() {
    context.read<AuthViewModel>().removeListener(_onAuthStateChanged);
    _suggestionDebounce?.cancel();
    _fadeCtrl.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _onAuthStateChanged() {
    if (!mounted) return;
    final status = context.read<AuthViewModel>().status;
    if (status == AuthStatus.unauthenticated ||
        status == AuthStatus.sessionExpired) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _startEditing() {
    final user = context.read<UserViewModel>().user;
    if (user == null) return;
    _nameCtrl.text = user.displayName;
    _ageCtrl.text = user.age.toString();
    _weightCtrl.text = user.weightKg.toString();
    _heightCtrl.text = user.heightCm.toString();
    _editGoal = user.fitnessGoal;

    _lastPreviewAge = user.age;
    _lastPreviewWeight = user.weightKg;
    _lastPreviewHeight = user.heightCm;
    _lastPreviewGoal = user.fitnessGoal;

    setState(() => _isEditing = true);
  }

  void _onProfileFieldChanged() {
    if (!_isEditing) return;

    _suggestionDebounce?.cancel();
    _suggestionDebounce = Timer(const Duration(milliseconds: 600), () {
      _maybeRefreshSuggestions();
      if (mounted) setState(() {});
    });

    if (mounted) setState(() {});
  }

  void _maybeRefreshSuggestions() {
    final age = int.tryParse(_ageCtrl.text.trim());
    final weight = double.tryParse(_weightCtrl.text.trim());
    final height = double.tryParse(_heightCtrl.text.trim());
    final goal = _editGoal;

    if (age == null || weight == null || height == null || height <= 0) return;

    final unchanged = age == _lastPreviewAge &&
        weight == _lastPreviewWeight &&
        height == _lastPreviewHeight &&
        goal == _lastPreviewGoal;
    if (unchanged) return;

    _lastPreviewAge = age;
    _lastPreviewWeight = weight;
    _lastPreviewHeight = height;
    _lastPreviewGoal = goal;

    final currentUser = context.read<UserViewModel>().user;
    if (currentUser == null) return;

    final previewUser = currentUser.copyWith(
      age: age,
      weightKg: weight,
      heightCm: height,
      fitnessGoal: goal,
      updatedAt: DateTime.now(),
    );

    context.read<WeatherViewModel>().refreshSuggestions(user: previewUser);
  }

  void _onGoalChanged(String? newGoal) {
    setState(() => _editGoal = newGoal);
    _suggestionDebounce?.cancel();
    _maybeRefreshSuggestions();
  }

  Future<void> _saveEdits() async {
    final uvm = context.read<UserViewModel>();
    final age = int.tryParse(_ageCtrl.text.trim());
    final weight = double.tryParse(_weightCtrl.text.trim());
    final height = double.tryParse(_heightCtrl.text.trim());

    if (_nameCtrl.text.trim().isEmpty) {
      SkySnackbar.error(context, 'Name cannot be empty.');
      return;
    }
    if (age == null || age < 10 || age > 100) {
      SkySnackbar.error(context, 'Please enter a valid age (10-100).');
      return;
    }
    if (weight == null || weight < 20 || weight > 300) {
      SkySnackbar.error(context, 'Please enter a valid weight (20-300 kg).');
      return;
    }
    if (height == null || height < 50 || height > 250) {
      SkySnackbar.error(context, 'Please enter a valid height (50-250 cm).');
      return;
    }

    final bmi = weight / ((height / 100) * (height / 100));
    final conflictMsg = _bmiGoalConflict(bmi, _editGoal);
    if (conflictMsg != null) {
      final proceed = await _showConfirmDialog(
        title: 'Goal Conflict Detected',
        message: '$conflictMsg\n\nDo you still want to save this goal?',
        confirmLabel: 'Save Anyway',
        isDanger: false,
      );
      if (!proceed || !mounted) return;
    }

    final ok = await uvm.updateProfile(
      displayName: _nameCtrl.text.trim(),
      age: age,
      weightKg: weight,
      heightCm: height,
      fitnessGoal: _editGoal,
    );

    if (!mounted) return;
    if (ok) {
      setState(() => _isEditing = false);
      SkySnackbar.success(context, 'Profile updated successfully.');
    } else {
      SkySnackbar.error(
          context, uvm.errorMessage ?? 'Failed to update profile.');
    }
  }

  Future<void> _onSignOut() async {
    final confirmed = await _showConfirmDialog(
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
      isDanger: true,
    );
    if (!confirmed || !mounted) return;

    await context.read<AuthViewModel>().signOut();

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDanger = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0F0F1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF1E1E30)),
            ),
            title: Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            content: Text(message,
                style: const TextStyle(
                    color: Color(0xFF8888AA), fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Color(0xFF8888AA))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  confirmLabel,
                  style: TextStyle(
                    color: isDanger
                        ? const Color(0xFFFF4757)
                        : const Color(0xFF00C6FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
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
        return 'Reduce weight first (BMI >= 30)';
      case 'Endurance':
        return bmi >= 30
            ? 'Not recommended — BMI Obese'
            : 'Not recommended — BMI Overweight';
      default:
        return '';
    }
  }

  String? _bmiGoalConflict(double bmi, String? goal) {
    if (goal == null || bmi <= 0) return null;

    if (bmi < 18.5 && goal == 'Weight Loss') {
      return 'Your BMI (${bmi.toStringAsFixed(1)}) is already Underweight. '
          'Setting "Weight Loss" as your goal may be unsafe. '
          'Consider "Muscle Gain" or "General Fitness" instead.';
    }
    if (bmi >= 30 && goal == 'Muscle Gain') {
      return 'Your BMI (${bmi.toStringAsFixed(1)}) is in the Obese range. '
          '"Muscle Gain" workouts can be intense. '
          'Consider starting with "Weight Loss" or "General Fitness" first.';
    }
    if (bmi >= 25 && bmi < 30 && goal == 'Endurance') {
      return 'Your BMI (${bmi.toStringAsFixed(1)}) is Overweight. '
          'High-endurance training may strain your joints. '
          'Consider "Weight Loss" or "General Fitness" first.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 0 : 20,
              vertical: 16,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        IconButton(
                          icon: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A28),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF2A2A3A)),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        if (!_isEditing)
                          IconButton(
                            icon: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A28),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFF2A2A3A)),
                              ),
                              child: const Icon(
                                Icons.edit_outlined,
                                color: Color(0xFF00C6FF),
                                size: 18,
                              ),
                            ),
                            onPressed: _startEditing,
                          ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Consumer<UserViewModel>(
                      builder: (_, uvm, __) {
                        final user = uvm.user;
                        if (user == null) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF00C6FF),
                            ),
                          );
                        }

                        return Column(
                          children: [
                            _buildAvatarCard(user),
                            const SizedBox(height: 20),
                            _buildBmiCard(user),
                            const SizedBox(height: 20),
                            _isEditing
                                ? _buildEditCard(uvm)
                                : _buildInfoCard(user),
                            const SizedBox(height: 20),
                            _buildBiometricToggle(),
                          
                            const SizedBox(height: 20),
                            Consumer<AuthViewModel>(
                              builder: (_, avm, __) => SkyButton(
                                label: 'Sign Out',
                                onPressed: _onSignOut,
                                variant: SkyButtonVariant.danger,
                                isLoading: avm.isLoading,
                                icon: const Icon(
                                  Icons.logout_rounded,
                                  color: Color(0xFFFF4757),
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarCard(user) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F0F1E), Color(0xFF12122A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1E1E30), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF00C6FF), Color(0xFF0072FF)]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0072FF).withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: user.photoUrl != null
                ? ClipOval(
                    child: Image.network(user.photoUrl!, fit: BoxFit.cover))
                : Center(
                    child: Text(
                      user.displayName.isNotEmpty
                          ? user.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(user.email,
                    style: const TextStyle(
                        color: Color(0xFF8888AA), fontSize: 13),
                    overflow: TextOverflow.ellipsis),
                if (user.fitnessGoal != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C6FF).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF00C6FF).withOpacity(0.3)),
                    ),
                    child: Text(user.fitnessGoal!,
                        style: const TextStyle(
                            color: Color(0xFF00C6FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBmiCard(user) {
    final bmi = user.bmi;
    final bmiStatus = _bmiStatus(bmi);
    final conflictMsg = _bmiGoalConflict(bmi, user.fitnessGoal as String?);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E1E30), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('BMI (Body Mass Index)',
              style: TextStyle(
                  color: Color(0xFF8888AA),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(bmi.toStringAsFixed(1),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1)),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bmiStatus.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: bmiStatus.color.withOpacity(0.3)),
                  ),
                  child: Text(bmiStatus.label,
                      style: TextStyle(
                          color: bmiStatus.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (bmi.clamp(10, 40) - 10) / 30,
              backgroundColor: const Color(0xFF1E1E30),
              valueColor: AlwaysStoppedAnimation(bmiStatus.color),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 6),
          Text(bmiStatus.description,
              style: const TextStyle(
                  color: Color(0xFF555570), fontSize: 11)),
          if (conflictMsg != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4757).withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFFF4757).withOpacity(0.3),
                    width: 1.2),
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
                          conflictMsg,
                          style: const TextStyle(
                            color: Color(0xFFCC3344),
                            fontSize: 12,
                            height: 1.4,
                          ),
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
    );
  }

  Widget _buildInfoCard(user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E1E30), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FITNESS DATA',
              style: TextStyle(
                  color: Color(0xFF8888AA),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 16),
          _InfoRow(
              icon: Icons.cake_outlined,
              label: 'Age',
              value: '${user.age} years'),
          const _Divider(),
          _InfoRow(
              icon: Icons.monitor_weight_outlined,
              label: 'Weight',
              value: '${user.weightKg} kg'),
          const _Divider(),
          _InfoRow(
              icon: Icons.height_rounded,
              label: 'Height',
              value: '${user.heightCm} cm'),
          const _Divider(),
          _InfoRow(
              icon: Icons.flag_outlined,
              label: 'Goal',
              value: user.fitnessGoal ?? 'Not set'),
        ],
      ),
    );
  }

  Widget _buildEditCard(UserViewModel uvm) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFF00C6FF).withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF00C6FF).withOpacity(0.06),
              blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('EDIT PROFILE',
              style: TextStyle(
                  color: Color(0xFF00C6FF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 16),

          _EditField(label: 'NAME', controller: _nameCtrl),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _EditField(
                  label: 'AGE',
                  controller: _ageCtrl,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _EditField(
                  label: 'WEIGHT (KG)',
                  controller: _weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _EditField(
            label: 'HEIGHT (CM)',
            controller: _heightCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 14),

          _buildBmiPreview(),
          const SizedBox(height: 14),

          const Text('FITNESS GOAL',
              style: TextStyle(
                  color: Color(0xFF8888AA),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),

          Builder(builder: (_) {
            final w = double.tryParse(_weightCtrl.text);
            final h = double.tryParse(_heightCtrl.text);
            final double? bmi = (w != null && h != null && h > 0)
                ? w / ((h / 100) * (h / 100))
                : null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF12121E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2A2A3A)),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _editGoal,
                    dropdownColor: const Color(0xFF12121E),
                    style: const TextStyle(
                        color: Color(0xFFE0E0F0), fontSize: 14),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF555570)),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    hint: Text('Select goal',
                        style: TextStyle(
                            color:
                                const Color(0xFF8888AA).withOpacity(0.6))),
                    items: _goals.map((g) {
                      final disabled =
                          bmi != null ? _isGoalDisabled(g, bmi) : false;

                      return DropdownMenuItem<String>(
                        value: g,
                        enabled: !disabled,
                        child: Text(
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
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) _onGoalChanged(v);
                    },
                  ),
                ),

                if (_editGoal != null &&
                    bmi != null &&
                    _isGoalDisabled(_editGoal!, bmi)) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4757).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFFF4757).withOpacity(0.3),
                          width: 1.2),
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
                                _goalDisabledReason(_editGoal!, bmi),
                                style: const TextStyle(
                                  color: Color(0xFFCC3344),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          }),

          const SizedBox(height: 12),
          _buildSuggestionHint(),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: SkyButton(
                  label: 'Cancel',
                  onPressed: () {
                    _suggestionDebounce?.cancel();
                    final savedUser = context.read<UserViewModel>().user;
                    if (savedUser != null) {
                      context
                          .read<WeatherViewModel>()
                          .refreshSuggestions(user: savedUser);
                    }
                    setState(() => _isEditing = false);
                  },
                  variant: SkyButtonVariant.outlined,
                  height: 44,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Consumer<UserViewModel>(
                  builder: (_, uvm, __) => SkyButton(
                    label: 'Save',
                    onPressed: _saveEdits,
                    isLoading: uvm.isUpdating,
                    height: 44,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBmiPreview() {
    final weight = double.tryParse(_weightCtrl.text.trim());
    final height = double.tryParse(_heightCtrl.text.trim());

    if (weight == null || height == null || height <= 0) {
      return const SizedBox.shrink();
    }

    final bmi = weight / ((height / 100) * (height / 100));
    final bmiStatus = _bmiStatus(bmi);
    final conflictMsg = _bmiGoalConflict(bmi, _editGoal);

    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bmiStatus.color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: bmiStatus.color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.monitor_heart_outlined,
                  color: bmiStatus.color, size: 16),
              const SizedBox(width: 8),
              Text(
                'BMI Preview: ${bmi.toStringAsFixed(1)}',
                style: TextStyle(
                    color: bmiStatus.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: bmiStatus.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(bmiStatus.label,
                    style: TextStyle(
                        color: bmiStatus.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        if (conflictMsg != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4757).withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFFF4757).withOpacity(0.3),
                  width: 1.2),
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
                        conflictMsg,
                        style: const TextStyle(
                          color: Color(0xFFCC3344),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSuggestionHint() {
    final age = int.tryParse(_ageCtrl.text.trim());
    final weight = double.tryParse(_weightCtrl.text.trim());
    final height = double.tryParse(_heightCtrl.text.trim());

    if (age == null || weight == null || height == null || height <= 0) {
      return const SizedBox.shrink();
    }

    final bmi = weight / ((height / 100) * (height / 100));
    final isElderly = age >= 50;
    final isOverweight = bmi >= 25;

    final weather = context.read<WeatherViewModel>().weather;
    String hint;
    Color hintColor;

    if (weather == null) {
      hint = 'Load weather on Home to see activity suggestions.';
      hintColor = const Color(0xFF555570);
    } else if (weather.temperatureCelsius >= 35 && isOverweight) {
      hint = 'Suggestions: Swimming / Light Stretching (extreme heat + overweight)';
      hintColor = const Color(0xFFFF6B6B);
    } else if (weather.category == WeatherCategory.rain ||
        weather.category == WeatherCategory.snow ||
        weather.category == WeatherCategory.thunderstorm ||
        weather.category == WeatherCategory.atmosphere) {
      hint = 'Suggestions: Indoor Yoga / Bodyweight Circuit (indoor weather)';
      hintColor = const Color(0xFF00C6FF);
    } else if (isElderly) {
      hint = 'Suggestions: Morning Walk / Tai Chi (age 50+)';
      hintColor = const Color(0xFF2ECC71);
    } else if (!isOverweight) {
      hint = 'Suggestions: Outdoor Run / HIIT (normal BMI, clear weather)';
      hintColor = const Color(0xFF2ECC71);
    } else {
      hint = 'Suggestions: Morning Walk / Outdoor Yoga (overweight, clear weather)';
      hintColor = const Color(0xFFFFA502);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: hintColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: hintColor.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              color: hintColor, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(hint,
                style:
                    TextStyle(color: hintColor, fontSize: 11, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E1E30), width: 1.5),
      ),
      child: Consumer<AuthViewModel>(
        builder: (_, avm, __) {
          final hardwareAvailable = avm.biometricsAvailable;
          final isEnabled = avm.biometricLoginEnabled;

          return Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hardwareAvailable
                      ? const Color(0xFF00C6FF).withOpacity(0.1)
                      : const Color(0xFF555570).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.fingerprint_rounded,
                    color: hardwareAvailable
                        ? const Color(0xFF00C6FF)
                        : const Color(0xFF555570),
                    size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Biometric Login',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    Text(
                      !hardwareAvailable
                          ? 'Not available on this device'
                          : isEnabled
                              ? 'Fingerprint / Face ID enabled'
                              : 'Tap to enable Fingerprint / Face ID',
                      style: const TextStyle(
                          color: Color(0xFF8888AA), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: hardwareAvailable
                    ? (val) async {
                        await avm.setBiometricLoginEnabled(val);
                        if (!mounted) return;
                        SkySnackbar.info(
                          context,
                          val
                              ? 'Biometric login enabled.'
                              : 'Biometric login disabled.',
                        );
                      }
                    : null,
                activeColor: const Color(0xFF00C6FF),
                activeTrackColor:
                    const Color(0xFF00C6FF).withOpacity(0.3),
                inactiveThumbColor: const Color(0xFF555570),
                inactiveTrackColor: const Color(0xFF1E1E30),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Dark Mode Toggle ───────────────────────────────────────────────────────

  Widget _buildDarkModeToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E1E30), width: 1.5),
      ),
      child: Consumer<UserViewModel>(
        builder: (_, uvm, __) => Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF00C6FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                uvm.isDarkMode
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                color: const Color(0xFF00C6FF),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Light Mode',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    uvm.isDarkMode
                        ? 'Light mode enabled'
                        : 'Dark mode enabled',
                    style: const TextStyle(
                        color: Color(0xFF8888AA), fontSize: 12),
                  ),
                ],
              ),
            ),
            Switch(
              value: uvm.isDarkMode,
              onChanged: (val) => uvm.toggleDarkMode(val),
              activeColor: const Color(0xFF00C6FF),
              activeTrackColor: const Color(0xFF00C6FF).withOpacity(0.3),
              inactiveThumbColor: const Color(0xFF555570),
              inactiveTrackColor: const Color(0xFF1E1E30),
            ),
          ],
        ),
      ),
    );
  }

  _BmiStatus _bmiStatus(double bmi) {
    if (bmi < 18.5) {
      return _BmiStatus(
          label: 'Underweight',
          color: const Color(0xFF00C6FF),
          description:
              'Consider a nutrition plan to gain healthy weight.');
    } else if (bmi < 25) {
      return _BmiStatus(
          label: 'Normal',
          color: const Color(0xFF2ECC71),
          description: 'Great! Maintain your current lifestyle.');
    } else if (bmi < 30) {
      return _BmiStatus(
          label: 'Overweight',
          color: const Color(0xFFFFA502),
          description: 'Some cardio and diet adjustments recommended.');
    } else {
      return _BmiStatus(
          label: 'Obese',
          color: const Color(0xFFFF4757),
          description:
              'Consult a healthcare provider for a fitness plan.');
    }
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF555570), size: 18),
          const SizedBox(width: 12),
          Text(label,
              style:
                  const TextStyle(color: Color(0xFF8888AA), fontSize: 14)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(color: Color(0xFF1E1E30), height: 1);
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF8888AA),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF12121E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2A2A3A)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(
                color: Color(0xFFE0E0F0), fontSize: 14),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _BmiStatus {
  final String label;
  final Color color;
  final String description;
  const _BmiStatus(
      {required this.label,
      required this.color,
      required this.description});
}