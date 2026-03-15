import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/run_sessions.dart';
import '../services/storage_service.dart';

// Singleton storage service
final storageServiceProvider =
Provider<StorageService>((_) => StorageService());

// Main sessions notifier — holds the list of all runs
class SessionsNotifier extends AsyncNotifier<List<RunSession>> {
  @override
  Future<List<RunSession>> build() =>
      ref.read(storageServiceProvider).loadSessions();

  // Call this after finishing a run to refresh the list
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
            () => ref.read(storageServiceProvider).loadSessions());
  }

  // Call this after adding a photo in summary screen
  Future<void> updateSession(RunSession session) async {
    await ref.read(storageServiceProvider).updateSession(session);
    state = state.whenData((list) =>
        list.map((s) => s.id == session.id ? session : s).toList());
  }

  // Call this when user deletes a run
  Future<void> deleteSession(String id) async {
    await ref.read(storageServiceProvider).deleteSession(id);
    state =
        state.whenData((list) => list.where((s) => s.id != id).toList());
  }
}

final sessionsProvider =
AsyncNotifierProvider<SessionsNotifier, List<RunSession>>(
    SessionsNotifier.new);