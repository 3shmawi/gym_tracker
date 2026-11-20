import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Flutter Driver extension lets anything that reaches the VM service
/// tap and read the app. It is only for agents testing on a simulator
/// (test_driver/agent_app.dart, debug runs): nothing the stores get may
/// import it.
void main() {
  test('nothing under lib/ imports flutter_driver', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('package:flutter_driver/'))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('the agent entrypoint lives outside lib/', () {
    expect(File('test_driver/agent_app.dart').existsSync(), isTrue);
  });
}
