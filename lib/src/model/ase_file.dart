import 'package:pscore/pscore.dart';
import 'package:swatchkit/src/model/swatch_options.dart';

/// Identifies the color model of one ASE swatch.
enum AseColorModel {
  /// Red, green, and blue in the 0–1 range.
  rgb('RGB ', 3),

  /// Cyan, magenta, yellow, and black ink in the 0–1 range.
  cmyk('CMYK', 4),

  /// CIE L*a*b*: lightness in the 0–1 range, then a and b in the −128–127 range.
  lab('LAB ', 3),

  /// One gray level in the 0–1 range, where 1 is white.
  gray('Gray', 1),

  /// A model code not recognized by this release.
  unknown('', 0);

  /// Four-character code stored in the file.
  final String code;

  /// Number of components of the model.
  final int componentCount;

  /// Creates a model stored as [code] with [componentCount] values.
  const AseColorModel(this.code, this.componentCount);

  /// Returns the model stored as [code].
  static AseColorModel fromCode(String code) => values.firstWhere((model) => model.code == code, orElse: () => unknown);
}

/// Identifies how an application shares one ASE swatch between documents.
enum AseColorType {
  /// A global process color, updated everywhere it is used.
  global,

  /// A spot color printed with its own ink.
  spot,

  /// An ordinary process color.
  normal,
}

/// One item of an Adobe Swatch Exchange library: a swatch or a group.
sealed class AseEntry {
  /// Display name.
  final String name;

  /// Creates an entry named [name].
  const AseEntry({required this.name});
}

/// One named color of an Adobe Swatch Exchange library.
final class AseSwatch extends AseEntry {
  /// Four-character color-model code exactly as stored.
  final String modelCode;

  /// Components in the ranges documented by [model].
  final List<double> values;

  /// Sharing behavior, or `null` when the stored identifier is unknown.
  final AseColorType? type;

  /// Creates a swatch from stored values.
  AseSwatch({
    required super.name,
    required this.modelCode,
    required List<double> values,
    this.type = AseColorType.global,
  }) : values = List<double>.unmodifiable(values);

  /// Converts a process [color] to the matching ASE model.
  ///
  /// HSB colors are stored as RGB, since ASE has no HSB model. Throws a
  /// [SwatchWriteException] for book and unknown colors.
  factory AseSwatch.fromColor(PsColor color, {required String name, AseColorType type = AseColorType.global}) {
    double read(String key) => color.component(key)?.value ?? (throw SwatchWriteException(message: 'The ${color.classId} color has no "$key" component'));
    final (AseColorModel model, List<double> values) = switch (color.colorSpace) {
      PsColorSpace.rgb || PsColorSpace.hsb => switch (color.toRgb()) {
        (:final double red, :final double green, :final double blue) => (AseColorModel.rgb, [red / 255, green / 255, blue / 255]),
        null => throw SwatchWriteException(message: 'The ${color.classId} color is incomplete'),
      },
      PsColorSpace.cmyk => (
        AseColorModel.cmyk,
        [
          for (final String key in const ['Cyn ', 'Mgnt', 'Ylw ', 'Blck']) read(key) / 100,
        ],
      ),
      PsColorSpace.lab => (AseColorModel.lab, [read('Lmnc') / 100, read('A   '), read('B   ')]),
      PsColorSpace.grayscale => (AseColorModel.gray, [1 - read('Gry ') / 100]),
      PsColorSpace.book || PsColorSpace.unknown => throw SwatchWriteException(message: 'The ${color.classId} color cannot be stored in an ASE library'),
    };
    return AseSwatch(name: name, modelCode: model.code, values: values, type: type);
  }

  /// Known interpretation of [modelCode].
  AseColorModel get model => AseColorModel.fromCode(modelCode);

  /// Returns this swatch as a Photoshop color, or `null` for an unknown model.
  PsColor? toColor() {
    if (model == AseColorModel.unknown || values.length != model.componentCount) {
      return null;
    }
    return switch (model) {
      AseColorModel.rgb => PsColor.rgb(red: values[0] * 255, green: values[1] * 255, blue: values[2] * 255),
      AseColorModel.cmyk => PsColor.cmyk(cyan: values[0] * 100, magenta: values[1] * 100, yellow: values[2] * 100, black: values[3] * 100),
      AseColorModel.lab => PsColor.lab(lightness: values[0] * 100, a: values[1], b: values[2]),
      AseColorModel.gray => PsColor.grayscale(gray: 100 - values[0] * 100),
      AseColorModel.unknown => null,
    };
  }
}

/// A named group of swatches in an Adobe Swatch Exchange library.
final class AseGroup extends AseEntry {
  /// Swatches in source order.
  final List<AseSwatch> swatches;

  /// Creates a group named [name].
  AseGroup({
    required super.name,
    required List<AseSwatch> swatches,
  }) : swatches = List<AseSwatch>.unmodifiable(swatches);
}

/// Complete decoded contents of one Adobe Swatch Exchange `.ase` library.
final class AseFile {
  /// Major format version, normally 1.
  final int majorVersion;

  /// Minor format version, normally 0.
  final int minorVersion;

  /// Top-level swatches and groups in source order.
  final List<AseEntry> entries;

  /// Recoverable compatibility issues encountered while decoding.
  final List<SwatchWarning> warnings;

  /// Creates an immutable swatch-exchange library.
  AseFile({
    this.majorVersion = 1,
    this.minorVersion = 0,
    required List<AseEntry> entries,
    List<SwatchWarning> warnings = const [],
  }) : entries = List<AseEntry>.unmodifiable(entries),
       warnings = List<SwatchWarning>.unmodifiable(warnings);

  /// Every swatch with the name of its enclosing group, or `null` at the top level.
  Iterable<({AseSwatch swatch, String? group})> get swatches sync* {
    for (final AseEntry entry in entries) {
      switch (entry) {
        case final AseSwatch swatch:
          yield (swatch: swatch, group: null);
        case final AseGroup group:
          for (final AseSwatch swatch in group.swatches) {
            yield (swatch: swatch, group: group.name);
          }
      }
    }
  }
}
