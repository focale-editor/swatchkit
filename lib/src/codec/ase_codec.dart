import 'dart:convert';
import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:swatchkit/src/codec/swatch_decode_context.dart';
import 'package:swatchkit/src/model/ase_file.dart';
import 'package:swatchkit/src/model/swatch_options.dart';

/// Block type opening a group.
const int _groupStart = 0xc001;

/// Block type closing a group.
const int _groupEnd = 0xc002;

/// Block type holding one swatch.
const int _colorEntry = 0x0001;

/// Decodes Adobe Swatch Exchange `.ase` libraries.
final class AseDecoder extends Converter<List<int>, AseFile> {
  /// Options applied by [convert].
  final SwatchDecodeOptions options;

  /// Creates a reusable decoder with fixed [options].
  const AseDecoder({this.options = const SwatchDecodeOptions()});

  @override
  AseFile convert(List<int> input) => decode(input is Uint8List ? input : Uint8List.fromList(input), options: options);

  /// Decodes one complete in-memory ASE [bytes] buffer.
  static AseFile decode(Uint8List bytes, {SwatchDecodeOptions options = const SwatchDecodeOptions()}) {
    final SwatchDecodeContext context = SwatchDecodeContext(source: bytes, options: options, format: 'ASE');
    return context.guard(() {
      final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
      final String signature = reader.readString(4);
      if (signature != 'ASEF') {
        context.fail('Invalid ASE signature "$signature"; expected "ASEF"', 0);
      }
      final int majorVersion = reader.readUint16();
      final int minorVersion = reader.readUint16();
      if (majorVersion != 1) {
        context.fail('Unsupported ASE version $majorVersion.$minorVersion', 4);
      }
      final int count = reader.readUint32();
      context.checkCount(count, 8);
      final List<AseEntry> entries = [];
      final List<AseUnknownBlock> unknownBlocks = [];
      ({String name, List<AseSwatch> swatches})? group;
      for (int index = 0; index < count; index++) {
        context.entryIndex = index;
        final int blockOffset = reader.offset;
        final int type = reader.readUint16();
        final PsBinaryReader block = reader.readReader(reader.readUint32());
        switch (type) {
          case _colorEntry:
            final AseSwatch swatch = _readSwatch(block, context);
            if (group == null) {
              entries.add(swatch);
            } else {
              group.swatches.add(swatch);
            }
          case _groupStart:
            if (group != null) {
              context.issue('ASE group "${group.name}" is not closed before the next group', blockOffset);
              entries.add(AseGroup(name: group.name, swatches: group.swatches));
            }
            group = (name: context.readName(block, block.readUint16()), swatches: []);
          case _groupEnd:
            if (group == null) {
              context.issue('ASE group end has no matching group start', blockOffset);
            } else {
              entries.add(AseGroup(name: group.name, swatches: group.swatches));
              group = null;
            }
          default:
            context.issue('Unknown ASE block type 0x${type.toRadixString(16)} was preserved', blockOffset);
            unknownBlocks.add(AseUnknownBlock(index: index, type: type, data: block.readBytes(block.remaining)));
        }
      }
      context.entryIndex = null;
      if (group != null) {
        context.issue('ASE group "${group.name}" is never closed', reader.offset);
        entries.add(AseGroup(name: group.name, swatches: group.swatches));
      }
      if (!reader.isAtEnd) {
        context.issue('${reader.remaining} unrecognized trailing bytes remain after the ASE blocks', reader.offset);
      }
      return AseFile(
        majorVersion: majorVersion,
        minorVersion: minorVersion,
        entries: entries,
        unknownBlocks: unknownBlocks,
        trailingData: reader.readBytes(reader.remaining),
        warnings: context.warnings,
      );
    });
  }

  /// Reads one color-entry block.
  static AseSwatch _readSwatch(PsBinaryReader block, SwatchDecodeContext context) {
    final String name = context.readName(block, block.readUint16());
    final int modelOffset = block.baseOffset + block.offset;
    final String modelCode = block.readString(4);
    final AseColorModel model = AseColorModel.fromCode(modelCode);
    if (model == AseColorModel.unknown) {
      context.issue('ASE color model "$modelCode" is not recognized', modelOffset);
    }
    final Uint8List? rawComponents = model == AseColorModel.unknown ? block.readBytes(block.remaining - 2) : null;
    final List<double> values = [for (int index = 0; index < model.componentCount; index++) block.readFloat32()];
    final int typeId = block.readUint16();
    if (typeId >= AseColorType.values.length) {
      context.issue('ASE color type $typeId is not recognized', block.baseOffset + block.offset - 2);
    }
    return AseSwatch(
      name: name,
      modelCode: modelCode,
      values: values,
      type: typeId < AseColorType.values.length ? AseColorType.values[typeId] : null,
      rawTypeCode: typeId,
      rawComponents: rawComponents,
      trailingData: block.readBytes(block.remaining),
    );
  }
}

