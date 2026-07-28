import 'package:flutter/material.dart';

class ResponsiveCardGridItem {
  final Widget child;
  final bool fullWidth;

  const ResponsiveCardGridItem({
    required this.child,
    this.fullWidth = false,
  });

  const ResponsiveCardGridItem.fullWidth({required this.child})
      : fullWidth = true;
}

class ResponsiveCardGrid extends StatelessWidget {
  final List<ResponsiveCardGridItem> children;
  final double spacing;
  final double runSpacing;
  final double narrowBreakpoint;
  final EdgeInsetsGeometry? padding;
  final bool forceOddLastFullWidth;

  const ResponsiveCardGrid({
    super.key,
    required this.children,
    this.spacing = 10,
    this.runSpacing = 10,
    this.narrowBreakpoint = 300,
    this.padding,
    this.forceOddLastFullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columns = availableWidth < narrowBreakpoint ? 1 : 2;
        final tileWidth = columns == 1
            ? availableWidth
            : (availableWidth - spacing) / 2;
        final shouldPromoteLast =
            forceOddLastFullWidth &&
            columns > 1 &&
            children.isNotEmpty &&
            children.length.isOdd;

        return Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            children: List.generate(children.length, (index) {
              final item = children[index];
              final fullWidth =
                  item.fullWidth || (shouldPromoteLast && index == children.length - 1);
              return SizedBox(
                width: fullWidth ? availableWidth : tileWidth,
                child: item.child,
              );
            }),
          ),
        );
      },
    );
  }
}
