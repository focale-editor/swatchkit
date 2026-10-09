import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:swatchkit/swatchkit.dart';
import 'package:test/test.dart';

/// Exercises the ACO, ASE, and ACT codecs.
void main() {
  group('ACO', () {
    test('prefers named version 2 swatches and re-encodes them identically', () {
      final Uint8List bytes = _fixture('named.aco');
      final AcoFile file = AcoDecoder.decode(bytes);

      check(file.version).equals(2);
      check(file.warnings).isEmpty();
      check(file.swatches.map((swatch) => swatch.name).toList()).deepEquals(['Hearty Red', 'Luscious Pink', 'Deep Navy']);
      check(file.swatches.first.toColor()?.red).equals(212);
      check(const AcoCodec().encode(file)).deepEquals(bytes);
    });

    test('round-trips every process color space', () {
      final List<PsColor> colors = [
        PsColor.rgb(red: 255, green: 128, blue: 0),
        PsColor.hsb(hue: 180, saturation: 50, brightness: 100),
        PsColor.cmyk(cyan: 10, magenta: 20, yellow: 30, black: 40),
        PsColor.lab(lightness: 50, a: -20.5, b: 64),
        PsColor.grayscale(gray: 25),
      ];
      final AcoFile file = AcoFile(swatches: [for (final PsColor color in colors) AcoSwatch.fromColor(color, name: color.classId)]);

      final AcoFile decoded = AcoDecoder.decode(AcoEncoder.encode(file), options: const SwatchDecodeOptions(mode: SwatchDecodeMode.strict));

      check(decoded.swatches.map((swatch) => swatch.colorSpace).toList()).deepEquals([AcoColorSpace.rgb, AcoColorSpace.hsb, AcoColorSpace.cmyk, AcoColorSpace.lab, AcoColorSpace.grayscale]);
      check(decoded.swatches.map((swatch) => swatch.name).toList()).deepEquals(['RGBC', 'HSBC', 'CMYC', 'LbCl', 'Grsc']);
      check(decoded.swatches[0].components).deepEquals([65535, 32896, 0, 0]);
      check(decoded.swatches[2].toColor()?.component('Ylw ')?.value).isNotNull().isCloseTo(30, 0.01);
      check(decoded.swatches[3].toColor()?.component('A   ')?.value).equals(-20.5);
      check(decoded.swatches[4].components.first).equals(7500);
    });

    test('keeps matching-system swatches without a process color', () {
      final AcoFile file = AcoDecoder.decode(
        AcoEncoder.encode(
          AcoFile(
            version: 1,
            swatches: [
              AcoSwatch(colorSpaceId: 3, components: const [1, 2, 3, 4]),
            ],
          ),
        ),
      );

      check(file.version).equals(1);
      check(file.swatches.single.colorSpace).equals(AcoColorSpace.pantone);
      check(file.swatches.single.toColor()).isNull();
      check(() => AcoSwatch.fromColor(PsColor.fromDescriptor(const PsDescriptor(name: '', classId: 'BkCl')))).throws<SwatchWriteException>();
    });

    test('reports unknown spaces and rejects broken input', () {
      final Uint8List unknown = AcoEncoder.encode(
        AcoFile(
          version: 1,
          swatches: [
            AcoSwatch(colorSpaceId: 42, components: const [0, 0, 0, 0]),
          ],
        ),
      );

      check(AcoDecoder.decode(unknown).warnings).length.equals(1);
      check(() => AcoDecoder.decode(unknown, options: const SwatchDecodeOptions(mode: SwatchDecodeMode.strict))).throws<SwatchFormatException>();
      check(() => AcoDecoder.decode(Uint8List.fromList([0, 3, 0, 0]))).throws<SwatchFormatException>();
      check(() => AcoDecoder.decode(Uint8List.fromList([0, 1, 0, 5]))).throws<SwatchFormatException>();
    });
  });

  group('ASE', () {
    test('decodes groups and color types, then re-encodes identically', () {
      final Uint8List bytes = _fixture('sampler.ase');
      final AseFile file = AseDecoder.decode(bytes);
      final List<({AseSwatch swatch, String? group})> swatches = file.swatches.toList();

      check(file.warnings).isEmpty();
      check(file.entries.single).isA<AseGroup>().has((group) => group.name, 'name').equals('Whitefolder');
      check(swatches.map((entry) => entry.swatch.name).toList()).deepEquals(['White', 'lablab', 'mauve', 'grey', 'orange']);
      check(swatches[3].swatch.model).equals(AseColorModel.gray);
      check(swatches.first.swatch.type).equals(AseColorType.normal);
      check(const AseCodec().encode(file)).deepEquals(bytes);
    });

    test('converts Lab spot colors close to their published sRGB values', () {
      final AseSwatch base03 = AseDecoder.decode(_fixture('solarized.ase')).swatches.first.swatch;
      final ({double red, double green, double blue})? rgb = base03.toColor()?.toRgb();

      check(base03.name).equals('Base 03');
      check(base03.type).equals(AseColorType.spot);
      check([rgb!.red.round(), rgb.green.round(), rgb.blue.round()]).deepEquals([0, 43, 54]);
    });

    test('creates swatches from Photoshop colors', () {
      final AseFile file = AseFile(
        entries: [
          AseSwatch.fromColor(PsColor.hsb(hue: 0, saturation: 100, brightness: 100), name: 'Red'),
          AseGroup(
            name: 'Print',
            swatches: [
              AseSwatch.fromColor(PsColor.cmyk(cyan: 100, magenta: 0, yellow: 0, black: 0), name: 'Cyan', type: AseColorType.spot),
              AseSwatch.fromColor(PsColor.grayscale(gray: 100), name: 'Black'),
            ],
          ),
        ],
      );

      final AseFile decoded = AseDecoder.decode(AseEncoder.encode(file), options: const SwatchDecodeOptions(mode: SwatchDecodeMode.strict));
      final List<({AseSwatch swatch, String? group})> swatches = decoded.swatches.toList();

      check(swatches.map((entry) => entry.group).toList()).deepEquals([null, 'Print', 'Print']);
      check(swatches[0].swatch.model).equals(AseColorModel.rgb);
      check(swatches[0].swatch.values).deepEquals([1, 0, 0]);
      check(swatches[1].swatch.values).deepEquals([1, 0, 0, 0]);
      check(swatches[2].swatch.values).deepEquals([0]);
    });

    test('recovers from unbalanced groups unless strict', () {
      final Uint8List bytes = Uint8List.fromList([...ascii.encode('ASEF'), 0, 1, 0, 0, 0, 0, 0, 1, 0xc0, 0x02, 0, 0, 0, 0]);

      check(AseDecoder.decode(bytes).warnings.single.message).contains('no matching group start');
      check(() => AseDecoder.decode(bytes, options: const SwatchDecodeOptions(mode: SwatchDecodeMode.strict))).throws<SwatchFormatException>();
      check(() => AseDecoder.decode(Uint8List.fromList(ascii.encode('ASEX\u0000\u0001')))).throws<SwatchFormatException>();
    });
  });

  group('ACT', () {
    test('round-trips short tables with a transparent entry', () {
      final ActFile file = ActFile(
        colors: [ActColor(red: 255, green: 0, blue: 0), ActColor.fromColor(PsColor.grayscale(gray: 20))],
        transparentIndex: 1,
      );

      final Uint8List bytes = ActEncoder.encode(file);
      final ActFile decoded = const ActCodec().decode(bytes);

      check(bytes.length).equals(772);
      check(decoded.colors).length.equals(2);
      check(decoded.colors[1].green).equals(204);
      check(decoded.transparentIndex).equals(1);
      check(ActEncoder.encode(decoded)).deepEquals(bytes);
    });

    test('reads full tables without a trailer', () {
      final Uint8List bytes = Uint8List(768)..[765] = 9;

      final ActFile file = ActDecoder.decode(bytes);

      check(file.colors).length.equals(256);
      check(file.colors.last.red).equals(9);
      check(file.hasTrailer).isFalse();
      check(ActEncoder.encode(file)).deepEquals(bytes);
    });

    test('rejects malformed sizes and indices', () {
      check(() => ActDecoder.decode(Uint8List(700))).throws<SwatchFormatException>();
      check(ActDecoder.decode(Uint8List.fromList([...Uint8List(768), 0, 2, 0, 5])).warnings).length.equals(1);
      check(() => ActEncoder.encode(ActFile(colors: const []))).throws<SwatchWriteException>();
      check(() => ActColor(red: 256, green: 0, blue: 0)).throws<SwatchWriteException>();
    });
  });
}

/// Reads one base64-encoded fixture.
Uint8List _fixture(String name) => base64Decode(File('test/fixtures/$name.b64').readAsStringSync().replaceAll(RegExp(r'\s'), ''));
