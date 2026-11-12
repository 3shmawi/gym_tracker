// Long fixtures read better on one line here.
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/backup/domain/usecases/email_rules.dart';

void main() {
  group('EmailRules.clean', () {
    test('a normal address is kept, trimmed', () {
      expect(EmailRules.clean('  me@example.com '), 'me@example.com');
      expect(EmailRules.clean('a.b+c@sub.example.co'), 'a.b+c@sub.example.co');
    });

    for (final bad in [
      '',
      '   ',
      'no-at-sign',
      '@example.com',
      'me@',
      'me@@example.com',
      'a@b@c.com',
      'me@example',
      'me@.example.com',
      'me@example.com.',
      '.me@example.com',
      'me.@example.com',
      'me..x@example.com',
      'me@exa mple.com',
      'me @example.com',
      'me@example.com\n',
      'me@example.com\nBcc: x@y.z',
      'me@exa\u0000mple.com',
      'me@example.com\u202E',
      'me@exa\u200Bmple.com',
      'me@-example.com',
      '<script>alert(1)</script>@x.com',
    ]) {
      test('refuses ${bad.replaceAll('\n', r'\n')}', () {
        // A trailing newline is trimmed (so it is the same address); the
        // others carry a second line, a control or an invisible mark.
        final cleaned = EmailRules.clean(bad);
        if (bad == 'me@example.com\n') {
          expect(cleaned, 'me@example.com');
        } else {
          expect(cleaned, isNull);
        }
      });
    }

    test('refuses a script-looking local part with spaces and an over-long address', () {
      expect(EmailRules.clean('<script> x@x.com'), isNull);
      expect(EmailRules.clean('a"b@x.com'), isNull);
      expect(EmailRules.clean('a(b)@x.com'), isNull);
      expect(EmailRules.clean('أحمد@example.com'), isNotNull);
      expect(EmailRules.clean('${'a' * 65}@example.com'), isNull);
      expect(EmailRules.clean('a@${'b' * 250}.com'), isNull);
      expect(EmailRules.clean('${'a' * 64}@example.com'), isNotNull);
    });
  });

  group('EmailRules.code', () {
    test('keeps the digits only, at most six', () {
      expect(EmailRules.code('123 456'), '123456');
      expect(EmailRules.code('12-34-56'), '123456');
      expect(EmailRules.code('1234567890'), '123456');
      expect(EmailRules.code('abc'), '');
      expect(
        EmailRules.code('٢٣٤'),
        '',
        reason: 'Arabic-Indic digits are not sent as they are',
      );
      expect(EmailRules.code("12'; DROP TABLE x;--34"), '1234');
    });

    test('a code is exactly six digits', () {
      expect(EmailRules.isCode('123456'), isTrue);
      expect(EmailRules.isCode('12345'), isFalse);
      expect(EmailRules.isCode('1234567'), isFalse);
      expect(EmailRules.isCode('12345a'), isFalse);
    });
  });
}
