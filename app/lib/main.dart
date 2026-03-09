import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/features/home/presentation/home_screen.dart';
import 'src/features/auth/presentation/login_screen.dart';
import 'src/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RelicArchiveApp());
}

class RelicArchiveApp extends StatefulWidget {
  const RelicArchiveApp({super.key});

  @override
  State<RelicArchiveApp> createState() => _RelicArchiveAppState();
}

class _RelicArchiveAppState extends State<RelicArchiveApp> {
  Widget? _home;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
    final hasToken = prefs.getString('access_token') != null;

    if (mounted) {
      setState(() {
        if (!hasSeenOnboarding) {
          _home = const OnboardingScreen();
        } else {
          _home = hasToken ? const HomeScreen() : const LoginScreen();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_home == null) {
      // Show a simple loading screen while initializing
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: const Color(0xFF8D6E63)),
          ),
        ),
      );
    }

    return MaterialApp(
      title: '旧物志',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8D6E63),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8D6E63),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: _home,
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}
