import 'dart:convert';
import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:swatchkit/src/codec/swatch_decode_context.dart';
import 'package:swatchkit/src/model/aco_file.dart';
import 'package:swatchkit/src/model/swatch_options.dart';

/// Decodes Photoshop `.aco` swatch libraries.
///
/// A library holds a version 1 section, normally followed by a version 2
/// section repeating the same colors with names. The named section wins.
final class AcoDecoder extends Converter<List<int>, AcoFile> {
  /// Options applied by [convert].
  final SwatchDecodeOptions options;

  /// Creates a reusable decoder with fixed [options].
  const AcoDecoder({this.options = const SwatchDecodeOptions()});

  @override
  AcoFile convert(List<int> input) => decode(input is Uint8List ? input : Uint8List.fromList(input), options: options);

  /// Decodes one complete in-memory ACO [bytes] buffer.
  static AcoFile decode(Uint8List bytes, {SwatchDecodeOptions options = const SwatchDecodeOptions()}) {
    final SwatchDecodeContext context = SwatchDecodeContext(source: bytes, options: options, format: 'ACO');
    return context.guard(() {
      final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
      final int firstVersion = reader.readUint16();
      if (firstVersion != 1 && firstVersion != 2) {
        context.fail('Unsupported ACO version $firstVersion', 0);
      }
      List<AcoSwatch> swatches = _readSection(reader, firstVersion, context);
      int version = firstVersion;
      if (firstVersion == 1 && reader.remaining >= 4) {
        final int sectionOffset = reader.offset;
        final int secondVersion = reader.readUint16();
        if (secondVersion == 2) {
          final List<AcoSwatch> named = _readSection(reader, 2, context);
          if (named.length != swatches.length) {
            context.issue('The ACO version 2 section holds ${named.length} swatches instead of ${swatches.length}', sectionOffset);
          }
          swatches = named;
          version = 2;
        } else {
          context.issue('Unexpected ACO section version $secondVersion', sectionOffset);
        }
      }
      if (!reader.isAtEnd) {
        context.issue('${reader.remaining} unrecognized trailing bytes remain after the ACO swatches', reader.offset);
      }
      return AcoFile(swatches: swatches, version: version, warnings: context.warnings);
    });
  }

  /// Reads one counted section of [version] at the current position.
  static List<AcoSwatch> _readSection(PsBinaryReader reader, int version, SwatchDecodeContext context) {
    final int count = reader.readUint16();
    context.checkCount(count, reader.offset - 2);
    final List<AcoSwatch> swatches = [];
    for (int index = 0; index < count; index++) {
      context.entryIndex = index;
      final int recordOffset = reader.offset;
      final int colorSpaceId = reader.readUint16();
      final List<int> components = [for (int component = 0; component < 4; component++) reader.readUint16()];
      final String? name = version == 2 ? context.readName(reader, reader.readUint32()) : null;
      if (AcoColorSpace.fromId(colorSpaceId) == AcoColorSpace.unknown) {
        context.issue('ACO color space $colorSpaceId is not recognized', recordOffset);
      }
      swatches.add(AcoSwatch(colorSpaceId: colorSpaceId, components: components, name: name));
    }
    context.entryIndex = null;
    return swatches;
  }
}

/// Encodes Photoshop `.aco` swatch libraries.
final class AcoEncoder extends Converter<AcoFile, List<int>> {
  /// Creates a reusable encoder.
  const AcoEncoder();

  @override
  Uint8List convert(AcoFile input) => encode(input);

  /// Encodes [file] as a version 1 section, followed by a named version 2
  /// section unless [file] has version 1.
  static Uint8List encode(AcoFile file) {
    if (file.swatches.length > 0xffff) {
      throw SwatchWriteException(message: 'An ACO library holds at most 65535 swatches, not ${file.swatches.length}');
    }
    final PsBinaryWriter writer = PsBinaryWriter();
    for (final int version in [1, if (file.version >= 2) 2]) {
      writer
        ..writeUint16(version)
        ..writeUint16(file.swatches.length);
      for (final AcoSwatch swatch in file.swatches) {
        writer
          ..writeUint16(swatch.colorSpaceId)
          ..writeUint16List(swatch.components);
        if (version == 2) {
          final String name = swatch.name ?? '';
          writer.writeUint32(name.length + 1);
          writeSwatchName(writer, name);
        }
      }
    }
    return writer.takeBytes();
  }
}

/// Converts ACO models to and from their binary representation.
final class AcoCodec extends Codec<AcoFile, List<int>> {
  /// Options applied while decoding.
  final SwatchDecodeOptions decodeOptions;

  /// Creates a reusable codec.
  const AcoCodec({this.decodeOptions = const SwatchDecodeOptions()});

  @override
  AcoDecoder get decoder => AcoDecoder(options: decodeOptions);

  @override
  AcoEncoder get encoder => const AcoEncoder();

  @override
  Uint8List encode(AcoFile input) => encoder.convert(input);
}
