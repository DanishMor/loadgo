import 'dart:typed_data';
import 'dart:ui' as ui;

/// E18: on-device checks before a vehicle photo is sent, and privacy clean-up of the file. Nothing here talks to a
/// server; the thresholds are a first guess (UNVERIFIED) to be tuned with real phone photos.
enum PhotoIssue { tooDark, tooBright, blurry }

class PhotoQuality {
  /// Mean brightness 0..255 of the thumbnail.
  final double brightness;

  /// Variance of the Laplacian of the thumbnail: low means few sharp edges (a shaken or out-of-focus photo).
  final double sharpness;
  const PhotoQuality(this.brightness, this.sharpness);

  static const double minBrightness = 45, maxBrightness = 225, minSharpness = 60;

  List<PhotoIssue> get issues => [
        if (brightness < minBrightness) PhotoIssue.tooDark,
        if (brightness > maxBrightness) PhotoIssue.tooBright,
        if (sharpness < minSharpness) PhotoIssue.blurry,
      ];

  bool get ok => issues.isEmpty;

  /// From grey levels (0..255) of a [width] x [height] image, row by row.
  static PhotoQuality fromGrey(Uint8List grey, int width, int height) {
    if (width < 3 || height < 3 || grey.length < width * height) return const PhotoQuality(0, 0);
    var sum = 0.0;
    for (var i = 0; i < width * height; i++) {
      sum += grey[i];
    }
    // 4-neighbour Laplacian over the inner pixels.
    var n = 0, mean = 0.0, m2 = 0.0;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final i = y * width + x;
        final lap = 4.0 * grey[i] - grey[i - 1] - grey[i + 1] - grey[i - width] - grey[i + width];
        n++;
        final d = lap - mean;
        mean += d / n;
        m2 += d * (lap - mean);
      }
    }
    return PhotoQuality(sum / (width * height), n > 1 ? m2 / (n - 1) : 0);
  }

  /// RGBA bytes to grey levels (Rec. 601 weights).
  static Uint8List grey(Uint8List rgba) {
    final out = Uint8List(rgba.length ~/ 4);
    for (var i = 0, j = 0; j < out.length; i += 4, j++) {
      out[j] = (0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2]).round().clamp(0, 255);
    }
    return out;
  }

  /// Decodes [bytes] small (128 px wide) and measures it. A file that cannot be decoded counts as dark and blurry.
  static Future<PhotoQuality> measure(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 128);
      final img = (await codec.getNextFrame()).image;
      final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final q = fromGrey(grey(rgba), img.width, img.height);
      img.dispose();
      return q;
    } catch (_) {
      return const PhotoQuality(0, 0);
    }
  }
}

/// Removes every metadata segment from a JPEG (EXIF with the GPS place and the phone model, XMP, comments), keeping
/// the picture itself. Other formats are returned as they are (PNG and WebP from the picker carry no GPS).
/// Pure Dart: no package is added for this (rule 7).
Uint8List stripJpegMetadata(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return bytes;
  final out = BytesBuilder(copy: false)..add([0xFF, 0xD8]);
  var i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] != 0xFF) return bytes; // not a marker where one should be: leave the file alone
    final marker = bytes[i + 1];
    if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01 || marker == 0xFF) {
      i += marker == 0xFF ? 1 : 2;
      continue;
    }
    if (marker == 0xDA) {
      // Start of scan: the compressed picture runs to the end of the file.
      out.add(bytes.sublist(i));
      return out.takeBytes();
    }
    final len = (bytes[i + 2] << 8) | bytes[i + 3];
    if (len < 2 || i + 2 + len > bytes.length) return bytes;
    // APP1..APP15 (EXIF, XMP, ...) and COM go; APP0 (JFIF) and the picture's own tables stay.
    final drop = (marker >= 0xE1 && marker <= 0xEF) || marker == 0xFE;
    if (!drop) out.add(bytes.sublist(i, i + 2 + len));
    i += 2 + len;
  }
  return bytes;
}
