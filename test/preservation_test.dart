import 'dart:typed_data';

import 'package:swatchkit/swatchkit.dart';
import 'package:test/test.dart';

/// Checks forward-compatible payloads independently of the semantic encoders.
void main() {
  test('preserves an opaque ASE block inside a group and file extensions', () {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString('ASEF')
      ..writeUint16(1)
      ..writeUint16(0)
      ..writeUint32(3)
      ..writeUint16(0xc001)
      ..writeUint32(6)
      ..writeUint16(2)
      ..writeUint16(65)
      ..writeUint16(0)
      ..writeUint16(0x1234)
      ..writeUint32(3)
      ..writeBytes(Uint8List.fromList([11, 22, 33]))
      ..writeUint16(0xc002)
      ..writeUint32(0)
      ..writeUint8(99);
    final Uint8List bytes = writer.takeBytes();
    final AseFile file = AseDecoder.decode(bytes);
    expect(file.unknownBlocks.single.index, 1);
    expect(AseEncoder.encode(file), bytes);
    expect(() => AseDecoder.decode(bytes, options: const SwatchDecodeOptions(mode: SwatchDecodeMode.strict)), throwsA(isA<SwatchFormatException>()));
  });
  test('preserves a non-float unknown ASE model and unknown sharing type', () {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString('ASEF')
      ..writeUint16(1)
      ..writeUint16(0)
      ..writeUint32(1)
      ..writeUint16(1)
      ..writeUint32(13)
      ..writeUint16(1)
      ..writeUint16(0)
      ..writeString('NEW!')
      ..writeBytes(Uint8List.fromList([0xff, 0x80, 0x13]))
      ..writeUint16(42);
    final Uint8List bytes = writer.takeBytes();
    final AseFile file = AseDecoder.decode(bytes);
    final AseSwatch swatch = file.swatches.single.swatch;
    expect(swatch.rawTypeCode, 42);
    expect(swatch.rawComponents, [0xff, 0x80, 0x13]);
    expect(swatch.toColor(), isNull);
    expect(AseEncoder.encode(file), bytes);
  });
  test('retains distinct ACO sections and trailing data', () {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeUint16(1)
      ..writeUint16(1)
      ..writeUint16(0)
      ..writeUint16List([1, 2, 3, 0])
      ..writeUint16(2)
      ..writeUint16(1)
      ..writeUint16(0)
      ..writeUint16List([4, 5, 6, 0])
      ..writeUint32(1)
      ..writeUint16(0)
      ..writeUint8(77);
    final Uint8List bytes = writer.takeBytes();
    final AcoFile file = AcoDecoder.decode(bytes);
    expect(file.swatches.single.components, [4, 5, 6, 0]);
    expect(file.versionOneSwatches!.single.components, [1, 2, 3, 0]);
    expect(AcoEncoder.encode(file), bytes);
  });
}
