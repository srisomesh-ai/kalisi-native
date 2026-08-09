import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';
import 'app/providers.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Use the platform's native crypto (fast, and provides P-256 ECDH on Android/iOS).
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: KalisiApp()));
}

class KalisiApp extends ConsumerWidget {
  const KalisiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Kalisi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const _Root(),
    );
  }
}

/// Decides the first screen: onboarding if no active persona, else home.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persona = ref.watch(activePersonaProvider);
    return persona.when(
      loading: () => const _Splash(),
      error: (e, _) => const OnboardingScreen(),
      data: (p) => p == null ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [KColors.gold, KColors.ember],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 18),
            Text('Kalisi', style: AppTheme.display(size: 26, color: s.text)),
          ],
        ),
      ),
    );
  }
}
