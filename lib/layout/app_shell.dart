import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_bottom_navigation_bar.dart';

class AppShell extends StatelessWidget {
  final int currentIndex;
  final bool isAdmin;
  final ValueChanged<int> onChangePage;
  final Widget child;

  const AppShell({
    super.key,
    required this.currentIndex,
    required this.isAdmin,
    required this.onChangePage,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final screenType = breakpointOf(context);
    final desktopLayout = isDesktop(context);

    if (!desktopLayout) {
      return Scaffold(
        backgroundColor: backgroundColor,
        bottomNavigationBar: CustomBottomNavigationBar(
          items: [
            const CustomBottomNavigationBarItem(icon: Icons.home, label: 'Home'),
            const CustomBottomNavigationBarItem(icon: Icons.calendar_month, label: 'Calendario'),
            if (isAdmin) const CustomBottomNavigationBarItem(icon: Icons.people, label: 'Utenti'),
          ],
          colors: const CustomBottomNavigationBarColors(
            backgroundColor: primaryLightColor,
            selectedItemColor: onPrimaryColor,
            unselectedItemColor: surfaceColor,
          ),
          onChangePage: onChangePage,
          currentIndex: currentIndex,
        ),
        body: child,
      );
    }

    final double? maxContentWidth = maxContentWidthFor(screenType);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: surfaceColor,
            selectedIndex: currentIndex,
            onDestinationSelected: onChangePage,
            labelType: NavigationRailLabelType.all,
            selectedIconTheme: const IconThemeData(color: onPrimaryColor),
            unselectedIconTheme: const IconThemeData(color: onSurfaceVariantColor),
            selectedLabelTextStyle: const TextStyle(color: onPrimaryColor),
            unselectedLabelTextStyle: const TextStyle(color: onSurfaceVariantColor),
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Home'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: Text('Calendario'),
              ),
              if (isAdmin)
                const NavigationRailDestination(
                  icon: Icon(Icons.people_outline),
                  selectedIcon: Icon(Icons.people),
                  label: Text('Utenti'),
                ),
              if (isAdmin)
                const NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Dashboard'),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxContentWidth ?? double.infinity,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
