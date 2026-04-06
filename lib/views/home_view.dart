import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../models/weather_model.dart';
import '../models/activity_model.dart';
import '../models/user_model.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/user_viewmodel.dart';
import '../viewmodels/weather_viewmodel.dart';
import 'widgets/sky_snackbar.dart';
import 'profile_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  final TextEditingController _cityCtrl = TextEditingController();

  String? _inProgressActivityId;
  int _inProgressElapsed = 0;
  final Set<String> _completedActivityIds = {};

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialWeather());
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _loadInitialWeather() {
    final wvm = context.read<WeatherViewModel>();
    final uvm = context.read<UserViewModel>();
    if (!wvm.hasData) {
      wvm.fetchWeatherByCity('Manila', user: uvm.user);
    }
  }

  Future<void> _onRefresh() async {
    final wvm = context.read<WeatherViewModel>();
    final uvm = context.read<UserViewModel>();
    await wvm.refresh(user: uvm.user);
    context.read<AuthViewModel>().recordActivity();
  }

  Future<void> _searchCity(String city) async {
    if (city.trim().isEmpty) return;
    final wvm = context.read<WeatherViewModel>();
    final uvm = context.read<UserViewModel>();
    await wvm.fetchWeatherByCity(city.trim(), user: uvm.user);
    context.read<AuthViewModel>().recordActivity();
    if (!mounted) return;
    if (wvm.status == WeatherStatus.error) {
      SkySnackbar.error(context, wvm.errorMessage ?? 'City not found.');
    }
    FocusScope.of(context).unfocus();
  }

  void _showVideoSheet(
    BuildContext context,
    ActivityModel activity,
    UserModel? user,
    WeatherModel? weather,
  ) {
    if (activity.videoUrl == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VideoBottomSheet(
        activity: activity,
        user: user,
        weather: weather,
        initialElapsed: _inProgressActivityId == activity.id
            ? _inProgressElapsed
            : 0,
        isAlreadyCompleted: _completedActivityIds.contains(activity.id),
        onWorkoutStarted: () {
          setState(() {
            _inProgressActivityId = activity.id;
            _inProgressElapsed = 0;
          });
        },
        onElapsedTick: (elapsed) {
          if (_inProgressActivityId == activity.id) {
            setState(() => _inProgressElapsed = elapsed);
          }
        },
        onWorkoutCompleted: () {
          setState(() {
            _completedActivityIds.add(activity.id);
            _inProgressActivityId = null;
            _inProgressElapsed = 0;
          });
        },
        onWorkoutPaused: (elapsed) {
          setState(() => _inProgressElapsed = elapsed);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: const Color(0xFF00C6FF),
            backgroundColor: const Color(0xFF0F0F1E),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) =>
                  context.read<AuthViewModel>().recordActivity(),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildAppBar(context)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 20,
                        vertical: 16,
                      ),
                      child: _SearchBar(
                        controller: _cityCtrl,
                        onSearch: _searchCity,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 20,
                      ),
                      child: Consumer<WeatherViewModel>(
                        builder: (_, vm, __) {
                          if (vm.isLoading) return const _WeatherCardSkeleton();
                          if (vm.status == WeatherStatus.error && !vm.hasData) {
                            return _ErrorCard(
                              message:
                                  vm.errorMessage ?? 'Failed to load weather.',
                              onRetry: _onRefresh,
                            );
                          }
                          if (!vm.hasData) return const SizedBox.shrink();
                          return _WeatherCard(weather: vm.weather!);
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 20,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 18,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Suggested Activities',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 14)),
                  Consumer2<WeatherViewModel, UserViewModel>(
                    builder: (_, wvm, uvm, __) {
                      if (wvm.isLoading) {
                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: isWide ? 32 : 20,
                                vertical: 6,
                              ),
                              child: const _ActivityCardSkeleton(),
                            ),
                            childCount: 3,
                          ),
                        );
                      }
                      if (wvm.suggestions.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isWide ? 32 : 20,
                            ),
                            child: _EmptySuggestions(),
                          ),
                        );
                      }
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final activity = wvm.suggestions[i];
                            final isInProgress =
                                _inProgressActivityId == activity.id;
                            final isCompleted =
                                _completedActivityIds.contains(activity.id);
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                isWide ? 32 : 20,
                                0,
                                isWide ? 32 : 20,
                                12,
                              ),
                              child: GestureDetector(
                                onTap: () => _showVideoSheet(
                                  context,
                                  activity,
                                  uvm.user,
                                  wvm.weather,
                                ),
                                child: _ActivityCard(
                                  activity: activity,
                                  index: i,
                                  isInProgress: isInProgress,
                                  isCompleted: isCompleted,
                                ),
                              ),
                            );
                          },
                          childCount: wvm.suggestions.length,
                        ),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0072FF).withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child:
                const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          const Text(
            'SkyFit Pro',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          Consumer<UserViewModel>(
            builder: (_, uvm, __) {
              final name = uvm.user?.displayName.split(' ').first ?? '';
              return name.isNotEmpty
                  ? Text(
                      'Hi, $name',
                      style: const TextStyle(
                        color: Color(0xFF8888AA),
                        fontSize: 14,
                      ),
                    )
                  : const SizedBox.shrink();
            },
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileView()),
            ),
            child: Consumer<UserViewModel>(
              builder: (_, uvm, __) {
                return Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E1E30), Color(0xFF2A2A3A)],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF2A2A3A),
                      width: 2,
                    ),
                  ),
                  child: uvm.user?.photoUrl != null
                      ? ClipOval(
                          child: Image.network(
                            uvm.user!.photoUrl!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xFF8888AA),
                          size: 20,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Video Bottom Sheet ────────────────────────────────────────────────────────

class _VideoBottomSheet extends StatefulWidget {
  const _VideoBottomSheet({
    required this.activity,
    required this.user,
    required this.weather,
    required this.initialElapsed,
    required this.isAlreadyCompleted,
    required this.onWorkoutStarted,
    required this.onElapsedTick,
    required this.onWorkoutCompleted,
    required this.onWorkoutPaused,
  });
  final ActivityModel activity;
  final UserModel? user;
  final WeatherModel? weather;
  final int initialElapsed;
  final bool isAlreadyCompleted;
  final VoidCallback onWorkoutStarted;
  final void Function(int elapsed) onElapsedTick;
  final VoidCallback onWorkoutCompleted;
  final void Function(int elapsed) onWorkoutPaused;

  @override
  State<_VideoBottomSheet> createState() => _VideoBottomSheetState();
}

class _VideoBottomSheetState extends State<_VideoBottomSheet> {
  YoutubePlayerController? _controller;

  final bool _isMobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool _workoutStarted = false;
  bool _workoutDone = false;
  bool _isPaused = false;
  int _elapsedSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    if (widget.initialElapsed > 0) {
      _workoutStarted = true;
      _isPaused = true;
      _elapsedSeconds = widget.initialElapsed;
    }

    if (widget.isAlreadyCompleted) {
      _workoutStarted = true;
      _workoutDone = true;
      _elapsedSeconds = widget.activity.durationMinutes * 60;
    }

    if (_isMobile && widget.activity.videoUrl != null) {
      _controller = YoutubePlayerController(
        initialVideoId: widget.activity.videoUrl!,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          showLiveFullscreenButton: true,
          enableCaption: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _timer?.cancel();
    if (_workoutStarted && !_workoutDone) {
      widget.onWorkoutPaused(_elapsedSeconds);
    }
    super.dispose();
  }

  void _startWorkout() {
    setState(() {
      _workoutStarted = true;
      _isPaused = false;
      _elapsedSeconds = 0;
    });
    widget.onWorkoutStarted();
    _resumeTimer();
  }

  void _resumeTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
      widget.onElapsedTick(_elapsedSeconds);
      if (_elapsedSeconds >= widget.activity.durationMinutes * 60) {
        _completeWorkout();
      }
    });
  }

  void _pauseWorkout() {
    _timer?.cancel();
    setState(() => _isPaused = true);
    widget.onWorkoutPaused(_elapsedSeconds);
  }

  void _continueWorkout() {
    setState(() => _isPaused = false);
    _resumeTimer();
  }

  Future<void> _onFinishTapped() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Finish workout?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to finish this workout?',
          style: TextStyle(color: Color(0xFF8888AA)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Keep Going',
              style: TextStyle(color: Color(0xFF00C6FF)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Finish',
              style: TextStyle(color: Color(0xFF2ECC71)),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) _completeWorkout();
  }

  void _completeWorkout() {
    _timer?.cancel();
    setState(() {
      _workoutDone = true;
      _isPaused = false;
    });

    widget.onWorkoutCompleted();

    context.read<UserViewModel>().logActivity(
          activityId: widget.activity.id,
          activityName: widget.activity.name,
          durationMinutes:
              (_elapsedSeconds / 60).ceil().clamp(1, widget.activity.durationMinutes),
        );

    // No emoji — formal snackbar
    SkySnackbar.success(context, 'Workout complete. Well done!');
  }

  String _formatElapsed(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _buildWhySuggested() {
    final parts = <String>[];

    if (widget.weather != null) {
      switch (widget.weather!.category) {
        case WeatherCategory.clear:
          parts.add('Clear weather');
          break;
        case WeatherCategory.cloudy:
          parts.add('Cloudy weather');
          break;
        case WeatherCategory.rain:
          parts.add('Rainy weather');
          break;
        case WeatherCategory.snow:
          parts.add('Snow');
          break;
        case WeatherCategory.thunderstorm:
          parts.add('Thunderstorm');
          break;
        case WeatherCategory.atmosphere:
          parts.add('Poor visibility');
          break;
      }
      if (widget.weather!.isExtremeHeat) parts.add('Extreme heat');
    }

    if (widget.user != null) {
      parts.add(widget.user!.isElderly
          ? 'Age 50+'
          : 'Age ${widget.user!.age}');
      final cat = widget.user!.weightCategory;
      if (cat != null) {
        switch (cat) {
          case WeightCategory.underweight:
            parts.add('Underweight');
            break;
          case WeightCategory.normal:
            parts.add('Normal BMI');
            break;
          case WeightCategory.overweight:
            parts.add('Overweight');
            break;
          case WeightCategory.obese:
            parts.add('Obese BMI');
            break;
        }
      }
      if (widget.user!.fitnessGoal != null) {
        parts.add(widget.user!.fitnessGoal!);
      }
    }

    return parts.join(' · ');
  }

  String _difficultyDescription(ActivityDifficulty d) {
    switch (d) {
      case ActivityDifficulty.easy:
        return 'Suitable for all fitness levels';
      case ActivityDifficulty.moderate:
        return 'Some fitness experience recommended';
      case ActivityDifficulty.intense:
        return 'Advanced — consult a doctor if needed';
    }
  }

  Color _diffColor(ActivityDifficulty d) {
    switch (d) {
      case ActivityDifficulty.easy:
        return const Color(0xFF2ECC71);
      case ActivityDifficulty.moderate:
        return const Color(0xFFFFA502);
      case ActivityDifficulty.intense:
        return const Color(0xFFFF4757);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diffColor = _diffColor(widget.activity.difficulty);
    final whySuggested = _buildWhySuggested();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A3A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.activity.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _DiffBadge(
                    label: widget.activity.difficulty.name,
                    color: diffColor,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF8888AA),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: diffColor, size: 13),
                  const SizedBox(width: 5),
                  Text(
                    _difficultyDescription(widget.activity.difficulty),
                    style: TextStyle(
                      color: diffColor.withOpacity(0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _isMobile && _controller != null
                    ? YoutubePlayer(
                        controller: _controller!,
                        showVideoProgressIndicator: true,
                        progressIndicatorColor: const Color(0xFF00C6FF),
                        progressColors: const ProgressBarColors(
                          playedColor: Color(0xFF00C6FF),
                          handleColor: Color(0xFF0072FF),
                        ),
                      )
                    : Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.smartphone_rounded,
                                color: Color(0xFF555570),
                                size: 40,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Video available on mobile only.',
                                style: TextStyle(
                                  color: Color(0xFF8888AA),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                widget.activity.description,
                style: const TextStyle(
                  color: Color(0xFF8888AA),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 14),

            if (whySuggested.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0072FF).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF0072FF).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFF00C6FF),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Suggested based on: $whySuggested',
                          style: const TextStyle(
                            color: Color(0xFF00C6FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 14),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.timer_outlined,
                    label: '${widget.activity.durationMinutes} min',
                  ),
                  _InfoChip(
                    icon: widget.activity.location == ActivityLocation.indoor
                        ? Icons.home_outlined
                        : widget.activity.location == ActivityLocation.outdoor
                            ? Icons.park_outlined
                            : Icons.swap_horiz_rounded,
                    label: widget.activity.location.name,
                  ),
                  if (widget.activity.requiresEquipment)
                    _InfoChip(
                      icon: Icons.warning_amber_rounded,
                      label: 'Equipment needed',
                      color: const Color(0xFFFFA502),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _workoutDone
                  ? const _WorkoutDoneBanner()
                  : _workoutStarted
                      ? _WorkoutTimer(
                          elapsed: _elapsedSeconds,
                          total: widget.activity.durationMinutes * 60,
                          isPaused: _isPaused,
                          formatElapsed: _formatElapsed,
                          onPause: _pauseWorkout,
                          onContinue: _continueWorkout,
                          onFinish: _onFinishTapped,
                        )
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _startWorkout,
                            icon: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white),
                            label: const Text(
                              'Start Workout',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0072FF),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
    
  }
}

// ── Workout Timer Widget ──────────────────────────────────────────────────────

class _WorkoutTimer extends StatelessWidget {
  const _WorkoutTimer({
    required this.elapsed,
    required this.total,
    required this.isPaused,
    required this.formatElapsed,
    required this.onPause,
    required this.onContinue,
    required this.onFinish,
  });
  final int elapsed;
  final int total;
  final bool isPaused;
  final String Function(int) formatElapsed;
  final VoidCallback onPause;
  final VoidCallback onContinue;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final progress = (elapsed / total).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1929),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPaused
              ? const Color(0xFFFFA502).withOpacity(0.3)
              : const Color(0xFF0072FF).withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isPaused
                        ? Icons.pause_circle_outline_rounded
                        : Icons.fitness_center_rounded,
                    color: isPaused
                        ? const Color(0xFFFFA502)
                        : const Color(0xFF00C6FF),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isPaused ? 'Workout paused' : 'Workout in progress',
                    style: TextStyle(
                      color: isPaused
                          ? const Color(0xFFFFA502)
                          : const Color(0xFF00C6FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                formatElapsed(elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF1E1E30),
              valueColor: AlwaysStoppedAnimation<Color>(
                isPaused
                    ? const Color(0xFFFFA502)
                    : const Color(0xFF00C6FF),
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isPaused ? onContinue : onPause,
                  icon: Icon(
                    isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    isPaused ? 'Continue' : 'Pause',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPaused
                        ? const Color(0xFF0072FF)
                        : const Color(0xFF2A2A3A),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onFinish,
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: const Text(
                    'Finish',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2ECC71),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Workout Done Banner ───────────────────────────────────────────────────────

class _WorkoutDoneBanner extends StatelessWidget {
  const _WorkoutDoneBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2ECC71).withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF2ECC71).withOpacity(0.3),
        ),
      ),
      child: const Column(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF2ECC71), size: 28),
          SizedBox(height: 6),
          Text(
            'Workout Complete',
            style: TextStyle(
              color: Color(0xFF2ECC71),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Logged to your history',
            style: TextStyle(
              color: Color(0xFF8888AA),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Search Bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onSearch});
  final TextEditingController controller;
  final void Function(String) onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E30)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Color(0xFFE0E0F0), fontSize: 14),
        textInputAction: TextInputAction.search,
        onSubmitted: onSearch,
        decoration: InputDecoration(
          hintText: 'Search city...',
          hintStyle: TextStyle(
            color: const Color(0xFF8888AA).withOpacity(0.6),
            fontSize: 14,
          ),
          prefixIcon: const Icon(Icons.search_rounded,
              color: Color(0xFF555570), size: 20),
          suffixIcon: IconButton(
            icon: const Icon(Icons.send_rounded,
                color: Color(0xFF00C6FF), size: 18),
            onPressed: () => onSearch(controller.text),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

// ── Weather Card ──────────────────────────────────────────────────────────────

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.weather});
  final WeatherModel weather;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _gradientColors(weather.category),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _gradientColors(weather.category).first.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${weather.cityName}, ${weather.country}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(weather.fetchedAt),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                weather.tempDisplay,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 58,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                ),
              ),
              const Spacer(),
              Image.network(
                weather.iconUrl,
                width: 80,
                height: 80,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.cloud_outlined,
                  color: Colors.white54,
                  size: 60,
                ),
              ),
            ],
          ),
          Text(
            _capitalize(weather.weatherDescription),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(
                icon: Icons.water_drop_outlined,
                label: '${weather.humidity.round()}%',
                hint: 'Humidity',
              ),
              _StatChip(
                icon: Icons.air_rounded,
                label: '${weather.windSpeedKmh.round()} km/h',
                hint: 'Wind',
              ),
              _StatChip(
                icon: Icons.thermostat_outlined,
                label: 'Feels ${weather.feelsLikeCelsius.round()}°',
                hint: 'Feels like',
              ),
              if (weather.uvIndex != null)
                _StatChip(
                  icon: Icons.wb_sunny_outlined,
                  label: 'UV ${weather.uvIndex!.round()}',
                  hint: 'UV Index',
                ),
            ],
          ),
          if (!weather.isSafeForOutdoor) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.amber, size: 16),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Conditions not ideal for outdoor training',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
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

  List<Color> _gradientColors(WeatherCategory cat) {
    switch (cat) {
      case WeatherCategory.clear:
        return [const Color(0xFF1A73E8), const Color(0xFF0D47A1)];
      case WeatherCategory.cloudy:
        return [const Color(0xFF455A64), const Color(0xFF263238)];
      case WeatherCategory.rain:
        return [const Color(0xFF1565C0), const Color(0xFF0A1929)];
      case WeatherCategory.snow:
        return [const Color(0xFF546E7A), const Color(0xFF37474F)];
      case WeatherCategory.thunderstorm:
        return [const Color(0xFF4A148C), const Color(0xFF1A0033)];
      case WeatherCategory.atmosphere:
        return [const Color(0xFF4E342E), const Color(0xFF3E2723)];
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.icon, required this.label, required this.hint});
  final IconData icon;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Activity Card ─────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.activity,
    required this.index,
    required this.isInProgress,
    required this.isCompleted,
  });
  final ActivityModel activity;
  final int index;
  final bool isInProgress;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final diffColor = _diffColor(activity.difficulty);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFF2ECC71).withOpacity(0.4)
              : isInProgress
                  ? const Color(0xFF00C6FF).withOpacity(0.4)
                  : const Color(0xFF1E1E30),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isCompleted
                    ? [const Color(0xFF2ECC71), const Color(0xFF27AE60)]
                    : isInProgress
                        ? [const Color(0xFF00C6FF), const Color(0xFF0072FF)]
                        : index == 0
                            ? [const Color(0xFF00C6FF), const Color(0xFF0072FF)]
                            : [const Color(0xFF1E1E30), const Color(0xFF2A2A3A)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                  : isInProgress
                      ? const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 20)
                      : Text(
                          '#${index + 1}',
                          style: TextStyle(
                            color: index == 0
                                ? Colors.white
                                : const Color(0xFF8888AA),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        activity.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isCompleted)
                      _StatusBadge(
                        label: 'Done',
                        color: const Color(0xFF2ECC71),
                      )
                    else if (isInProgress)
                      _StatusBadge(
                        label: 'In Progress',
                        color: const Color(0xFF00C6FF),
                      )
                    else if (activity.videoUrl != null)
                      const Icon(
                        Icons.play_circle_outline_rounded,
                        color: Color(0xFF00C6FF),
                        size: 20,
                      ),
                    const SizedBox(width: 6),
                    _DiffBadge(
                      label: activity.difficulty.name,
                      color: diffColor,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  activity.description,
                  style: const TextStyle(
                    color: Color(0xFF8888AA),
                    fontSize: 12,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _InfoChip(
                      icon: Icons.timer_outlined,
                      label: '${activity.durationMinutes} min',
                    ),
                    const SizedBox(width: 8),
                    _InfoChip(
                      icon: activity.location == ActivityLocation.indoor
                          ? Icons.home_outlined
                          : activity.location == ActivityLocation.outdoor
                              ? Icons.park_outlined
                              : Icons.swap_horiz_rounded,
                      label: activity.location.name,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _diffColor(ActivityDifficulty d) {
    switch (d) {
      case ActivityDifficulty.easy:
        return const Color(0xFF2ECC71);
      case ActivityDifficulty.moderate:
        return const Color(0xFFFFA502);
      case ActivityDifficulty.intense:
        return const Color(0xFFFF4757);
    }
  }
}

// ── Shared Badges & Chips ─────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _DiffBadge extends StatelessWidget {
  const _DiffBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF555570);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: c, size: 13),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: c,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Skeleton Loaders ──────────────────────────────────────────────────────────

class _WeatherCardSkeleton extends StatefulWidget {
  const _WeatherCardSkeleton();

  @override
  State<_WeatherCardSkeleton> createState() => _WeatherCardSkeletonState();
}

class _WeatherCardSkeletonState extends State<_WeatherCardSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: 200,
        decoration: BoxDecoration(
          color: Color.lerp(
            const Color(0xFF0F0F1E),
            const Color(0xFF1A1A2E),
            _anim.value,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF00C6FF),
          ),
        ),
      ),
    );
  }
}

class _ActivityCardSkeleton extends StatelessWidget {
  const _ActivityCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E1E30)),
      ),
    );
  }
}

// ── Error Card ────────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFF4757).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: Color(0xFFFF4757), size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8888AA), fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF00C6FF), size: 18),
            label: const Text(
              'Retry',
              style: TextStyle(color: Color(0xFF00C6FF)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty Suggestions ─────────────────────────────────────────────────────────

class _EmptySuggestions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E1E30)),
      ),
      child: const Column(
        children: [
          Icon(Icons.fitness_center_outlined,
              color: Color(0xFF555570), size: 36),
          SizedBox(height: 10),
          Text(
            'Search for a city to get activity suggestions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8888AA), fontSize: 14),
          ),
        ],
      ),
    );
  }
}