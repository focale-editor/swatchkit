import 'dart:io';
import 'dart:typed_data';

import 'package:swatchkit/swatchkit.dart';

/// Prints the colors of one ACO, ASE, or ACT library.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/main.dart <library.aco|ase|act>');
    exitCode = 64;
    return;
  }
  final String path = arguments.single;
  final Uint8List bytes = await File(path).readAsBytes();
  final List<(String, PsColor?)> colors = switch (path.split('.').last.toLowerCase()) {
    'aco' => [for (final AcoSwatch swatch in AcoDecoder.decode(bytes).swatches) (swatch.name ?? '', swatch.toColor())],
    'ase' => [for (final (:AseSwatch swatch, :String? group) in AseDecoder.decode(bytes).swatches) ('${group ?? '-'} / ${swatch.name}', swatch.toColor())],
    'act' => [for (final ActColor color in ActDecoder.decode(bytes).colors) ('', color.toColor())],
    _ => throw ArgumentError.value(path, 'path', 'Unsupported extension'),
  };
  for (final (String name, PsColor? color) in colors) {
    stdout.writeln('$name: ${color?.toRgb() ?? 'no process color'}');
  }
}
