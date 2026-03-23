import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));
  runApp(const ProviderScope(child: RunneStApp()));
}

class RunneStApp extends StatelessWidget {
  const RunneStApp({super.key});
  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'RUNNE\$T',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: CupertinoColors.white,
        scaffoldBackgroundColor: Color(0xFF080808),
        barBackgroundColor: Color(0xFF0A0A0A),
        textTheme: CupertinoTextThemeData(
          primaryColor: CupertinoColors.white,
          textStyle: TextStyle(
            color: CupertinoColors.white,
            fontFamily: '.SF Pro Text',
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}