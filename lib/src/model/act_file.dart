import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:swatchkit/src/model/swatch_options.dart';

/// One 8-bit RGB entry of a color table.
final class ActColor {
  /// Red component in the 0–255 range.
  final int red;

  /// Green component in the 0–255 range.
  final int green;

  /// Blue component in the 0–255 range.
  final int blue;

  /// Creates a color table entry.
  ActColor({
    required this.red,
    required this.green,
    required this.blue,
  }) {
    if ([red, green, blue].any((component) => component < 0 || component > 255)) {
      throw const SwatchWriteException(message: 'ACT components must lie in the 0–255 range');
    }
  }

  /// Approximates [color] in 8-bit sRGB.
  ///
  /// Throws a [SwatchWriteException] for book, unknown, and incomplete colors.
  factory ActColor.fromColor(PsColor color) => switch (color.toRgb()) {
    (:final double red, :final double green, :final double blue) => ActColor(
      red: red.round().clamp(0, 255),
      green: green.round().clamp(0, 255),
      blue: blue.round().clamp(0, 255),
    ),
    null => throw SwatchWriteException(message: 'The ${color.classId} color cannot be approximated in RGB'),
  };

  /// Returns this entry as a Photoshop RGB color.
  PsColor toColor() => PsColor.rgb(red: red.toDouble(), green: green.toDouble(), blue: blue.toDouble());
}

/// Complete decoded contents of one Photoshop `.act` color table.
final class ActFile {
  /// Table entries in source order, at most 256.
  final List<ActColor> colors;

  /// Index of the entry treated as transparent, when the table defines one.
  final int? transparentIndex;

  /// Whether the four-byte count and transparency trailer is written.
  ///
  /// Photoshop writes it whenever the table has fewer than 256 entries or a
  /// transparent entry; the trailer is otherwise optional.
  final bool hasTrailer;

  /// Bytes filling the unused table entries; Photoshop writes `0xFF`.
  ///
  /// Empty means zeros, as for a newly created table.
  final Uint8List unusedEntries;

  /// Recoverable compatibility issues encountered while decoding.
  final List<SwatchWarning> warnings;

  /// Creates an immutable color table.
  ActFile({
    required List<ActColor> colors,
    this.transparentIndex,
    bool? hasTrailer,
    Uint8List? unusedEntries,
    List<SwatchWarning> warnings = const [],
  }) : colors = List<ActColor>.unmodifiable(colors),
       unusedEntries = Uint8List.fromList(unusedEntries ?? const []).asUnmodifiableView(),
       hasTrailer = hasTrailer ?? (colors.length != 256 || transparentIndex != null),
       warnings = List<SwatchWarning>.unmodifiable(warnings);
}
