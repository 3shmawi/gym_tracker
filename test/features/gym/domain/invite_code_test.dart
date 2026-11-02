import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';

void main() {
  group(InviteCode, () {
    test('accepts a code in any case, with spaces around it', () {
      expect(InviteCode.tryParse('K7M2QX')!.value, 'K7M2QX');
      expect(InviteCode.tryParse('k7m2qx')!.value, 'K7M2QX');
      expect(InviteCode.tryParse('  hjk2mn \n')!.value, 'HJK2MN');
    });

    test('every letter and digit of the alphabet works, nothing else', () {
      expect(InviteCode.alphabet.length, 31);
      for (final c in InviteCode.alphabet.split('')) {
        expect(InviteCode.tryParse(c * 6), isNotNull, reason: c);
      }
      for (final c in '01OIL'.split('')) {
        expect(InviteCode.tryParse('ABCDE$c'), isNull, reason: c);
        expect(InviteCode.tryParse('${c}BCDEF'), isNull, reason: c);
      }
    });

    test('hostile and malformed text is not a code', () {
      final huge = 'A' * 100000;
      for (final raw in <String?>[
        null,
        '',
        ' ',
        'ABC23',
        'ABC2345',
        'ABC 234',
        'ABC-234',
        'ABC234;',
        'ABC\n234',
        'A\u0000BC234',
        '<script>',
        "'; drop table invites; --",
        'https://evil.example',
        'javascript:1',
        '%41%42%43%32%33%34',
        // look-alikes that would fold into valid letters if upper-cased
        'ſſſſſſ',
        'ßßßßßß',
        'ＡＢＣ２３４',
        'ÄBC234',
        'ı23456',
        'ABC23٤',
        huge,
      ]) {
        expect(
          InviteCode.tryParse(raw),
          isNull,
          reason: '$raw'.substring(0, '$raw'.length.clamp(0, 30)),
        );
      }
    });

    test('clean() keeps only what may be typed', () {
      expect(InviteCode.clean('k7m-2qx '), 'K7M2QX');
      expect(InviteCode.clean('k7m2qxzzzz'), 'K7M2QX');
      expect(InviteCode.clean('0O1IL'), '');
      expect(InviteCode.clean('<b>k7</b>'), 'BK7B');
      expect(InviteCode.clean('ßſ'), '');
      expect(InviteCode.clean(''), '');
      expect(InviteCode.clean('A' * 100000), 'AAAAAA');
    });

    test('is a value, and never prints itself', () {
      expect(InviteCode.tryParse('k7m2qx'), InviteCode.tryParse('K7M2QX'));
      expect(
        InviteCode.tryParse('K7M2QX').hashCode,
        InviteCode.tryParse('k7m2qx').hashCode,
      );
      expect(InviteCode.tryParse('K7M2QX').toString(), isNot(contains('K7M')));
    });
  });
}
