import 'package:flutter_test/flutter_test.dart';
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
            (ref) async => const ApiHealth(status: 'ok', version: '1.2.3'),
          ),
        ],
      );
      await tester.pump();

      expect(find.text('API ok'), findsOneWidget);
      expect(find.text('version 1.2.3'), findsOneWidget);
    });

    testWidgets('shows an error with a retry button when the API is down', (
      tester,
    ) async {
      await tester.pumpApp(
        const HealthScreen(),
        overrides: [
          apiHealthProvider.overrideWith(
            (ref) => Future<ApiHealth>.error(Exception('offline')),
          ),
        ],
      );
      await tester.pump();

      expect(find.text("Can't reach the API"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
