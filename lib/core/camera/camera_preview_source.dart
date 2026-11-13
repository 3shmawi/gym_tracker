import 'package:flutter/widgets.dart';

/// A source that can show its live camera picture (Move games' placement
/// guide). Screens draw it only on the phone; it is never captured.
abstract interface class CameraPreviewSource {
  /// The live picture, or null when the camera is not running.
  Widget? buildPreview();
}
