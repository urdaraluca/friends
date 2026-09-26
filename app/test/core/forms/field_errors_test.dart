import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/forms/field_errors.dart';
import 'package:friends/core/forms/validators.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const validation = ProblemException(
    status: 422,
    code: ErrorCodes.validationError,
    errors: [
      FieldError(field: 'email', message: 'Bad email', type: 'value_error'),
      FieldError(field: 'email', message: 'Second', type: 'value_error'),
      FieldError(field: 'birthday.day', message: 'Bad day', type: 'x'),
      FieldError(field: 'avatar_url', message: 'Bad URL', type: 'x'),
    ],
  );

  group('FieldErrors', () {
    test('maps errors[] by field, first message wins', () {
      final errors = FieldErrors.fromError(validation);

      expect(errors['email'], 'Bad email');
      expect(errors['birthday'], 'Bad day');
      expect(errors['birthday.day'], 'Bad day');
      expect(errors['password'], isNull);
      expect(errors.has('avatar_url'), isTrue);
    });

    test('codeFields put field-less codes onto a field', () {
      const taken = ProblemException(status: 409, code: ErrorCodes.emailTaken);

      final errors = FieldErrors.fromError(
        taken,
        codeFields: const {ErrorCodes.emailTaken: 'email'},
      );
      final custom = FieldErrors.fromError(
        taken,
        codeFields: const {ErrorCodes.emailTaken: 'email'},
        messages: const {ErrorCodes.emailTaken: 'Taken!'},
      );

      expect(errors['email'], 'An account with this email already exists.');
      expect(custom['email'], 'Taken!');
    });

    test('non-problem errors have no field errors', () {
      expect(FieldErrors.fromError(const NetworkException()).isEmpty, isTrue);
    });

    test('without removes a field and the paths below it', () {
      final errors = FieldErrors.fromError(validation);

      expect(errors.without('birthday').has('birthday.day'), isFalse);
      expect(errors.without('email')['email'], isNull);
      expect(errors.without('password'), same(errors));
    });

    test('unclaimed lists errors for fields the form does not show', () {
      final errors = FieldErrors.fromError(validation);

      expect(errors.unclaimed({'email', 'birthday'}), ['avatar_url: Bad URL']);
    });
  });

  group('ServerErrorsMixin', () {
    testWidgets('shows server errors on fields and the rest in a banner', (
      tester,
    ) async {
      final key = GlobalKey<_TestFormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: _TestForm(key: key)),
        ),
      );

      key.currentState!.showServerError(validation, fields: {'email'});
      await tester.pump();

      expect(find.text('Bad email'), findsOneWidget);
      expect(find.textContaining('avatar_url: Bad URL'), findsOneWidget);
      expect(find.textContaining('birthday.day: Bad day'), findsOneWidget);

      // Editing the field clears its server error.
      await tester.enterText(find.byType(TextFormField), 'new@example.com');
      await tester.pump();
      expect(find.text('Bad email'), findsNothing);
    });

    testWidgets('errors without fields go to the banner', (tester) async {
      final key = GlobalKey<_TestFormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: _TestForm(key: key)),
        ),
      );

      key.currentState!.showServerError(
        const ProblemException(status: 401, code: 'invalid_credentials'),
        fields: {'email'},
      );
      await tester.pump();

      expect(find.text('banner: Wrong email or password.'), findsOneWidget);

      key.currentState!.clearServerErrors();
      await tester.pump();
      expect(find.textContaining('banner'), findsNothing);
    });
  });

  group('Validators', () {
    test('required', () {
      final validator = Validators.required('a name', max: 3);

      expect(validator('  '), 'Enter a name.');
      expect(validator('abcd'), 'Use at most 3 characters.');
      expect(validator(' abc '), isNull);
    });

    test('email', () {
      expect(Validators.email(''), 'Enter your email.');
      expect(Validators.email('nope'), 'Enter a valid email address.');
      expect(Validators.email(' ana@example.com '), isNull);
    });

    test('newPassword counts code points (10..128)', () {
      expect(Validators.newPassword('123456789'), isNotNull);
      expect(Validators.newPassword('😀' * 10), isNull);
      expect(Validators.newPassword('x' * 129), isNotNull);
      expect(Validators.currentPassword(''), isNotNull);
      expect(Validators.currentPassword('x'), isNull);
    });

    test('optionalInviteCode', () {
      expect(Validators.optionalInviteCode(''), isNull);
      expect(Validators.optionalInviteCode('abcde-fghjk'), isNull);
      expect(Validators.optionalInviteCode('nope'), isNotNull);
    });
  });
}

class _TestForm extends StatefulWidget {
  const new({super.key});

  @override
  State<_TestForm> createState() => _TestFormState();
}

class _TestFormState extends State<_TestForm> with ServerErrorsMixin {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (formError case final message?) Text('banner: $message'),
        TextFormField(
          forceErrorText: serverError('email'),
          onChanged: (_) => clearServerError('email'),
        ),
      ],
    );
  }
}
