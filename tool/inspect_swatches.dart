import 'dart:io';
import 'dart:typed_data';

import 'package:swatchkit/swatchkit.dart';

/// Prints the swatches of ACO, ASE, and ACT files and checks that each re-encodes identically.
Future<void> main(List<String> arguments) async {
  for (final String path in arguments) {
    final Uint8List bytes = await File(path).readAsBytes();
    final String extension = path.split('.').last.toLowerCase();
    final (List<String> lines, Uint8List encoded, List<SwatchWarning> warnings) = switch (extension) {
      'aco' => _aco(AcoDecoder.decode(bytes)),
      'ase' => _ase(AseDecoder.decode(bytes)),
      'act' => _act(ActDecoder.decode(bytes)),
      _ => throw ArgumentError.value(path, 'path', 'Unsupported extension'),
    };
    final bool identical = encoded.length == bytes.length && Iterable<int>.generate(bytes.length).every((index) => bytes[index] == encoded[index]);
    stdout.writeln('$path: ${lines.length} swatches, ${warnings.length} warnings, identical: $identical');
    lines.take(8).forEach((line) => stdout.writeln('  $line'));
    warnings.forEach(stdout.writeln);
  }
}

/// Describes one approximate sRGB color.
String _rgb(PsColor? color) => switch (color?.toRgb()) {
  (:final double red, :final double green, :final double blue) => 'rgb(${red.round()}, ${green.round()}, ${blue.round()})',
  null => 'no RGB',
};

/// Summarizes an ACO library.
(List<String>, Uint8List, List<SwatchWarning>) _aco(AcoFile file) => (
  [for (final AcoSwatch swatch in file.swatches) '${swatch.name} [${swatch.colorSpace.name}] ${_rgb(swatch.toColor())}'],
  AcoEncoder.encode(file),
  file.warnings,
);

/// Summarizes an ASE library.
(List<String>, Uint8List, List<SwatchWarning>) _ase(AseFile file) => (
  [for (final (:AseSwatch swatch, :String? group) in file.swatches) '${group ?? '-'} / ${swatch.name} [${swatch.modelCode} ${swatch.type?.name}] ${_rgb(swatch.toColor())}'],
  AseEncoder.encode(file),
  file.warnings,
);

/// Summarizes an ACT table.
(List<String>, Uint8List, List<SwatchWarning>) _act(ActFile file) => (
  [for (final ActColor color in file.colors) _rgb(color.toColor())],
  ActEncoder.encode(file),
  file.warnings,
);
