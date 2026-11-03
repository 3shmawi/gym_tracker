import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/cloudinary_url.dart';
import 'package:gym_tracker/core/media/media_cache.dart';

Uri? build(String publicId, {String cloud = 'azm', PictureSize? size}) =>
    CloudinaryUrl.picture(
      cloudName: cloud,
      publicId: publicId,
      size: size ?? PictureSize.large,
    );

void main() {
  group('CloudinaryUrl.picture', () {
    test('builds the documented delivery URL with fixed transformations', () {
      expect(
        build('exercises/ek-0055-tension').toString(),
        'https://res.cloudinary.com/azm/image/upload/'
        'c_limit,w_640,f_webp,q_auto/exercises/ek-0055-tension.png',
      );
      expect(
        build(
          'exercises/ek-0055-relaxation',
          size: PictureSize.thumb,
        ).toString(),
        'https://res.cloudinary.com/azm/image/upload/'
        'c_limit,w_160,f_webp,q_auto/exercises/ek-0055-relaxation.png',
      );
    });

    test('every URL it builds is one the cache may fetch', () {
      for (final size in PictureSize.values) {
        expect(
          MediaCache.isAllowed(build('exercises/ek-1', size: size)!),
          isTrue,
        );
      }
    });

    const hostileIds = <String, String>{
      'empty': '',
      'no folder': 'ek-0055-tension',
      'other folder': 'avatars/ek-0055-tension',
      'nested folder': 'exercises/x/ek-0055',
      'parent dir': 'exercises/../secret',
      'dot segment': 'exercises/./ek',
      'leading parent': '../exercises/ek-0055',
      'absolute URL': 'https://evil.example/exercises/ek-0055',
      'scheme-relative': '//evil.example/x',
      'javascript': 'javascript:alert(1)',
      'data URI': 'data:image/png;base64,AAAA',
      'upper case': 'exercises/EK-0055-tension',
      'upper folder': 'Exercises/ek-0055',
      'extension': 'exercises/ek-0055.png',
      'query': 'exercises/ek-0055?x=1',
      'fragment': 'exercises/ek-0055#x',
      'percent-encoded slash': 'exercises%2Fek-0055',
      'percent-encoded dot': 'exercises/%2e%2e',
      'backslash': r'exercises\ek-0055',
      'space': 'exercises/ek 0055',
      'newline': 'exercises/ek-0055\n',
      'trailing slash': 'exercises/ek-0055/',
      'transformation smuggled': 'exercises/ek,w_99999',
      'Cyrillic look-alike е': 'exercises/еk-0055',
      'full-width letters': 'exercises/ｅｋ-0055',
      'leading dash': 'exercises/-ek',
      'too long': 'exercises/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    };
    for (final MapEntry(key: name, value: id) in hostileIds.entries) {
      test('refuses a public id: $name', () {
        expect(build(id), isNull);
      });
    }

    test('accepts the longest allowed id and refuses one more character', () {
      final ok = 'exercises/${'a' * 80}';
      expect(build(ok), isNotNull);
      expect(build('${ok}a'), isNull);
    });

    const hostileClouds = <String, String>{
      'empty': '',
      'host': 'evil.example',
      'with a path': 'azm/../x',
      'upper case': 'AZM',
      'space': 'a zm',
      'at sign': 'azm@evil',
      'port': 'azm:443',
      'Cyrillic': 'аzm',
      'percent': 'azm%2F',
    };
    for (final MapEntry(key: name, value: cloud) in hostileClouds.entries) {
      test('refuses a cloud name: $name', () {
        expect(build('exercises/ek-0055-tension', cloud: cloud), isNull);
      });
    }
  });

  group('MediaCache.isAllowed', () {
    test('only https on the allowed hosts, no port or user info', () {
      expect(
        MediaCache.isAllowed(Uri.parse('https://res.cloudinary.com/azm/x.png')),
        isTrue,
      );
      for (final url in [
        'http://res.cloudinary.com/azm/x.png',
        'https://res.cloudinary.com.evil.example/x.png',
        'https://evil.example/res.cloudinary.com/x.png',
        'https://user@res.cloudinary.com/x.png',
        'https://res.cloudinary.com:8443/x.png',
        'file:///etc/passwd',
        'javascript:alert(1)',
      ]) {
        expect(MediaCache.isAllowed(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });
}
