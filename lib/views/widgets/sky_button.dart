import 'package:flutter/material.dart';

enum SkyButtonVariant { primary, secondary, outlined, danger, google }

class SkyButton extends StatefulWidget {
  const SkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SkyButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final SkyButtonVariant variant;
  final bool isLoading;
  final Widget? icon;
  final double? width;
  final double height;

  @override
  State<SkyButton> createState() => _SkyButtonState();
}

class _SkyButtonState extends State<SkyButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 0.04,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(_) {
    // FIX: Do not animate or respond to taps while loading.
    if (widget.isLoading || widget.onPressed == null) return;
    _controller.forward();
  }

  void _onTapUp(_) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // FIX: When loading or disabled, wrap in IgnorePointer so no tap events
    // reach the GestureDetector or InkWell at all — preventing double
    // submissions from rapid taps or keyboard onFieldSubmitted callbacks
    // that fire before isLoading has propagated to the widget tree.
    return IgnorePointer(
      ignoring: widget.isLoading || widget.onPressed == null,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedBuilder(
          animation: _scaleAnim,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          ),
          child: SizedBox(
            width: widget.width ?? double.infinity,
            height: widget.height,
            child: _buildButton(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildButton(ThemeData theme) {
    switch (widget.variant) {
      case SkyButtonVariant.primary:
        return _PrimaryButton(
          label: widget.label,
          onPressed: widget.isLoading ? null : widget.onPressed,
          isLoading: widget.isLoading,
          icon: widget.icon,
        );
      case SkyButtonVariant.secondary:
        return _SecondaryButton(
          label: widget.label,
          onPressed: widget.isLoading ? null : widget.onPressed,
          isLoading: widget.isLoading,
          icon: widget.icon,
        );
      case SkyButtonVariant.outlined:
        return _OutlinedButton(
          label: widget.label,
          onPressed: widget.isLoading ? null : widget.onPressed,
          isLoading: widget.isLoading,
          icon: widget.icon,
        );
      case SkyButtonVariant.danger:
        return _DangerButton(
          label: widget.label,
          onPressed: widget.isLoading ? null : widget.onPressed,
          isLoading: widget.isLoading,
          icon: widget.icon,
        );
      case SkyButtonVariant.google:
        return _GoogleButton(
          label: widget.label,
          onPressed: widget.isLoading ? null : widget.onPressed,
          isLoading: widget.isLoading,
        );
    }
  }
}

// ── Primary ──────────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null
            ? null
            : const LinearGradient(
                colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
        color: onPressed == null ? const Color(0xFF2A2A3A) : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: onPressed == null
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0072FF).withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        icon!,
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Secondary ────────────────────────────────────────────────────────────────

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A3A), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF00C6FF),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        icon!,
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFF00C6FF),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Outlined ─────────────────────────────────────────────────────────────────

class _OutlinedButton extends StatelessWidget {
  const _OutlinedButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00C6FF).withOpacity(0.6),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF00C6FF),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        icon!,
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          color: const Color(0xFF00C6FF).withOpacity(0.9),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Danger ───────────────────────────────────────────────────────────────────

class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF4757).withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFFFF4757),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        icon!,
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFFFF4757),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Google ────────────────────────────────────────────────────────────────────

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF4285F4),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _GoogleLogo(),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -1.57, 3.14, false, paint..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.22);

    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        3.14, 1.57, false, paint);

    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        1.57, 1.57, false, paint);

    paint.color = const Color(0xFF34A853);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        0.0, 1.57, false, paint);

    paint
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.56, paint);

    paint.color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(
          center.dx - radius * 0.02,
          center.dy - radius * 0.22,
          radius * 1.02,
          radius * 0.44),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}