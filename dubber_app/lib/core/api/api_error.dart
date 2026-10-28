/// One error type for the whole app. No raw maps reach the UI.
class ApiError implements Exception {
  const ApiError({
    required this.code,
    required this.message,
    this.httpStatus,
    this.retryable = false,
  });

  /// Machine code from the server, e.g. `not_enough_credits`.
  final String code;

  /// Human message, already safe to show.
  final String message;

  final int? httpStatus;

  /// True when retrying the same request could succeed.
  final bool retryable;

  const ApiError.network()
      : code = 'connection_lost',
        message = 'We could not reach the server. Check your connection.',
        httpStatus = null,
        retryable = true;

  const ApiError.offline()
      : code = 'offline',
        message = 'You are offline. Saved projects are still available.',
        httpStatus = null,
        retryable = true;

  const ApiError.unknown()
      : code = 'unknown',
        message = 'Something went wrong. Please try again.',
        httpStatus = null,
        retryable = true;

  const ApiError.unauthorized()
      : code = 'unauthorized',
        message = 'Your session has expired. Please log in again.',
        httpStatus = 401,
        retryable = false;

  bool get isAuthError => code == 'unauthorized' || httpStatus == 401;

  @override
  String toString() => 'ApiError($code, $httpStatus): $message';
}

/// Result wrapper: exactly one of [value] or [error] is set.
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final ApiError error;
}
