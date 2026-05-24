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
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF131313),
      ),
      home: const DashboardScreen(), // 👈 chuyển toàn bộ UI sang đây
    );
  }
}