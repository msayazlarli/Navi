import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/car_selection_screen.dart';
import 'screens/map_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final savedCarJson = prefs.getString('selected_car_json');

  runApp(NaviApp(hasSelectedCar: savedCarJson != null));
}

class NaviApp extends StatelessWidget {
  final bool hasSelectedCar;

  const NaviApp({super.key, required this.hasSelectedCar});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: hasSelectedCar ? const MapScreen() : const CarSelectionScreen(),
    );
  }
}
