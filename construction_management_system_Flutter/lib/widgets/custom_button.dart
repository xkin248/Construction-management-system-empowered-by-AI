import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/styles.dart';

enum ButtonType { primary, secondary, danger, ghost }

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ButtonType type;
  final bool fullWidth;
  final bool loading;
  final IconData? prefixIcon;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.type = ButtonType.primary,
    this.fullWidth = true,
    this.loading = false,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = _bgColor();
    final fg = _fgColor();
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: type == ButtonType.secondary
              ? const BorderSide(color: AppColors.borderColor)
              : null,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: AppStyles.radius8),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (prefixIcon != null) ...[
                    Icon(prefixIcon, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Text(text,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  Color _bgColor() => switch (type) {
        ButtonType.primary => AppColors.accentOrange,
        ButtonType.secondary => AppColors.cardColor,
        ButtonType.danger => AppColors.danger,
        ButtonType.ghost => Colors.transparent,
      };

  Color _fgColor() => switch (type) {
        ButtonType.primary => Colors.white,
        ButtonType.secondary => AppColors.textPrimary,
        ButtonType.danger => Colors.white,
        ButtonType.ghost => AppColors.primary,
      };
}