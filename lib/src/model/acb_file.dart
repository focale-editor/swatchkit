import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:swatchkit/src/model/swatch_options.dart';

/// Color model shared by every color of a book.
enum AcbColorModel {
  /// 8-bit RGB components.
  rgb(0, 3),

  /// CMYK ink coverages, stored inverted: 0 is full ink, 255 none.
  cmyk(2, 4),

  /// L*a*b* components: lightness scaled to 0–255, a and b offset by 128.
  lab(7, 3);

  /// Identifier stored in the file.
  final int id;

  /// Number of one-byte components each color holds.
  final int componentCount;

  /// Creates a color model stored as [id].
  const AcbColorModel(this.id, this.componentCount);

  /// Returns the model stored as [id], or `null` for an unknown one.
  static AcbColorModel? fromId(int id) => values.where((model) => model.id == id).firstOrNull;
}

/// One named color of a color book.
final class AcbColor {
  /// Display name, without the book's prefix and postfix.
  ///
  /// Empty for the placeholders some books use to fill a page.
  final String name;

  /// Six-character catalog code, padded with spaces.
  final String code;

  /// Raw one-byte components in the book's [AcbColorModel].
  final List<int> components;

  /// Creates a color, checking the code length and component range.
  AcbColor({required this.name, required this.code, required List<int> components}) : components = List<int>.unmodifiable(components) {
    if (code.length != 6 || code.codeUnits.any((unit) => unit > 0x7f)) {
      throw SwatchWriteException(message: 'An ACB catalog code holds six ASCII characters, not "$code"');
    }
    if (components.any((component) => component < 0 || component > 255)) {
      throw const SwatchWriteException(message: 'ACB components must lie in the 0–255 range');
    }
  }

  /// Returns this color in Photoshop's color model for [model].
  PsColor toColor(AcbColorModel model) => switch (model) {
    AcbColorModel.rgb => PsColor.rgb(red: components[0].toDouble(), green: components[1].toDouble(), blue: components[2].toDouble()),
    AcbColorModel.cmyk => PsColor.cmyk(
      cyan: (255 - components[0]) / 2.55,
      magenta: (255 - components[1]) / 2.55,
      yellow: (255 - components[2]) / 2.55,
      black: (255 - components[3]) / 2.55,
    ),
    AcbColorModel.lab => PsColor.lab(lightness: components[0] / 2.55, a: components[1] - 128.0, b: components[2] - 128.0),
  };
}

/// Complete decoded contents of one Photoshop `.acb` color book.
///
/// Titles and other texts may be Adobe localization keys such as
/// `$$$/colorbook/ANPA/title=ANPA Color`; [displayText] extracts the text.
final class AcbFile {
  /// Format version, 1 in every known book.
  final int version;

  /// Book identifier, unique among Adobe's books.
  final int identifier;

  /// Book title.
  final String title;

  /// Text shown before each color name.
  final String prefix;

  /// Text shown after each color name.
  final String postfix;

  /// Description, often a copyright notice.
  final String description;

  /// Colors shown on one page of Photoshop's picker.
  final int pageSize;

  /// Index on each page of the color that represents it in the page slider.
  final int pageSelectorOffset;

  /// Color model of every color.
  final AcbColorModel colorModel;

  /// Colors in source order, placeholders included.
  final List<AcbColor> colors;

  /// Bytes after the colors; newer books mark spot or process inks there with
  /// `spflspot` or `spflproc`.
  final Uint8List trailingData;

  /// Recoverable compatibility issues encountered while decoding.
  final List<SwatchWarning> warnings;

  /// Creates an immutable color book.
  AcbFile({
    this.version = 1,
    required this.identifier,
    required this.title,
    this.prefix = '',
    this.postfix = '',
    this.description = '',
    required this.pageSize,
    this.pageSelectorOffset = 0,
    required this.colorModel,
    required List<AcbColor> colors,
    Uint8List? trailingData,
    List<SwatchWarning> warnings = const [],
  }) : colors = List<AcbColor>.unmodifiable(colors),
       trailingData = Uint8List.fromList(trailingData ?? const []).asUnmodifiableView(),
       warnings = List<SwatchWarning>.unmodifiable(warnings);

  /// Whether the book describes spot inks, when it says so.
  bool? get spot => switch (String.fromCharCodes(trailingData.take(8))) {
    'spflspot' => true,
    'spflproc' => false,
    _ => null,
  };

  /// The text of [value], without an Adobe `$$$/…=` localization key.
  static String displayText(String value) => value.startsWith(r'$$$/') && value.contains('=') ? value.substring(value.indexOf('=') + 1) : value;

  /// The name Photoshop shows for [color]: prefix, name and postfix.
  String displayName(AcbColor color) => '${displayText(prefix)}${displayText(color.name)}${displayText(postfix)}';
}
