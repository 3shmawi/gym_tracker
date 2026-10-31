import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/update/update_dialog.dart';
import 'package:gym_tracker/core/update/update_service.dart';

/// Checks for a new version once per launch and shows the update dialog.
class AppUpdateListener extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<AppUpdateListener> createState() => _AppUpdateListenerState();
}

class _AppUpdateListenerState extends State<AppUpdateListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  Future<void> _check() async {
    final info = await UpdateService.check();
    final navigatorContext = rootNavigatorKey.currentContext;
    if (info == null || navigatorContext == null) return;
    if (!navigatorContext.mounted) return;
    await showUpdateDialog(navigatorContext, info);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
