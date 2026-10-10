import 'dart:convert';
import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:swatchkit/src/codec/swatch_decode_context.dart';
import 'package:swatchkit/src/model/acb_file.dart';
import 'package:swatchkit/src/model/swatch_options.dart';

/// Signature opening every color book.
const String _signature = '8BCB';

/// Decodes Photoshop `.acb` color books.
final class AcbDecoder extends Converter<List<int>, AcbFile> {
  /// Options applied by [convert].
  final SwatchDecodeOptions options;

  /// Creates a reusable decoder with fixed [options].
  const AcbDecoder({this.options = const SwatchDecodeOptions()});

  @override
  AcbFile convert(List<int> input) => decode(input is Uint8List ? input : Uint8List.fromList(input), options: options);

  /// Decodes one complete in-memory ACB [bytes] buffer.
  static AcbFile decode(Uint8List bytes, {SwatchDecodeOptions options = const SwatchDecodeOptions()}) {
    final SwatchDecodeContext context = SwatchDecodeContext(source: bytes, options: options, format: 'ACB');
    return context.guard(() {
      final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
      if (bytes.length < 4 || reader.readString(4) != _signature) {
        context.fail('An ACB color book starts with "$_signature"', 0);
      }
      final int version = reader.readUint16();
      if (version != 1) {
        context.issue('ACB version $version is not 1', 4);
      }
      final int identifier = reader.readUint16();
      final String title = _readText(reader, context);
      final String prefix = _readText(reader, context);
      final String postfix = _readText(reader, context);
      final String description = _readText(reader, context);
      final int countOffset = reader.offset;
      final int count = reader.readUint16();
      context.checkCount(count, countOffset);
      final int pageSize = reader.readUint16();
      final int pageSelectorOffset = reader.readUint16();
      final int modelOffset = reader.offset;
      final int modelId = reader.readUint16();
      final AcbColorModel colorModel = AcbColorModel.fromId(modelId) ?? context.fail('ACB color model $modelId is not RGB (0), CMYK (2) or Lab (7)', modelOffset);
      final List<AcbColor> colors = [];
      for (int index = 0; index < count; index++) {
        context.entryIndex = index;
        final String name = _readText(reader, context);
        final String code = reader.readString(6);
        colors.add(AcbColor(name: name, code: code, components: reader.readBytes(colorModel.componentCount)));
      }
      context.entryIndex = null;
      final Uint8List trailingData = reader.readBytes(reader.remaining);
      if (trailingData.isNotEmpty && trailingData.length != 8) {
        context.issue('${trailingData.length} unrecognized bytes follow the ACB colors', bytes.length - trailingData.length);
      }
      return AcbFile(
        version: version,
        identifier: identifier,
        title: title,
        prefix: prefix,
        postfix: postfix,
        description: description,
        pageSize: pageSize,
        pageSelectorOffset: pageSelectorOffset,
        colorModel: colorModel,
        colors: colors,
        trailingData: trailingData,
        warnings: context.warnings,
      );
    });
  }

  /// Reads a length-prefixed UTF-16 string, keeping every code unit.
  static String _readText(PsBinaryReader reader, SwatchDecodeContext context) {
    final int offset = reader.offset;
    final int length = reader.readUint32();
    if (length > context.options.maxNameCodeUnits) {
      context.fail('ACB text length $length exceeds the configured ${context.options.maxNameCodeUnits} limit', offset);
    }
    return String.fromCharCodes([for (int index = 0; index < length; index++) reader.readUint16()]);
  }
}

/// Encodes Photoshop `.acb` color books.
final class AcbEncoder extends Converter<AcbFile, List<int>> {
  /// Creates a reusable encoder.
  const AcbEncoder();

  @override
  Uint8List convert(AcbFile input) => encode(input);

  /// Encodes [file].
  static Uint8List encode(AcbFile file) {
    if (file.colors.length > 0xffff) {
      throw SwatchWriteException(message: 'An ACB color book holds at most 65535 colors, not ${file.colors.length}');
    }
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString(_signature)
      ..writeUint16(file.version)
      ..writeUint16(file.identifier);
    for (final String text in [file.title, file.prefix, file.postfix, file.description]) {
      _writeText(writer, text);
    }
    writer
      ..writeUint16(file.colors.length)
      ..writeUint16(file.pageSize)
      ..writeUint16(file.pageSelectorOffset)
      ..writeUint16(file.colorModel.id);
    for (final AcbColor color in file.colors) {
      if (color.components.length != file.colorModel.componentCount) {
        throw SwatchWriteException(message: 'An ACB ${file.colorModel.name} color holds ${file.colorModel.componentCount} components, not ${color.components.length}');
      }
      _writeText(writer, color.name);
      writer
        ..writeString(color.code)
        ..writeBytes(Uint8List.fromList(color.components));
    }
    writer.writeBytes(file.trailingData);
    return writer.takeBytes();
  }

  /// Writes [text] as a length-prefixed UTF-16 string.
  static void _writeText(PsBinaryWriter writer, String text) {
    writer
      ..writeUint32(text.length)
      ..writeUint16List(text.codeUnits);
  }
}

/// Converts ACB models to and from their binary representation.
final class AcbCodec extends Codec<AcbFile, List<int>> {
  /// Options applied while decoding.
  final SwatchDecodeOptions decodeOptions;

  /// Creates a reusable codec.
  const AcbCodec({this.decodeOptions = const SwatchDecodeOptions()});

  @override
  AcbDecoder get decoder => AcbDecoder(options: decodeOptions);

  @override
  AcbEncoder get encoder => const AcbEncoder();

  @override
  Uint8List encode(AcbFile input) => encoder.convert(input);
}
