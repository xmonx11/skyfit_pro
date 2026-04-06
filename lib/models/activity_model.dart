import 'weather_model.dart';

/// Difficulty level of a suggested activity.
enum ActivityDifficulty { easy, moderate, intense }

/// Where the activity takes place.
enum ActivityLocation { indoor, outdoor, either }

/// A fitness activity suggestion produced by the recommendation engine.
class ActivityModel {
  final String id;
  final String name;
  final String description;
  final ActivityDifficulty difficulty;
  final ActivityLocation location;
  final int durationMinutes;
  final List<String> tags;
  final String? imageAsset;
  final bool requiresEquipment;
  // ✅ Local asset path for AI-generated video (lab requirement)
  final String? videoUrl;

  // ✅ Primary fitness goal this activity is best suited for.
  // Used by _sortByGoal() to guarantee goal-matched activities always
  // surface at the top, regardless of which weather branch is active.
  // Values must match UserModel.fitnessGoal strings exactly:
  //   'Weight Loss' | 'Muscle Gain' | 'Endurance' | 'Flexibility' | 'General Fitness'
  final String? primaryGoal;

  const ActivityModel({
    required this.id,
    required this.name,
    required this.description,
    required this.difficulty,
    required this.location,
    required this.durationMinutes,
    required this.tags,
    this.imageAsset,
    this.requiresEquipment = false,
    this.videoUrl,
    this.primaryGoal,
  });

  factory ActivityModel.fromMap(Map<String, dynamic> map) {
    return ActivityModel(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      difficulty: ActivityDifficulty.values.firstWhere(
        (e) => e.name == map['difficulty'],
        orElse: () => ActivityDifficulty.moderate,
      ),
      location: ActivityLocation.values.firstWhere(
        (e) => e.name == map['location'],
        orElse: () => ActivityLocation.either,
      ),
      durationMinutes: (map['durationMinutes'] as num).toInt(),
      tags: List<String>.from(map['tags'] as List),
      imageAsset: map['imageAsset'] as String?,
      requiresEquipment: map['requiresEquipment'] as bool? ?? false,
      videoUrl: map['videoUrl'] as String?,
      primaryGoal: map['primaryGoal'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'difficulty': difficulty.name,
      'location': location.name,
      'durationMinutes': durationMinutes,
      'tags': tags,
      'imageAsset': imageAsset,
      'requiresEquipment': requiresEquipment,
      'videoUrl': videoUrl,
      'primaryGoal': primaryGoal,
    };
  }

  bool suitableFor(WeatherModel weather) {
    if (location == ActivityLocation.indoor) return true;
    if (location == ActivityLocation.outdoor) return weather.isSafeForOutdoor;
    return true;
  }

  ActivityModel copyWith({
    String? id,
    String? name,
    String? description,
    ActivityDifficulty? difficulty,
    ActivityLocation? location,
    int? durationMinutes,
    List<String>? tags,
    String? imageAsset,
    bool? requiresEquipment,
    String? videoUrl,
    String? primaryGoal,
  }) {
    return ActivityModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      difficulty: difficulty ?? this.difficulty,
      location: location ?? this.location,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      tags: tags ?? this.tags,
      imageAsset: imageAsset ?? this.imageAsset,
      requiresEquipment: requiresEquipment ?? this.requiresEquipment,
      videoUrl: videoUrl ?? this.videoUrl,
      primaryGoal: primaryGoal ?? this.primaryGoal,
    );
  }

