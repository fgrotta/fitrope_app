import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:flutter/material.dart';

typedef BreakpointWidgetBuilder = Widget Function(
  BuildContext context,
  ScreenType screenType,
);

class BreakpointBuilder extends StatelessWidget {
  final BreakpointWidgetBuilder builder;

  const BreakpointBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, _) {
        final screenType = breakpointOf(context);
        return builder(context, screenType);
      },
    );
  }
}
