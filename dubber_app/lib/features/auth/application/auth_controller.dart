import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_error.dart';

class Session {
  const Session({
    required this.name,
    required this.email,
    required this.credits,
  });

  final String name;
  final String email;
  final int credits;

  Session copyWith({int? credits}) =>
      Session(name: name, email: email, credits: credits ?? this.credits);

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        name: j['name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        credits: (j['credits'] as num?)?.toInt() ?? 0,
      );
}

class AuthState {
  const AuthState({
    this.session,
    this.loading = false,
    this.error,
    this.checked = false,
  });

  final Session? session;
  final bool loading;
  final ApiError? error;

  /// True once we know whether the user is logged in.
  final bool checked;

  bool get isLoggedIn => session != null;

  AuthState copyWith({
    Session? session,
    bool? loading,
    ApiError? error,
    bool clearError = false,
    bool? checked,
  }) =>
      AuthState(
        session: session ?? this.session,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        checked: checked ?? this.checked,
      );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState()) {
    _ref.read(apiClientProvider).onSessionExpired = _logout;
  }

  final Ref _ref;

  Future<void> restore() async {
    final tokens = _ref.read(tokenStoreProvider);
    final access = await tokens.readAccess();
    if (access == null) {
      state = state.copyWith(checked: true);
      return;
    }
    try {
      final me = await _ref.read(apiProvider).me();
      state = AuthState(session: Session.fromJson(me), checked: true);
    } catch (_) {
      // Token may still be refreshable; keep the user out but don't hard-fail.
      state = state.copyWith(checked: true);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = _ref.read(apiProvider);
      final tokens = await api.login(email: email, password: password);
      await _ref
          .read(tokenStoreProvider)
          .save(access: tokens.access, refresh: tokens.refresh);
      final me = await api.me();
      state = AuthState(
        session: Session.fromJson(me),
        checked: true,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: ApiClient.toApiError(e),
      );
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = _ref.read(apiProvider);
      final tokens = await api.register(
        name: name,
        email: email,
        password: password,
      );
      await _ref
          .read(tokenStoreProvider)
          .save(access: tokens.access, refresh: tokens.refresh);
      final me = await api.me();
      state = AuthState(session: Session.fromJson(me), checked: true);
      return true;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: ApiClient.toApiError(e),
      );
      return false;
    }
  }

  Future<bool> forgotPassword(String email) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _ref.read(apiProvider).forgotPassword(email);
      state = state.copyWith(loading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: ApiClient.toApiError(e),
      );
      return false;
    }
  }

  Future<void> refreshMe() async {
    if (state.session == null) return;
    try {
      final me = await _ref.read(apiProvider).me();
      state = state.copyWith(session: Session.fromJson(me));
    } catch (_) {
      // Keep the cached session; the screen shows stale data rather than failing.
    }
  }

  Future<void> setCredits(int credits) async {
    final s = state.session;
    if (s == null) return;
    state = state.copyWith(session: s.copyWith(credits: credits));
  }

  Future<void> logout() => _logout();

  Future<void> _logout() async {
    await _ref.read(tokenStoreProvider).clear();
    state = const AuthState(checked: true);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});
