<p align="center">
  <img src="screenshots/overview.png" alt="SwatchKit package illustration" width="180">
</p>

# SwatchKit

SwatchKit is a pure Dart codec for Adobe color swatch libraries: Photoshop swatches (`.aco`), Adobe Swatch Exchange (`.ase`), and Photoshop color tables (`.act`). It keeps the exact stored components, converts them to and from [`pscore`](https://pub.dev/packages/pscore) colors, and has no Flutter or native-code dependency.

## Supported data

- **ACO**: version 1 and named version 2 sections; RGB, HSB, CMYK, Lab, grayscale, and wide CMYK colors; Pantone, Focoltone, Trumatch, Toyo, and HKS references kept as raw components.
- **ASE**: version 1.0 libraries with groups, RGB, CMYK, Lab, and gray colors, and global, spot, or normal color types.
- **ACT**: 256-entry RGB tables, with the optional color count and transparent index.
- Configurable limits for file size, entry counts, and name lengths, with strict or tolerant handling of recoverable defects.

The models expose the stored color components separately from their `PsColor` conversion. Matching-system references remain accessible even when no process-color conversion is available.

## Reading a file

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:swatchkit/swatchkit.dart';

final Uint8List bytes = await File('swatches.aco').readAsBytes();
final AcoFile swatches = AcoDecoder.decode(bytes);

for (final AcoSwatch swatch in swatches.swatches) {
  print('${swatch.name}: ${swatch.toColor()?.toRgb()}');
}
```

Use the decoder matching the file format. ASE iteration includes the name of each swatch's group:

```dart
final AseFile exchange = AseDecoder.decode(await File('palette.ase').readAsBytes());

for (final (:AseSwatch swatch, :String? group) in exchange.swatches) {
  print('${group ?? '-'} / ${swatch.name}: ${swatch.model.name}');
}
```

For ACT files, `ActFile.colors` exposes the active RGB entries and `transparentIndex` identifies the optional transparent entry. See [docs/SWATCHES.md](docs/SWATCHES.md) for each format's storage conventions.

## Writing and editing

```dart
final AcoFile created = AcoFile(
  swatches: [
    AcoSwatch.fromColor(
      PsColor.cmyk(cyan: 100, magenta: 0, yellow: 0, black: 0),
      name: 'Process Cyan',
    ),
  ],
);

final Uint8List output = AcoEncoder.encode(created);
await File('cyan.aco').writeAsBytes(output, flush: true);
```

`AcoEncoder` writes a version 1 section followed by a named version 2 section by default. Set `AcoFile.version` to `1` for an unnamed library. `AseEncoder` writes the swatches and groups in `AseFile.entries`; `ActEncoder` writes a 256-slot table, padding unused entries with black.

The models are immutable. Build a new file from the desired swatches or groups when editing a palette.

## Reusable `dart:convert` API

`AcoCodec`, `AseCodec`, and `ActCodec` implement `Codec<FileModel, List<int>>` for their respective file models and share the same decoding options:

```dart
const AcoCodec codec = AcoCodec(
  decodeOptions: SwatchDecodeOptions(mode: SwatchDecodeMode.strict),
);

final AcoFile swatches = codec.decode(bytes);
final Uint8List encoded = codec.encode(swatches);
```

The `List<int>` binary type allows composition with standard codecs such as `base64`; direct `encode` calls still return `Uint8List`. Each decoder and encoder also implements `Converter`. Every conversion consumes or produces one complete in-memory file rather than an incremental byte stream.

## Color conventions

`toColor()` returns a `PsColor` built with Photoshop's descriptor units: RGB in 0–255, percentages for CMYK ink, HSB saturation and brightness, and grayscale ink, degrees for hue, and CIE L*a*b* values. `fromColor()` performs the inverse conversion. `PsColor.toRgb()` then approximates any process color in sRGB, without color management.

ASE has no HSB model, so HSB colors are stored as RGB. ACT tables only hold 8-bit RGB entries, so `ActColor.fromColor` approximates other colors.

## Strict, tolerant, and bounded decoding

`SwatchDecodeMode.tolerant`, the default, records recoverable problems in the `warnings` list of each file: unknown ACO color spaces, unknown ASE models, color types or blocks, unbalanced ASE groups, invalid ACT trailers, and trailing bytes. `SwatchDecodeMode.strict` turns them into `SwatchFormatException`s.

```dart
final AcoFile swatches = AcoDecoder.decode(
  bytes,
  options: const SwatchDecodeOptions(mode: SwatchDecodeMode.strict),
);
```

Structural truncation and resource-limit failures always throw. `SwatchDecodeOptions` bounds input size, swatch or block counts, and name lengths.

The bundled inspector accepts individual `.aco`, `.ase`, and `.act` files, prints their swatches and warnings, and compares re-encoded bytes with the source:

```console
dart run tool/inspect_swatches.dart swatches.aco palette.ase colors.act
```

## Current boundaries

Color books (`.acb`) are not supported. Conversions to sRGB use textbook formulas rather than ICC profiles.

Tolerant decoding does not guarantee lossless reconstruction: unknown ASE blocks and unrecognized trailing bytes are skipped, ACO sections are rebuilt from the effective swatch list, and unused ACT slots are regenerated. See [docs/SWATCHES.md](docs/SWATCHES.md) for the binary layouts, compatibility rules, encoding boundaries, and validation corpus.

## References

- [Adobe Photoshop File Formats Specification: Color Swatches](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/#50577411_pgfId-1055819)
- [Cyotek: Reading Photoshop color swatch files](https://www.cyotek.com/blog/reading-photoshop-color-swatch-aco-files-using-csharp)
- [`swatch` format notes](https://github.com/nsfmc/swatch)

SwatchKit is an independent implementation and is not affiliated with or endorsed by Adobe.

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
