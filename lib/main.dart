import 'package:flutter/material.dart';
import 'package:mislab4/screens/calendar.dart';


void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.system);
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'mislab4 206014',
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeMode,
          home: CalendarScreen(
            onThemeToggle: (isDarkMode) {
              _themeMode.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
            },
          ),
        );
      },
    );
  }
}