  @override
  String toString() =>
      'ActivityModel(id: $id, name: $name, difficulty: ${difficulty.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ── Predefined activity catalogue ─────────────────────────────────────────────
// videoUrl = YouTube video ID for AI-generated exercise videos
//
// Lab requirement matrix:
// Clear/Sunny + Age <50 + Normal/Athletic  → Outdoor Running / HIIT
// Clear/Sunny + Age >50 + Any              → Morning Walk / Tai Chi
// Rain/Snow   + Any    + Any               → Indoor Yoga / Bodyweight
// Extreme Heat + Any   + Overweight        → Swimming / Light Stretching
//
// primaryGoal — ensures _sortByGoal() always surfaces best-match first:
//   'Weight Loss'     → high-calorie cardio/HIIT
//   'Muscle Gain'     → strength / bodyweight
//   'Endurance'       → long-duration cardio
//   'Flexibility'     → yoga / stretching
//   'General Fitness' → moderate all-rounders

const List<ActivityModel> kDefaultActivities = [
  ActivityModel(
    id: 'outdoor_run',
    name: 'Outdoor Run',
    description:
        'A steady-paced run through local parks or streets. Great for cardiovascular health and fresh air.',
    difficulty: ActivityDifficulty.moderate,
    location: ActivityLocation.outdoor,
    durationMinutes: 30,
    tags: ['cardio', 'endurance'],
    primaryGoal: 'Endurance',
    videoUrl: 'BHY0FxzoKZE',
  ),
  ActivityModel(
    id: 'outdoor_cycling',
    name: 'Cycling',
    description:
        'Ride at a comfortable pace outdoors. Low impact and excellent for leg strength.',
    difficulty: ActivityDifficulty.moderate,
    location: ActivityLocation.outdoor,
    durationMinutes: 45,
    tags: ['cardio', 'legs', 'endurance'],
    primaryGoal: 'Endurance',
    videoUrl: 'uKE9GqZCj7Y',
  ),
  ActivityModel(
    id: 'outdoor_yoga',
    name: 'Outdoor Yoga',
    description:
        'Connect with nature while improving flexibility and mindfulness.',
    difficulty: ActivityDifficulty.easy,
    location: ActivityLocation.outdoor,
    durationMinutes: 40,
    tags: ['flexibility', 'mindfulness', 'recovery'],
    primaryGoal: 'Flexibility',
    videoUrl: 'v7AYKMP6rOE',
  ),
  ActivityModel(
    id: 'hiit_park',
    name: 'Park HIIT',
    description:
        'High-intensity interval training using park benches and open space.',
    difficulty: ActivityDifficulty.intense,
    location: ActivityLocation.outdoor,
    durationMinutes: 20,
    tags: ['hiit', 'cardio', 'strength'],
    primaryGoal: 'Weight Loss',
    videoUrl: 'ml6cT4AZdqI',
  ),
  ActivityModel(
    id: 'home_yoga',
    name: 'Home Yoga',
    description:
        'Gentle yoga sequence to improve flexibility, posture and mental clarity.',
    difficulty: ActivityDifficulty.easy,
    location: ActivityLocation.indoor,
    durationMinutes: 30,
    tags: ['flexibility', 'mindfulness', 'recovery'],
    primaryGoal: 'Flexibility',
    videoUrl: '4pKly2JojMw',
  ),
  ActivityModel(
    id: 'bodyweight_strength',
    name: 'Bodyweight Strength',
    description: 'Push-ups, squats, lunges and planks. No equipment required.',
    difficulty: ActivityDifficulty.moderate,
    location: ActivityLocation.indoor,
    durationMinutes: 30,
    tags: ['strength', 'bodyweight'],
    primaryGoal: 'Muscle Gain',
    requiresEquipment: false,
    videoUrl: 'UItWltVZZmE',
  ),
  ActivityModel(
    id: 'treadmill_run',
    name: 'Treadmill Run',
    description: 'Controlled indoor run. Perfect for bad-weather days.',
    difficulty: ActivityDifficulty.moderate,
    location: ActivityLocation.indoor,
    durationMinutes: 30,
    tags: ['cardio', 'endurance'],
    primaryGoal: 'Endurance',
    requiresEquipment: true,
    videoUrl: '8iPEnn-ltC8',
  ),
  ActivityModel(
    id: 'indoor_cycling',
    name: 'Stationary Cycling',
    description:
        'Spin session at home or gym. High calorie burn with zero joint impact.',
    difficulty: ActivityDifficulty.intense,
    location: ActivityLocation.indoor,
    durationMinutes: 40,
    tags: ['cardio', 'legs'],
    primaryGoal: 'Weight Loss',
    requiresEquipment: true,
    videoUrl: 'ZMO_XC9w7Lw',
  ),
  ActivityModel(
    id: 'stretching',
    name: 'Full-Body Stretching',
    description:
        'A 20-minute guided stretch to aid recovery and improve flexibility.',
    difficulty: ActivityDifficulty.easy,
    location: ActivityLocation.either,
    durationMinutes: 20,
    tags: ['flexibility', 'recovery'],
    primaryGoal: 'Flexibility',
    videoUrl: 'sTANio_2E0Q',
  ),
  ActivityModel(
    id: 'swimming',
    name: 'Swimming',
    description:
        'Full-body low-impact workout. Ideal for joints and cardiovascular health.',
    difficulty: ActivityDifficulty.moderate,
    location: ActivityLocation.either,
    durationMinutes: 45,
    // ✅ FIXED: Added 'heat' tag so swimming surfaces in extreme heat fallback
    tags: ['cardio', 'full-body', 'low-impact', 'heat'],
    primaryGoal: 'General Fitness',
    requiresEquipment: true,
    videoUrl: 'gh5mAtmeR3Y',
  ),
  ActivityModel(
    id: 'morning_walk',
    name: 'Morning Walk',
    description:
        'A gentle morning walk to boost energy and cardiovascular health.',
    difficulty: ActivityDifficulty.easy,
    location: ActivityLocation.outdoor,
    durationMinutes: 30,
    tags: ['cardio', 'low-impact', 'recovery', 'elderly'],
    primaryGoal: 'General Fitness',
    videoUrl: 'La64WYECkAE',
  ),
  ActivityModel(
    id: 'tai_chi',
    name: 'Tai Chi in the Park',
    description:
        'Slow, flowing movements that improve balance and flexibility. Perfect for 50+.',
    difficulty: ActivityDifficulty.easy,
    location: ActivityLocation.outdoor,
    durationMinutes: 40,
    tags: ['flexibility', 'balance', 'mindfulness', 'elderly', 'recovery'],
    primaryGoal: 'Flexibility',
    videoUrl: 'cEOS2zoyQw4',
  ),
  ActivityModel(
    id: 'bodyweight_circuit',
    name: 'Bodyweight Circuit',
    description:
        'A structured indoor circuit — jumping jacks, mountain climbers, push-ups.',
    difficulty: ActivityDifficulty.moderate,
    location: ActivityLocation.indoor,
    durationMinutes: 25,
    tags: ['cardio', 'strength', 'bodyweight', 'circuit'],
    primaryGoal: 'Muscle Gain',
    videoUrl: 'cbKkB3POqaY',
  ),
  ActivityModel(
    id: 'light_stretching',
    name: 'Hydrated Light Stretching',
    description:
        'Gentle full-body stretching with hydration breaks. Safe for hot weather.',
    difficulty: ActivityDifficulty.easy,
    location: ActivityLocation.either,
    durationMinutes: 20,
    tags: ['flexibility', 'recovery', 'low-impact', 'heat'],
    primaryGoal: 'Flexibility',
    videoUrl: 'L_xrDAtykMI',
  ),
];