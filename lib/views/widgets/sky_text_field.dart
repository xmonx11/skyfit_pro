import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SkyTextField extends StatefulWidget {
  const SkyTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.prefixIcon,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.onChanged,
    this.inputFormatters,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.maxLines = 1,
    this.errorText, // 👈 new
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? prefixIcon;
  final bool isPassword;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction textInputAction;
  final void Function(String)? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final int maxLines;
  final String? errorText; // 👈 new

  @override
  State<SkyTextField> createState() => _SkyTextFieldState();
}

class _SkyTextFieldState extends State<SkyTextField> {
  bool _obscure = true;
  bool _isFocused = false;
  String? _errorText;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _errorText = widget.errorText; // 👈 init from external
    _focusNode.addListener(() {
      setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void didUpdateWidget(SkyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 👇 sync external errorText changes in real-time
    if (oldWidget.errorText != widget.errorText) {
      setState(() => _errorText = widget.errorText);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool get _hasError => _errorText != null && _errorText!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Text(
          widget.label,
          style: TextStyle(
            color: _hasError
                ? const Color(0xFFFF4757)
                : _isFocused
                    ? const Color(0xFF00C6FF)
                    : const Color(0xFF8888AA),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),

        // Field container
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: const Color(0xFF12121E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hasError
                  ? const Color(0xFFFF4757).withOpacity(0.7)
                  : _isFocused
                      ? const Color(0xFF00C6FF)
                      : const Color(0xFF2A2A3A),
              width: _isFocused || _hasError ? 1.5 : 1.0,
            ),
            boxShadow: _hasError
                ? [
                    BoxShadow(
                      color: const Color(0xFFFF4757).withOpacity(0.08),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ]
                : _isFocused
                    ? [
                        BoxShadow(
                          color: const Color(0xFF00C6FF).withOpacity(0.12),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.isPassword && _obscure,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            textInputAction: widget.textInputAction,
            onFieldSubmitted: widget.onFieldSubmitted,
            autofillHints: widget.autofillHints,
            enabled: widget.enabled,
            maxLines: widget.isPassword ? 1 : widget.maxLines,
            style: const TextStyle(
              color: Color(0xFFE0E0F0),
              fontSize: 15,
              letterSpacing: 0.3,
            ),
            onChanged: (v) {
              widget.onChanged?.call(v);
              // Re-validate on change if already showing error
              if (widget.errorText == null && _hasError && widget.validator != null) {
                final result = widget.validator!(v);
                setState(() => _errorText = result);
              }
            },
            validator: (v) {
              // Only run internal validator if no external errorText
              if (widget.errorText != null) return null;
              final result = widget.validator?.call(v);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _errorText = result);
              });
              return null;
            },
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                color: const Color(0xFF8888AA).withOpacity(0.6),
                fontSize: 14,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(
                      widget.prefixIcon,
                      color: _hasError
                          ? const Color(0xFFFF4757).withOpacity(0.7)
                          : _isFocused
                              ? const Color(0xFF00C6FF)
                              : const Color(0xFF555570),
                      size: 20,
                    )
                  : null,
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xFF555570),
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              errorStyle: const TextStyle(fontSize: 0, height: 0),
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
            ),
          ),
        ),

        // Custom error message below field
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFFF4757),
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: const TextStyle(
                            color: Color(0xFFFF4757),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}