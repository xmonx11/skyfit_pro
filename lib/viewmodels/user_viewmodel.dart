import 'dart:async';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../repositories/auth_repository.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import 'weather_viewmodel.dart';

/// Manages the current user's profile state, Firestore sync, and app theme.
/// Reacts to auth state changes via [onAuthStateChanged].
class UserViewModel extends ChangeNotifier {
  UserViewModel({
    required AuthRepository authRepository,
    required FirestoreService firestoreService,
    required StorageService storageService,
  })  : _auth = authRepository,
        _firestore = firestoreService,
        _storage = storageService;

  final AuthRepository _auth;
  final FirestoreService _firestore;
  final StorageService _storage;

  WeatherViewModel? _weatherViewModel;

  void setWeatherViewModel(WeatherViewModel wvm) {
    _weatherViewModel = wvm;
  }

  // ── State ─────────────────────────────────────────────────────────────────

  UserModel? _user;
  UserProfileStatus _profileStatus = UserProfileStatus.idle;
  String? _errorMessage;
  bool _isUpdating = false;

  StreamSubscription<UserModel?>? _profileStreamSub;
  String? _subscribedUid;

  // ── Theme ─────────────────────────────────────────────────────────────────

  static const String _kThemeKey = 'skyfit_theme_mode';
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Call once at startup (before runApp) to restore saved preference.
  Future<void> loadTheme() async {
    final saved = await _storage.read(_kThemeKey);
    switch (saved) {
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      default:
        _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  /// Toggle dark/light and persist the preference.
  Future<void> toggleDarkMode(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _storage.write(_kThemeKey, isDark ? 'dark' : 'light');
  }

  // ── Public getters ────────────────────────────────────────────────────────

  UserModel? get user => _user;
  UserProfileStatus get profileStatus => _profileStatus;
  String? get errorMessage => _errorMessage;
  bool get isUpdating => _isUpdating;

  bool get isProfileComplete =>
      _user != null &&
      _user!.age > 0 &&
      _user!.weightKg > 0 &&
      _user!.heightCm > 0;

  // ── Auth state reactor ────────────────────────────────────────────────────

  void onAuthStateChanged(UserModel? authUser) {
    if (authUser == null) {
      _clearProfile();
      return;
    }

    // Guard: stream already live for this UID — do nothing.
    if (_subscribedUid == authUser.uid && _profileStreamSub != null) {
      if (_user == null) {
        _user = authUser;
        notifyListeners();
      }
      return;
    }

    // New user or stream died — seed immediately so UI has something to show,
    // then open the real-time stream AND do an explicit one-shot fetch.
    // The one-shot fetch is the web safety net: on web, Firestore's real-time
    // snapshots() can silently fail to deliver the first event if the auth
    // token hasn't propagated to the SDK yet (race between Firebase Auth and
    // Firestore on the web platform). The explicit getUser() call goes through
    // a fresh HTTP request that always picks up the current token.
    _user = authUser;
    notifyListeners();

    _subscribeToProfile(authUser.uid);
    _loadProfileOnce(authUser.uid); // web-safe fallback
  }

  // ── Profile operations ────────────────────────────────────────────────────

  /// One-shot fetch used as a web fallback in case the real-time stream
  /// doesn't deliver its first event promptly after login/re-login.
  Future<void> _loadProfileOnce(String uid) async {
    try {
      final profile = await _firestore.getUser(uid);
      if (profile != null && _subscribedUid == uid) {
        // Only update if the stream hasn't already delivered a fresher copy.
        // Compare updatedAt so we never downgrade a stream-delivered document
        // with a stale HTTP response.
        final currentUpdatedAt = _user?.updatedAt;
        final fetchedUpdatedAt = profile.updatedAt;
        final shouldUpdate = currentUpdatedAt == null ||
            !fetchedUpdatedAt.isBefore(currentUpdatedAt);

        if (shouldUpdate) {
          _user = profile;
          _profileStatus = UserProfileStatus.loaded;
          notifyListeners();
          _weatherViewModel?.refreshSuggestions(user: _user);
        }
      }
    } catch (e) {
      // Non-fatal on web — the real-time stream may still deliver.
      // Only surface the error if we still have no user after the fetch.
      if (_user?.uid == uid && _profileStatus != UserProfileStatus.loaded) {
        _errorMessage = 'Failed to load profile: ${e.toString()}';
        _profileStatus = UserProfileStatus.error;
        notifyListeners();
      }
    }
  }

  Future<void> loadProfile(String uid) async {
    _setProfileStatus(UserProfileStatus.loading);
    try {
      final profile = await _firestore.getUser(uid);
      if (profile != null) {
        _user = profile;
        _setProfileStatus(UserProfileStatus.loaded);
      } else {
        _setProfileStatus(UserProfileStatus.notFound);
      }
    } catch (e) {
      _setError('Failed to load profile: ${e.toString()}');
      _setProfileStatus(UserProfileStatus.error);
    }
  }

  Future<bool> updateProfile({
    String? displayName,
    int? age,
    double? weightKg,
    double? heightCm,
    String? fitnessGoal,
  }) async {
    if (_user == null) return false;

    _isUpdating = true;
    _errorMessage = null;
    notifyListeners();

    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (age != null) updates['age'] = age;
    if (weightKg != null) updates['weightKg'] = weightKg;
    if (heightCm != null) updates['heightCm'] = heightCm;
    if (fitnessGoal != null) updates['fitnessGoal'] = fitnessGoal;

    if (updates.isEmpty) {
      _isUpdating = false;
      notifyListeners();
      return true;
    }

    final previousUser = _user;

    try {
      await _firestore.updateUser(_user!.uid, updates);

      _user = _user!.copyWith(
        displayName: displayName,
        age: age,
        weightKg: weightKg,
        heightCm: heightCm,
        fitnessGoal: fitnessGoal,
        updatedAt: DateTime.now(),
      );

      _isUpdating = false;
      _profileStatus = UserProfileStatus.loaded;
      notifyListeners();

      _weatherViewModel?.refreshSuggestions(user: _user);
      return true;
    } catch (e) {
      _user = previousUser;
      _isUpdating = false;
      _errorMessage = 'Failed to update profile: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updatePhotoUrl(String photoUrl) async {
    if (_user == null) return false;

    _isUpdating = true;
    notifyListeners();

    final previousUser = _user;
    try {
      await _firestore.updateUser(_user!.uid, {'photoUrl': photoUrl});
      _user = _user!.copyWith(photoUrl: photoUrl, updatedAt: DateTime.now());
      _isUpdating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _user = previousUser;
      _isUpdating = false;
      _errorMessage = 'Failed to update photo: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  Future<bool> logActivity({
    required String activityId,
    required String activityName,
    required int durationMinutes,
  }) async {
    if (_user == null) return false;
    try {
      await _firestore.logActivity(_user!.uid, {
        'activityId': activityId,
        'activityName': activityName,
        'durationMinutes': durationMinutes,
      });
      return true;
    } catch (e) {
      _setError('Failed to log activity: ${e.toString()}');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getActivityLog({int limit = 20}) async {
    if (_user == null) return [];
    try {
      return await _firestore.getActivityLog(_user!.uid, limit: limit);
    } catch (e) {
      _setError('Failed to load activity log: ${e.toString()}');
      return [];
    }
  }

  // ── Real-time Firestore stream ─────────────────────────────────────────────

  void _subscribeToProfile(String uid) {
    _profileStreamSub?.cancel();
    _profileStreamSub = null;
    _subscribedUid = uid;

    _profileStreamSub = _firestore.userStream(uid).listen(
      (userModel) {
        if (userModel != null && _subscribedUid == uid) {
          _user = userModel;
          _profileStatus = UserProfileStatus.loaded;
          notifyListeners();
          _weatherViewModel?.refreshSuggestions(user: _user);
        }
      },
      onError: (e) {
        // On web this can be a Firestore permission error that surfaces here
        // instead of throwing. Log it and surface to UI.
        _setError('Profile sync error: ${e.toString()}');
      },
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _clearProfile() {
    _profileStreamSub?.cancel();
    _profileStreamSub = null;
    _subscribedUid = null;
    _user = null;
    _profileStatus = UserProfileStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  void _setProfileStatus(UserProfileStatus status) {
    _profileStatus = status;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  @override
  void dispose() {
    _profileStreamSub?.cancel();
    super.dispose();
  }
}

enum UserProfileStatus { idle, loading, loaded, notFound, error }