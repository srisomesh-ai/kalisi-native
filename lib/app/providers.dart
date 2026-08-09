import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/database.dart';
import '../data/api/api_client.dart';
import '../data/repositories/auth_repository.dart';

/// Single database instance for the app.
final dbProvider = Provider<KalisiDb>((ref) {
  final db = KalisiDb();
  ref.onDispose(db.close);
  return db;
});

/// API client.
final apiProvider = Provider<ApiClient>((ref) => ApiClient());

/// Auth repository (identity creation, login).
final authRepoProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dbProvider), ref.watch(apiProvider));
});

/// The currently active persona (null → show onboarding).
final activePersonaProvider = FutureProvider<Persona?>((ref) async {
  // Rebuilds when auth state changes.
  ref.watch(authStateProvider);
  return ref.watch(dbProvider).activePersona();
});

/// Bumped whenever auth changes (create/switch/logout) to refresh dependents.
final authStateProvider = StateProvider<int>((ref) => 0);

/// Theme mode — persisted lightly; defaults to light like the web.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);
