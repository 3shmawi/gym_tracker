import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Why the camera cannot be used.
enum CameraProblem {
  /// The member said no (or it is blocked by the system).
  denied,

  /// None on this phone, or it failed to start.
  unavailable,
}

/// Builds the live camera. A provider so tests put a plain box in its place:
/// widget tests have no camera.
typedef ScannerCameraBuilder = Widget Function(
  BuildContext context, {
  required ValueChanged<String?> onScanned,
  required ValueChanged<CameraProblem> onProblem,
});

/// Replaces the live camera in integration tests, which run on a simulator
/// with no camera. Null in the app.
@visibleForTesting
ScannerCameraBuilder? scannerCameraOverride;

final scannerCameraBuilderProvider = Provider<ScannerCameraBuilder>(
  (ref) => scannerCameraOverride ?? _liveCamera,
);

/// QR codes only, one result per code, back camera. The picture is never
/// returned to Dart (`returnImage` stays off): it cannot be stored or sent.
Widget _liveCamera(
  BuildContext context, {
  required ValueChanged<String?> onScanned,
  required ValueChanged<CameraProblem> onProblem,
}) => _LiveCamera(onScanned: onScanned, onProblem: onProblem);

class _LiveCamera extends StatefulWidget {
  const new({required this.onScanned, required this.onProblem});

  final ValueChanged<String?> onScanned;
  final ValueChanged<CameraProblem> onProblem;

  @override
  State<_LiveCamera> createState() => _LiveCameraState();
}

class _LiveCameraState extends State<_LiveCamera> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (raw != null) widget.onScanned(raw);
      },
      errorBuilder: (context, error) {
        final problem =
            error.errorCode == MobileScannerErrorCode.permissionDenied
            ? CameraProblem.denied
            : CameraProblem.unavailable;
        // After this frame: the page rebuilds into the refusal screen.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onProblem(problem),
        );
        return const SizedBox.shrink();
      },
    );
  }
}
