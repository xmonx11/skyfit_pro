import 'package:flutter/material.dart';

enum SkySnackbarType { success, error, info, warning }

class SkySnackbar {
  SkySnackbar._();

  static void show(
    BuildContext context, {
    required String message,
    SkySnackbarType type = SkySnackbarType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    // ✅ FIX 1: Guard against unmounted / deactivated widget contexts
    if (!context.mounted) return;

    // ✅ FIX 2: Use maybeOf() so it returns null instead of throwing
    //           when there's no Scaffold ancestor (off-screen widget)
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    final config = _getConfig(type);

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        duration: duration,
        // ✅ FIX 3: Use fixed behavior — floating with large bottom margin
        //           causes "presented off screen" on many devices
        behavior: SnackBarBehavior.fixed,
        content: _SkySnackbarContent(
          message: message,
          icon: config.icon,
          iconColor: config.iconColor,
          borderColor: config.borderColor,
          glowColor: config.glowColor,
        ),
      ),
    );
  }

  static void success(BuildContext context, String message) =>
      show(context, message: message, type: SkySnackbarType.success);

  static void error(BuildContext context, String message) =>
      show(context, message: message, type: SkySnackbarType.error);

  static void info(BuildContext context, String message) =>
      show(context, message: message, type: SkySnackbarType.info);

  static void warning(BuildContext context, String message) =>
      show(context, message: message, type: SkySnackbarType.warning);

  static _SnackbarConfig _getConfig(SkySnackbarType type) {
    switch (type) {
      case SkySnackbarType.success:
        return _SnackbarConfig(
          icon: Icons.check_circle_outline_rounded,
          iconColor: const Color(0xFF2ECC71),
          borderColor: const Color(0xFF2ECC71),
          glowColor: const Color(0xFF2ECC71),
        );
      case SkySnackbarType.error:
        return _SnackbarConfig(
          icon: Icons.error_outline_rounded,
          iconColor: const Color(0xFFFF4757),
          borderColor: const Color(0xFFFF4757),
          glowColor: const Color(0xFFFF4757),
        );
      case SkySnackbarType.warning:
        return _SnackbarConfig(
          icon: Icons.warning_amber_rounded,
          iconColor: const Color(0xFFFFA502),
          borderColor: const Color(0xFFFFA502),
          glowColor: const Color(0xFFFFA502),
        );
      case SkySnackbarType.info:
        return _SnackbarConfig(
          icon: Icons.info_outline_rounded,
          iconColor: const Color(0xFF00C6FF),
          borderColor: const Color(0xFF00C6FF),
          glowColor: const Color(0xFF00C6FF),
        );
    }
  }
}

class _SnackbarConfig {
  final IconData icon;
  final Color iconColor;
  final Color borderColor;
  final Color glowColor;

  const _SnackbarConfig({
    required this.icon,
    required this.iconColor,
    required this.borderColor,
    required this.glowColor,
  });
}

class _SkySnackbarContent extends StatelessWidget {
  const _SkySnackbarContent({
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.borderColor,
    required this.glowColor,
  });

  final String message;
  final IconData icon;
  final Color iconColor;
  final Color borderColor;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withOpacity(0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFE0E0F0),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}