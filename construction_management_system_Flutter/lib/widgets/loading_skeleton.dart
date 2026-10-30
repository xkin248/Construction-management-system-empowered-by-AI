import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable loading skeletons.
///
/// Every data-driven screen used to show a full-screen `CircularProgressIndicator`
/// as its only first-paint state. That reads as a frozen app on slow site
/// networks and gives no sense of what is coming. These skeletons mirror the
/// real layout (cards, rows, KPI tiles) so the screen feels instant and never
/// jumps when the data lands.
///
/// All pieces are pure presentation: they take no data and trigger no requests.

/// Static grey block used as a building unit.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
    this.color,
  });

  final double? width;
  final double? height;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? AppColors.border.withValues(alpha: AppColors.isDark ? 0.55 : 0.7),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Card-shaped skeleton surface matching the real `sectionCard` surfaces.
class SkeletonPanel extends StatelessWidget {
  const SkeletonPanel({
    super.key,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.child,
    this.radius = 16,
  });

  final double? height;
  final EdgeInsetsGeometry padding;
  final Widget? child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: child,
    );
  }
}

/// Owns the single pulse animation shared by every child skeleton block.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(begin: 0.55, end: 1.0)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

/// One list row: leading avatar + two text lines.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key, this.leading = true, this.trailing = false});

  final bool leading;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return SkeletonPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      radius: 14,
      child: Row(
        children: [
          if (leading) ...[
            const SkeletonBox(width: 36, height: 36, radius: 18),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 160, height: 12, radius: 6),
                SizedBox(height: 8),
                SkeletonBox(width: 96, height: 10, radius: 5),
              ],
            ),
          ),
          if (trailing) ...[
            const SizedBox(width: 12),
            const SkeletonBox(width: 48, height: 20, radius: 10),
          ],
        ],
      ),
    );
  }
}

class _SkeletonStatRow extends StatelessWidget {
  const _SkeletonStatRow({this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          const Expanded(child: SkeletonBox(height: 68, radius: 14)),
        ],
      ],
    );
  }
}

/// Generic list skeleton: optional stats strip on top, then [rows] rows.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rows = 5,
    this.showHeader = false,
    this.headerStatCount = 4,
    this.padding = const EdgeInsets.all(16),
  });

  final int rows;
  final bool showHeader;
  final int headerStatCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: rows + (showHeader ? 1 : 0),
        itemBuilder: (context, index) {
          if (showHeader && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _SkeletonStatRow(count: headerStatCount),
            );
          }
          return const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SkeletonTile(),
          );
        },
      ),
    );
  }
}

/// Two-column (or wider) card grid skeleton for the Files page.
class SkeletonCardGrid extends StatelessWidget {
  const SkeletonCardGrid({
    super.key,
    this.count = 6,
    this.columns = 2,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
  });

  final int count;
  final int columns;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.05,
        ),
        itemCount: count,
        itemBuilder: (context, index) => const SkeletonPanel(
          padding: EdgeInsets.all(14),
          radius: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 34, height: 34, radius: 10),
              SizedBox(height: 12),
              SkeletonBox(width: 110, height: 11, radius: 6),
              SizedBox(height: 8),
              SkeletonBox(width: 70, height: 9, radius: 5),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashboard skeleton: hero card, KPI strip, section heading and preview rows.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key, this.padding = const EdgeInsets.all(16)});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: const [
          SkeletonBox(height: 104, radius: 18),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 82, radius: 14)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 82, radius: 14)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 82, radius: 14)),
            ],
          ),
          SizedBox(height: 22),
          SkeletonBox(width: 140, height: 14, radius: 6),
          SizedBox(height: 12),
          SkeletonTile(),
          SizedBox(height: 10),
          SkeletonTile(),
          SizedBox(height: 10),
          SkeletonTile(),
        ],
      ),
    );
  }
}

/// Detail-page skeleton: header card plus stacked content cards.
class SkeletonDetail extends StatelessWidget {
  const SkeletonDetail({super.key, this.padding = const EdgeInsets.all(16)});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: const [
          SkeletonBox(height: 96, radius: 18),
          SizedBox(height: 12),
          SkeletonBox(height: 128, radius: 16),
          SizedBox(height: 12),
          SkeletonBox(height: 96, radius: 16),
          SizedBox(height: 12),
          SkeletonBox(height: 152, radius: 16),
        ],
      ),
    );
  }
}

/// Small inline skeleton for a single card section (worker dashboard tiles).
class SkeletonSection extends StatelessWidget {
  const SkeletonSection({super.key, this.lines = 3, this.padding = const EdgeInsets.all(16)});

  final int lines;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              const SkeletonBox(height: 14, radius: 6),
            ],
          ],
        ),
      ),
    );
  }
}
