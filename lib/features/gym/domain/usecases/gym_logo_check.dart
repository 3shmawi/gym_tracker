import 'dart:typed_data';

/// Why downloaded logo bytes were refused.
enum GymLogoProblem {
  empty,
  tooBig,
  notPngOrJpeg,

  /// The header could not be read to the end (cut off, or not what the
  /// signature promised).
  broken,

  /// Smaller than [GymLogoCheck.minSide] or larger than
  /// [GymLogoCheck.maxSide] on a side.
  badSize,

  /// An animated PNG (a logo is one picture).
  animated,
}

/// The checks downloaded logo bytes pass before the phone keeps them
/// (docs/designs/gym_logo.md §4). The bucket already allows only PNG and
/// JPEG up to 512 KB; this is the second line of defence, and it reads the
/// picture's size from the header **without decoding it**, so a small file
/// that claims a huge picture is refused before it can use the memory.
///
/// Pure Dart: the signature rules are the dashboard's (`checkLogoFile` in
/// `dashboard/src/gyms/settings.ts`).
abstract final class GymLogoCheck {
  /// The bucket's own limit (migration 0008).
  static const int maxBytes = 512 * 1024;

  /// The dashboard writes at most 512 px a side; a little room for logos
  /// uploaded another way, never a picture big enough to hurt.
  static const maxSide = 2048;
  static const minSide = 16;

  static const _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  /// Null when [bytes] are a logo the app shows, else why not.
  static GymLogoProblem? inspect(Uint8List bytes) {
    if (bytes.isEmpty) return GymLogoProblem.empty;
    if (bytes.length > maxBytes) return GymLogoProblem.tooBig;
    final size = _startsWith(bytes, _png)
        ? _pngSize(bytes)
        : _startsWith(bytes, const [0xFF, 0xD8, 0xFF])
        ? _jpegSize(bytes)
        : null;
    if (size == null) return GymLogoProblem.notPngOrJpeg;
    return switch (size) {
      _Broken() => GymLogoProblem.broken,
      _Animated() => GymLogoProblem.animated,
      _Size(:final width, :final height) =>
        width < minSide ||
                height < minSide ||
                width > maxSide ||
                height > maxSide
            ? GymLogoProblem.badSize
            : null,
    };
  }

  static bool _startsWith(Uint8List bytes, List<int> head) {
    if (bytes.length < head.length) return false;
    for (var i = 0; i < head.length; i++) {
      if (bytes[i] != head[i]) return false;
    }
    return true;
  }

  static int _u32(Uint8List b, int at) =>
      (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static int _u16(Uint8List b, int at) => (b[at] << 8) | b[at + 1];

  /// IHDR first (its size), then the chunks up to the first IDAT: an `acTL`
  /// there makes it an animated PNG.
  static _Header _pngSize(Uint8List b) {
    // Signature (8) + length (4) + "IHDR" (4) + width (4) + height (4).
    if (b.length < 33) return const _Broken();
    if (_u32(b, 8) != 13 || String.fromCharCodes(b, 12, 16) != 'IHDR') {
      return const _Broken();
    }
    final width = _u32(b, 16);
    final height = _u32(b, 20);
    var at = 8;
    while (at + 8 <= b.length) {
      final length = _u32(b, at);
      final type = String.fromCharCodes(b, at + 4, at + 8);
      if (type == 'acTL') return const _Animated();
      if (type == 'IDAT') return _Size(width, height);
      // Length + type + data + CRC; a length past the end is a broken file.
      final next = at + 12 + length;
      if (length < 0 || next > b.length) return const _Broken();
      at = next;
    }
    return const _Broken();
  }

  /// The markers up to the first start-of-frame (its size). A scan before
  /// any frame, or a marker past the end, is a broken file.
  static _Header _jpegSize(Uint8List b) {
    var at = 2;
    while (at + 4 <= b.length) {
      if (b[at] != 0xFF) return const _Broken();
      final marker = b[at + 1];
      if (marker == 0xFF) {
        at++; // Fill byte.
        continue;
      }
      // Markers without a length.
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        at += 2;
        continue;
      }
      if (marker == 0xDA || marker == 0xD9) return const _Broken();
      final length = _u16(b, at + 2);
      if (length < 2 || at + 2 + length > b.length) return const _Broken();
      final isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) {
        if (length < 7) return const _Broken();
        return _Size(_u16(b, at + 7), _u16(b, at + 5));
      }
      at += 2 + length;
    }
    return const _Broken();
  }
}

sealed class _Header {
  const new();
}

class _Size extends _Header {
  const new(this.width, this.height);
  final int width;
  final int height;
}

class _Broken extends _Header {
  const new();
}

class _Animated extends _Header {
  const new();
}
