import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(
    // Only change: wrap with ProviderScope
    const ProviderScope(
      child: RunneStApp(),
    ),
  );
}

class RunneStApp extends StatelessWidget {
  const RunneStApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RUNNE\$T',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080808),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF141414),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}