/// Encodes Adobe Swatch Exchange `.ase` libraries.
final class AseEncoder extends Converter<AseFile, List<int>> {
  /// Creates a reusable encoder.
  const AseEncoder();

  @override
  Uint8List convert(AseFile input) => encode(input);

  /// Encodes [file] as a complete ASE library.
  static Uint8List encode(AseFile file) {
    final List<Uint8List> blocks = [
      for (final AseEntry entry in file.entries)
        ...switch (entry) {
          final AseSwatch swatch => [_block(_colorEntry, (writer) => _writeSwatch(writer, swatch))],
          final AseGroup group => [
            _block(_groupStart, (writer) => _writeName(writer, group.name)),
            for (final AseSwatch swatch in group.swatches) _block(_colorEntry, (writer) => _writeSwatch(writer, swatch)),
            _block(_groupEnd, (_) {}),
          ],
        },
    ];
    final List<AseUnknownBlock> unknown = [...file.unknownBlocks]..sort((a, b) => a.index.compareTo(b.index));
    final List<Uint8List> ordered = [];
    int nextKnown = 0;
    for (final AseUnknownBlock block in unknown) {
      if (block.index < 0 || block.type < 0 || block.type > 0xffff || const [_colorEntry, _groupStart, _groupEnd].contains(block.type)) {
        throw const SwatchWriteException(message: 'Invalid opaque ASE block position or type');
      }
      while (ordered.length < block.index && nextKnown < blocks.length) {
        ordered.add(blocks[nextKnown++]);
      }
      ordered.add(_block(block.type, (writer) => writer.writeBytes(block.data)));
    }
    ordered.addAll(blocks.skip(nextKnown));
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString('ASEF')
      ..writeUint16(file.majorVersion)
      ..writeUint16(file.minorVersion)
      ..writeUint32(ordered.length);
    ordered.forEach(writer.writeBytes);
    writer.writeBytes(file.trailingData);
    return writer.takeBytes();
  }

  /// Frames the payload written by [write] as a block of [type].
  static Uint8List _block(int type, void Function(PsBinaryWriter writer) write) {
    final PsBinaryWriter payload = PsBinaryWriter();
    write(payload);
    final Uint8List bytes = payload.takeBytes();
    return (PsBinaryWriter()
          ..writeUint16(type)
          ..writeUint32(bytes.length)
          ..writeBytes(bytes))
        .takeBytes();
  }

  /// Writes a length-prefixed, null-terminated UTF-16 [name].
  static void _writeName(PsBinaryWriter writer, String name) {
    if (name.length >= 0xffff) {
      throw SwatchWriteException(message: 'ASE name "${name.substring(0, 16)}…" is too long');
    }
    writer.writeUint16(name.length + 1);
    writeSwatchName(writer, name);
  }

  /// Writes one color-entry payload.
  static void _writeSwatch(PsBinaryWriter writer, AseSwatch swatch) {
    final int? type = swatch.type?.index ?? swatch.rawTypeCode;
    if (swatch.modelCode.length != 4 || type == null || type < 0 || type > 0xffff) {
      throw SwatchWriteException(message: 'ASE swatch "${swatch.name}" has no writable color model or type');
    }
    _writeName(writer, swatch.name);
    writer.writeString(swatch.modelCode);
    if ((swatch.model, swatch.rawComponents) case (AseColorModel.unknown, final Uint8List components)) {
      writer.writeBytes(components);
    } else {
      if (swatch.model != AseColorModel.unknown && swatch.values.length != swatch.model.componentCount) {
        throw const SwatchWriteException(message: 'ASE component count does not match its color model');
      }
      swatch.values.forEach(writer.writeFloat32);
    }
    writer.writeUint16(type);
    writer.writeBytes(swatch.trailingData);
  }
}

/// Converts ASE models to and from their binary representation.
final class AseCodec extends Codec<AseFile, List<int>> {
  /// Options applied while decoding.
  final SwatchDecodeOptions decodeOptions;

  /// Creates a reusable codec.
  const AseCodec({this.decodeOptions = const SwatchDecodeOptions()});

  @override
  AseDecoder get decoder => AseDecoder(options: decodeOptions);

  @override
  AseEncoder get encoder => const AseEncoder();

  @override
  Uint8List encode(AseFile input) => encoder.convert(input);
}
