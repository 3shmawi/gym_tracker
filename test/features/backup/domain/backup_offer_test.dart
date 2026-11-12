import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/backup/domain/usecases/backup_offer.dart';
import 'package:gym_tracker/features/backup/presentation/backup_offer.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

bool offer(
  int n, {
  int dismissals = 0,
  bool enabled = false,
  bool flag = true,
}) => shouldOfferBackup(
  finishedWorkouts: n,
  dismissals: dismissals,
  enabled: enabled,
  flagOn: flag,
);

void main() {
  group('shouldOfferBackup', () {
    test('never before the 3rd workout, then on it', () {
      expect(offer(0), isFalse);
      expect(offer(1), isFalse);
      expect(offer(2), isFalse);
      expect(offer(3), isTrue);
    });

    test('"Not now" → again only after the 10th', () {
      expect(offer(3, dismissals: 1), isFalse);
      expect(offer(9, dismissals: 1), isFalse);
      expect(offer(10, dismissals: 1), isTrue);
    });

    test('twice declined: never again', () {
      expect(offer(50, dismissals: 2), isFalse);
      expect(offer(50, dismissals: 99), isFalse);
    });

    test('not when it is on already, or the flag is off', () {
      expect(offer(5, enabled: true), isFalse);
      expect(offer(5, flag: false), isFalse);
    });

    test('hostile numbers do not break it', () {
      expect(offer(-1), isFalse);
      expect(offer(1 << 40), isTrue);
      expect(offer(5, dismissals: -1), isFalse);
    });
  });

  testWidgets('the offer sheet has two answers', (tester) async {
    await tester.pumpApp(const Scaffold(body: BackupOfferSheet()));
    expect(find.text(l10nEn.backupOfferTitle), findsOneWidget);
    expect(find.byKey(const Key('backup_offer_accept')), findsOneWidget);
    expect(find.byKey(const Key('backup_offer_later')), findsOneWidget);
  });

  screensUiTests({
    'backup_offer_sheet': () => const Scaffold(body: BackupOfferSheet()),
  });
}
