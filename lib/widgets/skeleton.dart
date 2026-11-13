import 'package:flutter/material.dart';
import 'package:mangaloader/theme/app_tokens.dart';
import 'package:shimmer/shimmer.dart';

/// Loading placeholders that reuse the geometry of the real content, so the
/// list or grid does not jump when the data arrives. Colors come from the
/// active color scheme, which keeps the skeletons readable in light, dark and
/// AMOLED themes alike.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius:
              borderRadius ?? BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),
    );
  }
}

/// Grid of cover-shaped placeholders mirroring the catalog and library grids.
class SkeletonMangaGrid extends StatelessWidget {
  const SkeletonMangaGrid({
    super.key,
    this.itemCount = 12,
    this.crossAxisCount,
    this.childAspectRatio = 0.65,
    this.padding = const EdgeInsets.all(12),
    this.spacing = 10,
  });

  final int itemCount;

  /// When null the column count is derived exactly like the real grids
  /// (a 160 px minimum tile width, clamped to 2..6 columns).
  final int? crossAxisCount;
  final double childAspectRatio;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = crossAxisCount ??
            (constraints.maxWidth / 160).floor().clamp(2, 6);
        return SkeletonShimmer(
          child: GridView.builder(
            padding: padding,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: childAspectRatio,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) => const SkeletonBox(
              borderRadius: BorderRadius.all(
                Radius.circular(AppTokens.radiusLg),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Row-shaped placeholders for the compact library list layout: a cover
/// thumbnail next to two text lines.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 8,
    this.padding = const EdgeInsets.all(12),
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppTokens.spaceSm),
        itemBuilder: (context, index) => const SizedBox(
          height: 86,
          child: Row(
            children: [
              SkeletonBox(
                width: 50,
                height: 70,
                borderRadius: BorderRadius.all(
                  Radius.circular(AppTokens.radiusSm),
                ),
              ),
              SizedBox(width: AppTokens.spaceMd),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: 0.72,
                      child: SkeletonBox(height: 12),
                    ),
                    SizedBox(height: AppTokens.spaceSm),
                    FractionallySizedBox(
                      widthFactor: 0.45,
                      child: SkeletonBox(height: 10),
                    ),
                    SizedBox(height: AppTokens.spaceXs),
                    FractionallySizedBox(
                      widthFactor: 0.28,
                      child: SkeletonBox(height: 8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Applies the shimmer sweep over a group of skeleton shapes. The tone is a
/// translucent wash of the brand accent instead of a fixed grey, so the
/// placeholder belongs to whichever theme is active.
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final base = Color.alphaBlend(
      AppTokens.accent.withValues(alpha: 0.12),
      surface,
    );
    final highlight = Color.alphaBlend(
      AppTokens.accent.withValues(alpha: 0.30),
      surface,
    );
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: child,
    );
  }
}