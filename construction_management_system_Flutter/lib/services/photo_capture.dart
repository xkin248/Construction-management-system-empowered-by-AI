import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// A captured photo ready to be posted as base64 to the backend.
class CapturedPhoto {
  /// Base64 payload without the `data:` prefix.
  final String base64;

  /// MIME type, e.g. `image/jpeg`.
  final String mimeType;

  const CapturedPhoto({required this.base64, required this.mimeType});

  int get byteLength => (base64.length * 3) ~/ 4;

  Map<String, dynamic> toJson({
    String base64Key = 'photo_base64',
    String mimeKey = 'photo_mime_type',
  }) =>
      {base64Key: base64, mimeKey: mimeType};
}

/// Thrown when the camera cannot be used or the user cancels.
class PhotoCaptureException implements Exception {
  final String message;
  final bool cancelled;
  PhotoCaptureException(this.message, {this.cancelled = false});
  @override
  String toString() => message;
}

/// Thin wrapper around `image_picker` used by attendance check-in and task
/// completion. Only the OS camera is offered — never the gallery — because the
/// photo is proof that the worker is physically on site. The image is downscaled
/// before encoding so a 4G upload stays well under the server's 6 MB cap.
class PhotoCapture {
  PhotoCapture._();

  /// Longest edge in pixels after downscaling.
  static const int maxEdge = 1024;

  /// JPEG quality after downscaling (0-100).
  static const int quality = 70;

  /// Server-side hard limit (see app/attendance_photo.py).
  static const int maxBytes = 6 * 1024 * 1024;

  static final ImagePicker _picker = ImagePicker();

  /// Opens the camera and returns the encoded photo.
  ///
  /// Throws [PhotoCaptureException] with `cancelled = true` when the user backs
  /// out, and with a readable message when the camera is unavailable, so callers
  /// can show a localised hint instead of a raw platform error.
  static Future<CapturedPhoto> takeSelfie() =>
      _take(preferFrontCamera: true);

  /// Opens the camera for task-completion evidence (rear camera by default).
  static Future<CapturedPhoto> takeEvidencePhoto() =>
      _take(preferFrontCamera: false);

  static Future<CapturedPhoto> _take({required bool preferFrontCamera}) async {
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice:
            preferFrontCamera ? CameraDevice.front : CameraDevice.rear,
        maxWidth: maxEdge.toDouble(),
        maxHeight: maxEdge.toDouble(),
        imageQuality: quality,
        requestFullMetadata: false,
      );
    } catch (e) {
      throw PhotoCaptureException(
        kIsWeb
            ? 'Camera is not available in this browser. Open BuildSmart on a phone to take the photo.'
            : 'Camera could not be opened: $e',
      );
    }
    if (file == null) {
      throw PhotoCaptureException('Photo was cancelled', cancelled: true);
    }

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      throw PhotoCaptureException('Could not read the captured photo: $e');
    }
    if (bytes.isEmpty) {
      throw PhotoCaptureException('The captured photo is empty, please retake');
    }
    if (bytes.length > maxBytes) {
      throw PhotoCaptureException(
          'The photo is too large (${(bytes.length / 1048576).toStringAsFixed(1)} MB). Please retake.');
    }

    return CapturedPhoto(
      base64: base64Encode(bytes),
      mimeType: _mimeOf(file),
    );
  }

  static String _mimeOf(XFile file) {
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic')) return 'image/heic';
    // image_picker re-encodes to JPEG when imageQuality / maxWidth is set.
    return 'image/jpeg';
  }
}
