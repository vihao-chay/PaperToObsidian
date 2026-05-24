import 'package:flutter/material.dart';

import 'screens/dashbroad_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF to Obsidian Knowledge Nodes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF72B7FF),
          secondary: Color(0xFF2FBF71),
          surface: Color(0xFF171B22),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F1115),
      ),
      home: const DashboardScreen(),
    );
  }
}
