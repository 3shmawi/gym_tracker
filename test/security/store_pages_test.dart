import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The privacy policy, terms and delete-account pages must keep telling the
/// truth about gym accounts (App Review and Google Play read them), in both
/// languages (docs/decisions/gym_accounts.md §8–§9).
void main() {
  String page(String name) => File('website/$name').readAsStringSync();

  String section(String html, String lang) {
    final start = html.indexOf('<div data-lang="$lang">');
    expect(start, isNonNegative, reason: lang);
    final end = lang == 'en'
        ? html.indexOf('<div data-lang="ar">')
        : html.indexOf('</article>');
    return html.substring(start, end);
  }

  test('every page was re-dated for the gym accounts release', () {
    // Terms were last changed with the gym accounts release; the privacy
    // policy again when the captain's progress view was added.
    for (final (name, date) in [
      ('privacy.html', '2026-11-03'),
      ('terms.html', '2026-11-02'),
    ]) {
      expect(RegExp(date).allMatches(page(name)).length, 2, reason: name);
    }
  });

  group('privacy policy', () {
    final html = page('privacy.html');

    test('English says everything the decision doc promised', () {
      final en = section(html, 'en');
      for (final phrase in [
        'Gym accounts',
        'display name',
        'workouts you log <em>in that gym</em>',
        'cannot see workouts you logged on your own',
        'random account id and a random install id',
        'no password, email or phone',
        'camera is used on your phone only',
        'not recorded, stored or sent',
        'one-way hash',
        '7 days',
        'hashed network address for 30 days',
        'Leaving a gym',
        'hidden is not deleted',
        'under 18',
        'guardian',
        'Cloudflare',
        'Turnstile',
        'Cloudflare Turnstile Privacy Addendum',
        'https://www.cloudflare.com/en-gb/turnstile-privacy-policy/',
        'Progress your captain sees',
        'how many workouts you did each week',
        'which planned exercises you skipped',
        'your level and streak',
        'never calculated from workouts you log on your own',
        'The app tells you this when you join',
        'Profile → Delete account',
        'Supabase',
        'PostHog',
        'Sentry',
      ]) {
        expect(en, contains(phrase), reason: phrase);
      }
    });

    test('Arabic covers the same ground', () {
      final ar = section(html, 'ar');
      for (final phrase in [
        'حسابات الجيم',
        'الاسم الذي أعطوه لك',
        'داخل ذلك الجيم',
        'رقم تثبيت عشوائي',
        'ليس له كلمة مرور',
        'الكاميرا على هاتفك فقط',
        'لا تُسجَّل الصور',
        'بصمة (hash)',
        '7 أيام',
        '30 يوماً',
        'مغادرة الجيم',
        'والإخفاء ليس حذفاً',
        '18 عاماً',
        'ولي الأمر',
        'Cloudflare',
        'Turnstile',
        'ملحق خصوصية Cloudflare Turnstile',
        'https://www.cloudflare.com/en-gb/turnstile-privacy-policy/',
        'تقدّمك الذي يراه الكابتن',
        'عدد تمارينك كل أسبوع',
        'التمارين المخططة التي تخطيتها',
        'مستواك وسلسلة أسابيعك',
        'ولا يُحسب أبداً من تمارين سجلتها وحدك',
        'حذف الحساب',
      ]) {
        expect(ar, contains(phrase), reason: phrase);
      }
    });

    test('the two languages list the same number of items', () {
      for (final tag in ['<h2>', '<li>']) {
        expect(
          tag.allMatches(section(html, 'en')).length,
          tag.allMatches(section(html, 'ar')).length,
          reason: tag,
        );
      }
    });

    test('still says nothing is sold and nothing is used for ads', () {
      expect(
        section(html, 'en'),
        contains('do not sell your personal information'),
      );
      expect(section(html, 'ar'), contains('لا نبيع معلوماتك الشخصية'));
    });
  });

  group('terms', () {
    final html = page('terms.html');

    test('both languages cover gym accounts', () {
      expect(section(html, 'en'), contains('Gym accounts'));
      expect(section(html, 'en'), contains('expires after 7 days'));
      expect(section(html, 'en'), contains('under 18'));
      expect(section(html, 'ar'), contains('حسابات الجيم'));
      expect(section(html, 'ar'), contains('7 أيام'));
      expect(section(html, 'ar'), contains('18 عاماً'));
    });
  });

  group('delete account page (Apple 5.1.1(v), Google Play)', () {
    final html = page('delete-account.html');

    test('names the in-app path and the no-email route, in both languages', () {
      final en = section(html, 'en');
      expect(en, contains('Settings → My account'));
      expect(en, contains('Delete account'));
      expect(en, contains('no email'));
      expect(en, contains("gym owner's email"));
      expect(en, contains('within 30 days'));
      expect(en, contains('only owner'));
      final ar = section(html, 'ar');
      expect(ar, contains('الإعدادات ← حسابي'));
      expect(ar, contains('حذف الحساب'));
      expect(ar, contains('بريد مالك جيمك'));
      expect(ar, contains('30 يوماً'));
    });

    test('the Google Play deletion URL still exists in the app docs', () {
      expect(
        File('docs/release.md').readAsStringSync(),
        contains('https://azmm.pages.dev/delete-account.html'),
      );
    });
  });

  test('the pages load nothing new from third parties', () {
    for (final name in ['privacy.html', 'terms.html', 'delete-account.html']) {
      final hosts = RegExp('(?:src|href)="(https?://[^"/]+)')
          .allMatches(page(name))
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        hosts.difference({
          'https://fonts.googleapis.com',
          'https://fonts.gstatic.com',
          // A plain link to Cloudflare's Turnstile Privacy Addendum.
          'https://www.cloudflare.com',
        }),
        isEmpty,
        reason: name,
      );
    }
  });
}
