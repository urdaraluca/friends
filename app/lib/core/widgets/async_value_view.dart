import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:material_ui/material_ui.dart';

/// Renders an [AsyncValue]: a spinner while loading, an [ErrorView] with
/// Retry on error, and [data] otherwise.
///
/// ```dart
/// AsyncValueView(
///   value: ref.watch(groupsProvider),
///   onRetry: () => ref.invalidate(groupsProvider),
///   data: (groups) => GroupList(groups: groups),
/// )
/// ```
///
/// While refreshing (`ref.invalidate`, `ref.refresh`), the previous data
/// stays on screen. After an error, a refresh (Retry) shows the spinner
/// again, so the tap has visible feedback until the new result arrives.
class AsyncValueView<T> extends StatelessWidget {
  const new({
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
    super.key,
  });

  final AsyncValue<T> value;

  /// Builds the content once a value is available.
  final Widget Function(T data) data;

  /// Shown as a Retry button on errors (usually `ref.invalidate(provider)`).
  final VoidCallback? onRetry;

  /// Replaces the default [LoadingView].
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      // Riverpod keeps showing the previous state while refreshing. That is
      // right for data, but an error would stay up (Retry still enabled)
      // until the retry finishes: up to the 10 s connect timeout offline.
      skipLoadingOnRefresh: !value.hasError,
      data: data,
      loading: () => loading ?? const LoadingView(),
      error: (error, _) => ErrorView(error: error, onRetry: onRetry),
    );
  }
}

/// Waits for every one of [futures], ignoring their errors. For
/// `RefreshIndicator.onRefresh` with `ref.refresh(provider.future)`, when
/// the screen shows the errors itself (an [AsyncValueView]):
///
/// ```dart
/// RefreshIndicator(
///   onRefresh: () => settled([ref.refresh(groupsProvider.future)]),
///   child: ...,
/// )
/// ```
Future<void> settled(Iterable<Future<Object?>> futures) => Future.wait([
  for (final future in futures)
    future.then<void>((_) {}, onError: (Object _) {}),
]);

/// A centered spinner.
class LoadingView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// A centered error message for any API error, with an optional Retry
/// button. Network errors read "Can't reach the server".
class ErrorView extends StatelessWidget {
  const new({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = isNetworkError(error);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(offline ? Icons.cloud_off : Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              offline ? "Can't reach the server" : 'Something went wrong',
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              offline
                  ? 'Check your connection and try again.'
                  : friendlyErrorMessage(error),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
