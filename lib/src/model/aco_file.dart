import 'package:pscore/pscore.dart';
import 'package:swatchkit/src/model/swatch_options.dart';

/// Identifies the color space of one ACO swatch.
enum AcoColorSpace {
  /// Red, green, and blue in the 0–65535 range.
  rgb(0),

  /// Hue, saturation, and brightness in the 0–65535 range.
  hsb(1),

  /// Cyan, magenta, yellow, and black, where 0 is full ink.
  cmyk(2),

  /// A Pantone matching-system reference.
  pantone(3),

  /// A Focoltone color reference.
  focoltone(4),

  /// A Trumatch color reference.
  trumatch(5),

  /// A Toyo 88 colorfinder reference.
  toyo(6),

  /// CIE L*a*b*: lightness in hundredths, then signed a and b in hundredths.
  lab(7),

  /// Grayscale in the 0–10000 range, where 10000 is white.
  grayscale(8),

  /// Cyan, magenta, yellow, and black in the 0–10000 range, where 10000 is full ink.
  wideCmyk(9),

  /// An HKS color reference.
  hks(10),

  /// A color-space identifier not recognized by this release.
  unknown(-1);

  /// Identifier stored in the file.
  final int id;

  /// Creates a color space stored as [id].
  const AcoColorSpace(this.id);

  /// Returns the color space stored as [id].
  static AcoColorSpace fromId(int id) => values.firstWhere((space) => space.id == id, orElse: () => unknown);
}

/// One color of a Photoshop swatch library, with its exact stored components.
final class AcoSwatch {
  /// Color-space identifier exactly as stored.
  final int colorSpaceId;

  /// Four unsigned 16-bit components, interpreted according to [colorSpace].
  final List<int> components;

  /// Swatch name, when the library has a version 2 section.
  final String? name;

  /// Creates a swatch from raw stored values.
  AcoSwatch({
    required this.colorSpaceId,
    required List<int> components,
    this.name,
  }) : components = List<int>.unmodifiable(components) {
    if (components.length != 4 || components.any((component) => component < 0 || component > 0xffff)) {
      throw const SwatchWriteException(message: 'An ACO swatch needs four unsigned 16-bit components');
    }
  }

  /// Converts a process [color] to the matching ACO color space.
  ///
  /// Throws a [SwatchWriteException] for book and unknown colors, and for
  /// colors missing a component.
  factory AcoSwatch.fromColor(PsColor color, {String? name}) {
    double read(String key) => color.component(key)?.value ?? (throw SwatchWriteException(message: 'The ${color.classId} color has no "$key" component'));
    int scale(double value, double factor) => (value * factor).round().clamp(0, 0xffff);
    final (AcoColorSpace space, List<int> components) = switch (color.colorSpace) {
      PsColorSpace.rgb => (AcoColorSpace.rgb, [scale(color.red ?? read('Rd  '), 257), scale(color.green ?? read('Grn '), 257), scale(color.blue ?? read('Bl  '), 257), 0]),
      PsColorSpace.hsb => (AcoColorSpace.hsb, [scale(read('H   ') % 360, 65535 / 360), scale(read('Strt'), 655.35), scale(read('Brgh'), 655.35), 0]),
      PsColorSpace.cmyk => (
        AcoColorSpace.cmyk,
        [
          for (final String key in const ['Cyn ', 'Mgnt', 'Ylw ', 'Blck']) scale(100 - read(key), 655.35),
        ],
      ),
      PsColorSpace.lab => (
        AcoColorSpace.lab,
        [scale(read('Lmnc'), 100), (read('A   ') * 100).round().clamp(-12800, 12700).toUnsigned(16), (read('B   ') * 100).round().clamp(-12800, 12700).toUnsigned(16), 0],
      ),
      PsColorSpace.grayscale => (AcoColorSpace.grayscale, [scale(100 - read('Gry '), 100).clamp(0, 10000), 0, 0, 0]),
      PsColorSpace.book || PsColorSpace.unknown => throw SwatchWriteException(message: 'The ${color.classId} color cannot be stored in an ACO library'),
    };
    return AcoSwatch(colorSpaceId: space.id, components: components, name: name);
  }

  /// Known interpretation of [colorSpaceId].
  AcoColorSpace get colorSpace => AcoColorSpace.fromId(colorSpaceId);

  /// Returns this swatch as a Photoshop color, or `null` for matching-system references.
  PsColor? toColor() => switch (colorSpace) {
    AcoColorSpace.rgb => PsColor.rgb(red: components[0] / 257, green: components[1] / 257, blue: components[2] / 257),
    AcoColorSpace.hsb => PsColor.hsb(hue: components[0] / 65535 * 360, saturation: components[1] / 655.35, brightness: components[2] / 655.35),
    AcoColorSpace.cmyk => PsColor.cmyk(
      cyan: 100 - components[0] / 655.35,
      magenta: 100 - components[1] / 655.35,
      yellow: 100 - components[2] / 655.35,
      black: 100 - components[3] / 655.35,
    ),
    AcoColorSpace.wideCmyk => PsColor.cmyk(cyan: components[0] / 100, magenta: components[1] / 100, yellow: components[2] / 100, black: components[3] / 100),
    AcoColorSpace.lab => PsColor.lab(lightness: components[0] / 100, a: components[1].toSigned(16) / 100, b: components[2].toSigned(16) / 100),
    AcoColorSpace.grayscale => PsColor.grayscale(gray: 100 - components[0] / 100),
    AcoColorSpace.pantone || AcoColorSpace.focoltone || AcoColorSpace.trumatch || AcoColorSpace.toyo || AcoColorSpace.hks || AcoColorSpace.unknown => null,
  };
}

/// Complete decoded contents of one Photoshop `.aco` swatch library.
final class AcoFile {
  /// Swatches in source order, taken from the version 2 section when present.
  final List<AcoSwatch> swatches;

  /// Highest section version read: 2 when names were available, otherwise 1.
  final int version;

  /// Recoverable compatibility issues encountered while decoding.
  final List<SwatchWarning> warnings;

  /// Creates an immutable swatch library.
  AcoFile({
    required List<AcoSwatch> swatches,
    this.version = 2,
    List<SwatchWarning> warnings = const [],
  }) : swatches = List<AcoSwatch>.unmodifiable(swatches),
       warnings = List<SwatchWarning>.unmodifiable(warnings);
}
