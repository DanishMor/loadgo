// Draws the PLACEHOLDER launcher icon, adaptive foreground and splash logo
// (a white truck on LoadGo blue) with plain Dart, no packages.
//
//   dart run tool/make_placeholder_icon.dart [outDir]      (default: assets/branding)
//
// Then `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`
// copy them into android/ and ios/ (docs/ICON_AND_SPLASH.md). The final artwork
// is to be made by a designer and dropped over these three files.
import 'dart:io';
import 'dart:typed_data';

const int size = 1024;
const int blue = 0xFF1565C0;
const int white = 0xFFFFFFFF;
const int dark = 0xFF0D47A1;

class Canvas {
  Canvas(this.fill) : px = Uint32List(size * size)..fillRange(0, size * size, fill);
  final int fill;
  final Uint32List px; // 0xAARRGGBB

  void rect(int x, int y, int w, int h, int color) {
    for (var j = y; j < y + h; j++) {
      if (j < 0 || j >= size) continue;
      for (var i = x; i < x + w; i++) {
        if (i >= 0 && i < size) px[j * size + i] = color;
      }
    }
  }

  void circle(int cx, int cy, int r, int color) {
    for (var j = cy - r; j <= cy + r; j++) {
      for (var i = cx - r; i <= cx + r; i++) {
        if (i < 0 || j < 0 || i >= size || j >= size) continue;
        final dx = i - cx, dy = j - cy;
        if (dx * dx + dy * dy <= r * r) px[j * size + i] = color;
      }
    }
  }

  /// The truck, inside the middle 66% (the adaptive-icon safe zone).
  void truck(int body, int detail) {
    const x0 = 230, y0 = 350; // top-left of the cargo box
    rect(x0, y0, 360, 250, body); // cargo box
    rect(x0 + 380, y0 + 70, 180, 180, body); // cab
    rect(x0 + 420, y0 + 105, 90, 70, detail); // window
    rect(x0, y0 + 250, 560, 40, body); // chassis
    for (final cx in [x0 + 110, x0 + 450]) {
      circle(cx, y0 + 300, 60, body);
      circle(cx, y0 + 300, 28, detail);
    }
  }
}

Uint8List _png(Uint32List px) {
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < size; x++) {
      final p = px[y * size + x];
      raw.add([(p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF, (p >> 24) & 0xFF]);
    }
  }
  final out = BytesBuilder();
  out.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final t = type.codeUnits;
    out.add(_u32(data.length));
    out.add(t);
    out.add(data);
    out.add(_u32(_crc([...t, ...data])));
  }

  chunk('IHDR', [..._u32(size), ..._u32(size), 8, 6, 0, 0, 0]);
  chunk('IDAT', ZLibEncoder().convert(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

final List<int> _table = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

void main(List<String> args) {
  final dir = Directory(args.isNotEmpty ? args.first : 'assets/branding')..createSync(recursive: true);

  final icon = Canvas(blue)..truck(white, dark);
  File('${dir.path}/icon.png').writeAsBytesSync(_png(icon.px));

  final foreground = Canvas(0x00000000)..truck(white, dark);
  File('${dir.path}/icon_foreground.png').writeAsBytesSync(_png(foreground.px));

  final splash = Canvas(0x00000000)..truck(white, blue);
  File('${dir.path}/splash_logo.png').writeAsBytesSync(_png(splash.px));

  stdout.writeln('Wrote icon.png, icon_foreground.png, splash_logo.png to ${dir.path} (placeholders).');
}
