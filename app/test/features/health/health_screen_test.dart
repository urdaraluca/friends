import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/features/health/data/health_repository.dart';
import 'package:friends/features/health/presentation/health_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('HealthScreen', () {
    testWidgets('shows the API version when the API is up', (tester) async {
      await tester.pumpApp(
        const HealthScreen(),
        overrides: [
          apiHealthProvider.overrideWith(
            (ref) async => const Health(
              status: HealthStatus.ok,
              version: '1.2.3',
              db: HealthDb.ok,
            ),
          ),
        ],
      );
      await tester.pump();

      expect(find.text('API ok'), findsOneWidget);
      expect(find.text('version 1.2.3'), findsOneWidget);
      expect(find.text('database ok'), findsOneWidget);
    });

    testWidgets('shows an error with a retry button when the API is down', (
      tester,
    ) async {
      await tester.pumpApp(
        const HealthScreen(),
        overrides: [
          apiHealthProvider.overrideWith(
            (ref) => Future<Health>.error(const NetworkException()),
          ),
        ],
      );
      await tester.pump();

      expect(find.text("Can't reach the server"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
