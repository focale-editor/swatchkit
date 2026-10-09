import 'dart:convert';
import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:swatchkit/src/codec/swatch_decode_context.dart';
import 'package:swatchkit/src/model/act_file.dart';
import 'package:swatchkit/src/model/swatch_options.dart';

/// Size of the fixed 256-entry RGB table.
const int _tableBytes = 768;

/// Value of the transparency field when no entry is transparent.
const int _noTransparency = 0xffff;

/// Decodes Photoshop `.act` color tables.
final class ActDecoder extends Converter<List<int>, ActFile> {
  /// Options applied by [convert].
  final SwatchDecodeOptions options;

  /// Creates a reusable decoder with fixed [options].
  const ActDecoder({this.options = const SwatchDecodeOptions()});

  @override
  ActFile convert(List<int> input) => decode(input is Uint8List ? input : Uint8List.fromList(input), options: options);

  /// Decodes one complete in-memory ACT [bytes] buffer.
  static ActFile decode(Uint8List bytes, {SwatchDecodeOptions options = const SwatchDecodeOptions()}) {
    final SwatchDecodeContext context = SwatchDecodeContext(source: bytes, options: options, format: 'ACT');
    return context.guard(() {
      if (bytes.length != _tableBytes && bytes.length != _tableBytes + 4) {
        context.fail('An ACT table holds 768 or 772 bytes, not ${bytes.length}', 0);
      }
      final PsBinaryReader reader = PsBinaryReader(bytes: bytes)..skip(_tableBytes);
      int count = 256;
      int? transparentIndex;
      if (!reader.isAtEnd) {
        count = reader.readUint16();
        final int transparency = reader.readUint16();
        if (count == 0 || count > 256) {
          context.issue('ACT color count $count is outside the 1–256 range', _tableBytes);
          count = 256;
        }
        if (transparency != _noTransparency) {
          if (transparency < count) {
            transparentIndex = transparency;
          } else {
            context.issue('ACT transparent index $transparency is outside the table', _tableBytes + 2);
          }
        }
      }
      return ActFile(
        colors: [for (int index = 0; index < count; index++) ActColor(red: bytes[index * 3], green: bytes[index * 3 + 1], blue: bytes[index * 3 + 2])],
        transparentIndex: transparentIndex,
        hasTrailer: bytes.length > _tableBytes,
        warnings: context.warnings,
      );
    });
  }
}

/// Encodes Photoshop `.act` color tables.
final class ActEncoder extends Converter<ActFile, List<int>> {
  /// Creates a reusable encoder.
  const ActEncoder();

  @override
  Uint8List convert(ActFile input) => encode(input);

  /// Encodes [file], padding unused table entries with black.
  static Uint8List encode(ActFile file) {
    final int count = file.colors.length;
    final int? transparentIndex = file.transparentIndex;
    if (count == 0 || count > 256) {
      throw SwatchWriteException(message: 'An ACT table holds 1 to 256 colors, not $count');
    }
    if (transparentIndex != null && (transparentIndex < 0 || transparentIndex >= count)) {
      throw SwatchWriteException(message: 'ACT transparent index $transparentIndex is outside the table');
    }
    if (!file.hasTrailer && (count != 256 || transparentIndex != null)) {
      throw const SwatchWriteException(message: 'An ACT table without a trailer must hold 256 opaque colors');
    }
    final PsBinaryWriter writer = PsBinaryWriter();
    for (final ActColor color in file.colors) {
      writer
        ..writeUint8(color.red)
        ..writeUint8(color.green)
        ..writeUint8(color.blue);
    }
    writer.writeZeros((256 - count) * 3);
    if (file.hasTrailer) {
      writer
        ..writeUint16(count)
        ..writeUint16(transparentIndex ?? _noTransparency);
    }
    return writer.takeBytes();
  }
}

/// Converts ACT models to and from their binary representation.
final class ActCodec extends Codec<ActFile, List<int>> {
  /// Options applied while decoding.
  final SwatchDecodeOptions decodeOptions;

  /// Creates a reusable codec.
  const ActCodec({this.decodeOptions = const SwatchDecodeOptions()});

  @override
  ActDecoder get decoder => ActDecoder(options: decodeOptions);

  @override
  ActEncoder get encoder => const ActEncoder();

  @override
  Uint8List encode(ActFile input) => encoder.convert(input);
}
