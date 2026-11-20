// The app with the Flutter Driver extension, for an AI agent to drive on a
// simulator or emulator (scripts/agent_run.sh → the Dart MCP server's
// `flutter_driver_command`). Debug runs only: release builds use
// lib/main.dart, which never imports flutter_driver
// (test/security/agent_driver_test.dart).
import 'package:flutter_driver/driver_extension.dart';
import 'package:gym_tracker/main.dart' as app;

Future<void> main() async {
  enableFlutterDriverExtension();
  await app.main();
}
