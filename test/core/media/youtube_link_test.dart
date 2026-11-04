import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';

void main() {
  final doc = jsonDecode(
    File('docs/features/youtube_link_vectors.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final vectors = (doc['vectors']! as List).cast<Map<String, Object?>>();

  group('YouTubeLink.parse (shared vectors)', () {
    test('there are vectors to run', () {
      expect(vectors.length, greaterThan(40));
    });
    for (final v in vectors) {
      final input = v['input']! as String;
      final name =
          '${v['valid'] == true ? 'accepts' : 'refuses'}: ${v['note']}';
      test(name, () {
        final ref = YouTubeLink.parse(input);
        if (v['valid'] == true) {
          expect(ref, isNotNull, reason: input);
          expect(ref!.id, v['id']);
          expect(ref.start, v['start']);
          expect(ref.end, v['end']);
        } else {
          expect(ref, isNull, reason: input);
        }
      });
    }
  });

  group(YouTubeVideoRef, () {
    test('validates ids and times like the database', () {
      expect(YouTubeVideoRef.isValid('dQw4w9WgXcQ'), isTrue);
      expect(YouTubeVideoRef.isValid('dQw4w9WgXcQ', start: 0, end: 1), isTrue);
      expect(YouTubeVideoRef.isValid('short'), isFalse);
      expect(YouTubeVideoRef.isValid('dQw4w9WgXcQ', start: 5, end: 5), isFalse);
      expect(YouTubeVideoRef.isValid('dQw4w9WgXcQ', start: 43201), isFalse);
      expect(YouTubeVideoRef.isValid('dQw4w9WgXcQ', end: 0), isFalse);
    });

    test('the YouTube link is built from the id only', () {
      expect(
        const YouTubeVideoRef('dQw4w9WgXcQ', start: 90).watchUrl.toString(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90',
      );
      expect(
        const YouTubeVideoRef('dQw4w9WgXcQ').watchUrl.toString(),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });
  });
}
