import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final int age;
  final double weightKg;
  final double heightCm;
  final String? fitnessGoal;
  final bool isProfileComplete; // ← ADDED
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.age,
    required this.weightKg,
    required this.heightCm,
    this.fitnessGoal,
    this.isProfileComplete = false, // ← ADDED (default false)
    required this.createdAt,
    required this.updatedAt,
  });

  // ── BMI Computation ──────────────────────────────────────────────────────

  /// BMI = weight(kg) / height(m)²
  /// Returns 0 if heightCm is not set yet (incomplete profile).
  double get bmi {
    if (heightCm <= 0) return 0;
    final heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }

  /// Weight category based on WHO BMI classification.
  /// Returns null if BMI cannot be computed (incomplete profile).
  WeightCategory? get weightCategory {
    if (bmi <= 0) return null;
    if (bmi < 18.5) return WeightCategory.underweight;
    if (bmi < 25.0) return WeightCategory.normal;
    if (bmi < 30.0) return WeightCategory.overweight;
    return WeightCategory.obese;
  }

  /// True if user is considered overweight per lab matrix (BMI >= 25).
  /// Returns false if BMI is not yet computable.
  bool get isOverweight =>
      weightCategory == WeightCategory.overweight ||
      weightCategory == WeightCategory.obese;

  /// True if user is elderly per lab matrix (age >= 50)
  bool get isElderly => age >= 50;

  /// True if user is young (age < 50)
  bool get isYoung => age < 50;

  /// True if user has normal/athletic weight.
  /// Returns false if BMI is not yet computable.
  bool get isNormalWeight =>
      weightCategory == WeightCategory.normal ||
      weightCategory == WeightCategory.underweight;

  // ── Validation helpers ───────────────────────────────────────────────────

  bool get isValidWeight => weightKg >= 20 && weightKg <= 300;
  bool get isValidHeight => heightCm >= 50 && heightCm <= 250;
  bool get isValidAge => age >= 1 && age <= 120;
  bool get isProfileValid => isValidWeight && isValidHeight && isValidAge;

  // ── Factory constructors ─────────────────────────────────────────────────

  factory UserModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserModel(
      uid: doc.id,
      email: data['email'] as String,
      displayName: data['displayName'] as String,
      photoUrl: data['photoUrl'] as String?,
      age: (data['age'] as num).toInt(),
      weightKg: (data['weightKg'] as num).toDouble(),
      heightCm: (data['heightCm'] as num?)?.toDouble() ?? 0.0,
      fitnessGoal: data['fitnessGoal'] as String?,
      isProfileComplete: data['isProfileComplete'] as bool? ?? false, // ← ADDED
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String,
      email: map['email'] as String,
      displayName: map['displayName'] as String,
      photoUrl: map['photoUrl'] as String?,
      age: (map['age'] as num).toInt(),
      weightKg: (map['weightKg'] as num).toDouble(),
      heightCm: (map['heightCm'] as num?)?.toDouble() ?? 0.0,
      fitnessGoal: map['fitnessGoal'] as String?,
      isProfileComplete: map['isProfileComplete'] as bool? ?? false, // ← ADDED
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] is Timestamp
          ? (map['updatedAt'] as Timestamp).toDate()
          : DateTime.parse(map['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'age': age,
      'weightKg': weightKg,
      'heightCm': heightCm,
      'fitnessGoal': fitnessGoal,
      'isProfileComplete': isProfileComplete, // ← ADDED
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    int? age,
    double? weightKg,
    double? heightCm,
    String? fitnessGoal,
    bool? isProfileComplete, // ← ADDED
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      age: age ?? this.age,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      fitnessGoal: fitnessGoal ?? this.fitnessGoal,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete, // ← ADDED
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'UserModel(uid: $uid, name: $displayName, age: $age, bmi: ${bmi.toStringAsFixed(1)}, category: ${weightCategory?.name ?? 'unknown'}, isProfileComplete: $isProfileComplete)';
}

// ── Weight Category Enum ──────────────────────────────────────────────────────

enum WeightCategory { underweight, normal, overweight, obese }