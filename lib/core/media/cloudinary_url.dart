/// The sizes the app asks Cloudinary for. Fixed words only: nothing a user,
/// a captain or the server sends ever becomes part of a transformation.
enum PictureSize {
  /// A list row's 52-point tile at up to 3×.
  thumb(160),

  /// The exercise screen's 210-point picture at up to 3×.
  large(640);

  new(this.width);

  final int width;
}

/// Builds a delivery URL of the exercise picture library on Cloudinary
/// (docs/features/gym_exercise_images.md → "Picture URLs").
///
/// `https://res.cloudinary.com/<cloud>/image/upload/c_limit,w_<n>,f_webp,q_auto/<public id>.png`
///
/// - Only a public id of the library (`exercises/<a-z0-9->`) is accepted, and
///   only a cloud name of `[a-z0-9_-]`: anything else (a URL, `../`, upper
///   case, look-alike letters, percent-encoding, spaces) returns null, and
///   the caller shows the bundled picture.
/// - `c_limit` never enlarges; `f_webp` is fixed rather than `f_auto`, which
///   picks the format from the request's `Accept` header and could answer
///   AVIF, which Flutter can't decode; `q_auto` lets Cloudinary pick the
///   quality.
abstract final class CloudinaryUrl {
  static const host = 'res.cloudinary.com';

  static final _cloudName = RegExp(r'^[a-z0-9][a-z0-9_-]{0,62}$');
  static final _publicId = RegExp(r'^exercises/[a-z0-9][a-z0-9-]{0,79}$');

  static bool isCloudName(String value) => _cloudName.hasMatch(value);

  static bool isPublicId(String value) => _publicId.hasMatch(value);

  /// The URL, or null when [cloudName] or [publicId] is not acceptable.
  static Uri? picture({
    required String cloudName,
    required String publicId,
    required PictureSize size,
  }) {
    if (!isCloudName(cloudName) || !isPublicId(publicId)) return null;
    final name = publicId.substring('exercises/'.length);
    return Uri(
      scheme: 'https',
      host: host,
      pathSegments: [
        cloudName,
        'image',
        'upload',
        'c_limit,w_${size.width},f_webp,q_auto',
        'exercises',
        '$name.png',
      ],
    );
  }
}
