import 'package:flutter/material.dart';

const double kBreakpointSm = 600;
const double kBreakpointMd = 900;
const double kBreakpointLg = 1200;
const double kBreakpointXl = 1600;

enum ScreenType {
  mobile,
  tablet,
  desktop,
  largeDesktop,
}

ScreenType breakpointOf(BuildContext context) {
  final width = MediaQuery.of(context).size.width;

  if (width >= kBreakpointXl) {
    return ScreenType.largeDesktop;
  }
  if (width >= kBreakpointMd) {
    return ScreenType.desktop;
  }
  if (width >= kBreakpointSm) {
    return ScreenType.tablet;
  }

  return ScreenType.mobile;
}

bool isMobile(BuildContext context) => breakpointOf(context) == ScreenType.mobile;

bool isTablet(BuildContext context) => breakpointOf(context) == ScreenType.tablet;

bool isDesktop(BuildContext context) {
  final screenType = breakpointOf(context);
  return screenType == ScreenType.desktop || screenType == ScreenType.largeDesktop;
}

bool isLargeDesktop(BuildContext context) => breakpointOf(context) == ScreenType.largeDesktop;

double? maxContentWidthFor(ScreenType screenType) {
  switch (screenType) {
    case ScreenType.mobile:
      return null;
    case ScreenType.tablet:
      return 900;
    case ScreenType.desktop:
      return 1200;
    case ScreenType.largeDesktop:
      return 1400;
  }
}
