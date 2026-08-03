import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/styles.dart';

class ComingSoon extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const ComingSoon({super.key, required this.icon, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppStyles.radius16,
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppStyles.cardShadow,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: AppStyles.radius16,
          ),
          child: Icon(icon, size: 32, color: Colors.white),
        ),
        const SizedBox(height: 20),
        Text(title, style: AppStyles.h3),
        const SizedBox(height: 6),
        Text(sub, style: AppStyles.bodySecondary, textAlign: TextAlign.center),
      ]),
    );
  }
}