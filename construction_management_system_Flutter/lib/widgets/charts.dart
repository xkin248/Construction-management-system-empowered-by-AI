import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

// ──────────────── Simple Bar Chart (no labels) ────────────────
class SimpleBarChart extends StatelessWidget {
  final List<double> values;
  final double height;
  final Color? color;
  const SimpleBarChart({super.key, required this.values, this.height = 120, this.color});

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values.map((v) {
          final h = maxV <= 0 ? 4.0 : (v / maxV) * (height - 4);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                height: h < 4 ? 4 : h,
                decoration: BoxDecoration(color: color ?? AppColors.accent, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ──────────────── Labeled Bar Chart (with x-axis labels + y-axis) ────────────────
class LabeledBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final double height;
  final Color? color;
  final Color? highlightColor;

  const LabeledBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 140,
    this.color,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final yMax = ((maxV / 10).ceil() * 10).toDouble();
    final ySteps = [0, (yMax * 0.25).toInt(), (yMax * 0.5).toInt(), (yMax * 0.75).toInt(), yMax.toInt()];

    return Column(children: [
      SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Y-axis labels
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: ySteps.reversed.map((y) => Text('$y',
                maxLines: 1,
                style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted))).toList(),
          ),
          const SizedBox(width: 8),
          // Bars
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: values.asMap().entries.map((e) {
                final isLast = e.key == values.length - 1;
                final h = yMax <= 0 ? 4.0 : (e.value / yMax) * height;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Container(
                      height: h < 4 ? 4 : h,
                      decoration: BoxDecoration(
                        color: isLast ? (highlightColor ?? AppColors.blue) : (color ?? AppColors.blue),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      // X-axis labels
      Row(children: [
        const SizedBox(width: 28), // y-axis offset
        Expanded(
          child: Row(
            children: labels.map((l) => Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(l, textAlign: TextAlign.center, maxLines: 1,
                    style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
              ),
            )).toList(),
          ),
        ),
      ]),
    ]);
  }
}

// ──────────────── Dual Bar Chart (two series, e.g. predicted vs actual) ────────────────
class DualBarChart extends StatelessWidget {
  final List<double> seriesA;
  final List<double> seriesB;
  final List<String> labels;
  final double height;
  final Color? colorA;
  final Color? colorB;

  const DualBarChart({
    super.key,
    required this.seriesA,
    required this.seriesB,
    required this.labels,
    this.height = 140,
    this.colorA,
    this.colorB,
  });

  @override
  Widget build(BuildContext context) {
    final all = [...seriesA, ...seriesB];
    final maxV = all.isEmpty ? 1.0 : all.reduce((a, b) => a > b ? a : b);
    final yMax = maxV <= 0 ? 1.0 : ((maxV / 10).ceil() * 10).toDouble();
    final ySteps = [0, (yMax * 0.25).toInt(), (yMax * 0.5).toInt(), (yMax * 0.75).toInt(), yMax.toInt()];

    return Column(children: [
      SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: ySteps.reversed.map((y) => Text('$y',
                maxLines: 1,
                style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted))).toList(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(labels.length, (i) {
                final hA = yMax <= 0 ? 4.0 : (seriesA[i] / yMax) * height;
                final hB = yMax <= 0 ? 4.0 : (seriesB[i] / yMax) * height;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Expanded(
                            child: Container(
                              height: hA < 4 ? 4 : hA,
                              decoration: BoxDecoration(
                                color: (colorA ?? AppColors.blue).withValues(alpha: 0.7),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Container(
                              height: hB < 4 ? 4 : hB,
                              decoration: BoxDecoration(
                                color: (colorB ?? AppColors.green).withValues(alpha: 0.9),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        const SizedBox(width: 28),
        Expanded(
          child: Row(
            children: labels.map((l) => Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(l, textAlign: TextAlign.center, maxLines: 1,
                    style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted)),
              ),
            )).toList(),
          ),
        ),
      ]),
    ]);
  }
}

// ──────────────── Stacked Bar (attendance rate) ────────────────
class StackedProgressBar extends StatelessWidget {
  final int present;
  final int late;
  final int absent;

  const StackedProgressBar({super.key, required this.present, required this.late, required this.absent});

  @override
  Widget build(BuildContext context) {
    final total = present + late + absent;
    if (total == 0) return const SizedBox(height: 10);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 14,
        child: Row(children: [
          if (present > 0) Expanded(flex: present, child: Container(color: AppColors.green)),
          if (late > 0) Expanded(flex: late, child: Container(color: AppColors.yellow)),
          if (absent > 0) Expanded(flex: absent, child: Container(color: AppColors.red)),
        ]),
      ),
    );
  }
}

// ──────────────── Donut Chart ────────────────
class DonutSlice {
  final double value;
  final Color color;
  final String label;
  const DonutSlice(this.value, this.color, this.label);
}

class _DonutPainter extends CustomPainter {
  final List<DonutSlice> slices;
  _DonutPainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) return;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final strokeW = size.width * 0.22;
    var start = -90 * 3.1415926535 / 180;
    for (final s in slices) {
      final sweep = (s.value / total) * 2 * 3.1415926535;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect.deflate(strokeW / 2), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices;
}

class SimpleDonutChart extends StatelessWidget {
  final List<DonutSlice> slices;
  final double size;
  const SimpleDonutChart({super.key, required this.slices, this.size = 120});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _DonutPainter(slices)),
      );
}
