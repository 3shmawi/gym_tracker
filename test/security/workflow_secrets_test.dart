import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps CI from leaking secrets. Logs, and in a public repo everything in
/// them, can be read by anyone; GitHub only hides a secret's exact stored
/// text, not a key decoded from it. CI also runs zizmor (pinned actions,
/// token permissions, injection) — see docs/security.md → "CI and secrets".
void main() {
  final workflowDir = Directory('.github/workflows');
  final workflows = workflowDir.existsSync()
      ? workflowDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
            .toList()
      : <File>[];

  /// The `run:` scripts of a workflow, each as (first line number, text).
  List<(int, String)> runScripts(String workflow) {
    final scripts = <(int, String)>[];
    final lines = workflow.split('\n');
    final runKey = RegExp(r'^(\s*)(- )?run: ?(.*)$');
    for (var i = 0; i < lines.length; i++) {
      final match = runKey.firstMatch(lines[i]);
      if (match == null) continue;
      final value = match.group(3)!.split(' #').first.trim();
      if (!{'|', '>', '|-', '>-'}.contains(value)) {
        scripts.add((i + 1, value));
        continue;
      }
      final keyIndent =
          match.group(1)!.length + (match.group(2) == null ? 0 : 2);
      final body = <String>[];
      var j = i + 1;
      for (; j < lines.length; j++) {
        final line = lines[j];
        final indent = line.length - line.trimLeft().length;
        if (line.trim().isNotEmpty && indent <= keyIndent) break;
        body.add(line);
      }
      scripts.add((i + 1, body.join('\n')));
      i = j - 1;
    }
    return scripts;
  }

  test('secrets reach scripts only through env:, never inline', () {
    // Inline, a secret becomes part of the script text, which GitHub can
    // show when the step fails and which bypasses quoting.
    final findings = <String>[
      for (final file in workflows)
        for (final (line, script) in runScripts(file.readAsStringSync()))
          if (script.contains(r'${{ secrets.')) '${file.path}:$line',
    ];
    expect(findings, isEmpty, reason: findings.join('\n'));
  });

  test('a key written to a file is masked before anything reads it', () {
    // Variables holding a key (base64 .p8/.p12, a service-account JSON).
    final keyVar = RegExp(r'\$\{?\w*(P8|P12|PLAY|SERVICE_ACCOUNT|PRIVATE)\w*');
    final keyFile = RegExp(r'>\s*"?[^\s|;&]*\.(p8|p12|pem|json|key)\b');
    final findings = <String>[
      for (final file in workflows)
        for (final (line, script) in runScripts(file.readAsStringSync()))
          if (keyVar.hasMatch(script) &&
              keyFile.hasMatch(script) &&
              !script.contains('scripts/mask_secrets.sh'))
            '${file.path}:$line',
    ];
    expect(
      findings,
      isEmpty,
      reason:
          'Call ./scripts/mask_secrets.sh on the file right after writing '
          'it:\n${findings.join('\n')}',
    );
  });

  test('no shell tracing (set -x prints every value, secrets included)', () {
    final trace = RegExp(r'set -[a-z]*x|set -o xtrace|bash -[a-z]*x\b');
    final files = [
      ...workflows,
      for (final dir in ['scripts', 'tool'])
        if (Directory(dir).existsSync())
          ...Directory(dir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.sh')),
    ];
    final findings = <String>[
      for (final file in files)
        if (trace.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(findings, isEmpty, reason: findings.join('\n'));
  });

  test('third-party actions are pinned to a full commit SHA', () {
    // A tag can be moved to different code; a commit can't. Dependabot
    // keeps the pins (and their # vX.Y.Z comments) up to date.
    final uses = RegExp(r'uses:\s*([\w.-]+/[\w./-]+)@([^\s#]+)');
    final findings = <String>[
      for (final file in workflows)
        for (final match in uses.allMatches(file.readAsStringSync()))
          if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(match.group(2)!))
            '${file.path}: ${match.group(1)}@${match.group(2)}',
    ];
    expect(findings, isEmpty, reason: findings.join('\n'));
  });

  test('the masking script stays silent outside GitHub Actions', () {
    // Elsewhere "::add-mask::<line>" would print the key it should hide.
    final script = File('scripts/mask_secrets.sh').readAsStringSync();
    expect(script, contains(r'[ "${GITHUB_ACTIONS:-}" = true ] || exit 0'));
  });
}
