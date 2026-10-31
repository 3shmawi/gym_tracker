import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against shipping secrets in the app or the repository.
/// Anything compiled into the app can be extracted, so only publishable
/// keys may ever live in env files — and never in source code.
void main() {
  const scannedDirs = ['lib', 'android', 'ios', 'website', 'supabase', 'env'];
  const skippedDirs = {
    'build',
    '.gradle',
    'Pods',
    '.symlinks',
    'ephemeral',
    '.dart_tool',
    'gen',
  };
  const textExtensions = {
    '.dart', '.kt', '.kts', '.java', '.swift', '.m', '.xml', '.plist', //
    '.json', '.yaml', '.yml', '.properties', '.gradle', '.html', '.js',
    '.css', '.sql', '.xcconfig', '.entitlements', '.toml', '.env',
  };

  final forbidden = <String, RegExp>{
    'private key': RegExp('BEGIN [A-Z ]*PRIVATE KEY'),
    'Supabase secret key': RegExp('sb_secret_[A-Za-z0-9_-]{10,}'),
    'AWS access key': RegExp('AKIA[0-9A-Z]{16}'),
    'Stripe live key': RegExp('sk_live_[0-9A-Za-z]{10,}'),
    'GitHub token': RegExp('gh[pousr]_[A-Za-z0-9]{30,}'),
    'Google API key': RegExp('AIza[0-9A-Za-z_-]{35}'),
    'hard-coded keystore password': RegExp(
      r'(storePassword|keyPassword)\s*=\s*"[^"]+"',
    ),
  };

  // Only checked in client code: supabase/ legitimately names the role in
  // config.toml and in policies (`to service_role`).
  final clientOnly = <String, RegExp>{
    'Supabase service role': RegExp('service_role', caseSensitive: false),
  };

  Iterable<File> sourceFiles() sync* {
    for (final dir in scannedDirs) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File) continue;
        final parts = entity.uri.pathSegments;
        if (parts.any(skippedDirs.contains)) continue;
        final name = parts.last;
        // Local, git-ignored files that legitimately hold real values.
        if (name == 'key.properties' || name == 'local.properties') continue;
        final dot = name.lastIndexOf('.');
        if (dot < 0 || !textExtensions.contains(name.substring(dot))) {
          continue;
        }
        yield entity;
      }
    }
  }

  test('no secrets in source, native or website files', () {
    final findings = <String>[];
    for (final file in sourceFiles()) {
      final String content;
      try {
        content = file.readAsStringSync();
      } on FileSystemException {
        continue;
      }
      final isClient = !file.path.startsWith('supabase');
      final patterns = {...forbidden, if (isClient) ...clientOnly};
      for (final MapEntry(key: label, value: pattern) in patterns.entries) {
        if (pattern.hasMatch(content)) findings.add('$label → ${file.path}');
      }
    }
    expect(findings, isEmpty, reason: findings.join('\n'));
  });

  test('env/example.json holds no values except public hosts', () {
    final example = jsonDecode(
      File('env/example.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final filled = example.entries.where(
      (e) => e.value is String && (e.value as String).isNotEmpty,
    );
    final allowed = filled.where((e) => e.key.endsWith('_HOST'));
    expect(filled.length, allowed.length, reason: 'Keep example.json empty.');
  });

  test('.gitignore keeps env files and signing material out of git', () {
    final gitignore = File('.gitignore').readAsStringSync();
    for (final entry in [
      'env/*.json',
      'android/key.properties',
      '*.jks',
      '*.p8',
      '*.p12',
    ]) {
      expect(gitignore, contains(entry), reason: '$entry must be ignored');
    }
  });
}
