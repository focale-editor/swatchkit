import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:swatchkit/src/model/swatch_options.dart';

/// Collects warnings and applies limits shared by every swatch decoder.
final class SwatchDecodeContext {
  /// Complete input used as an exception source.
  final Uint8List source;

  /// Caller-selected limits and compatibility behavior.
  final SwatchDecodeOptions options;

  /// Short format name used in messages, such as `ACO`.
  final String format;

  /// Collected tolerant-mode warnings.
  final List<SwatchWarning> warnings = [];

  /// Entry currently being decoded, when applicable.
  int? entryIndex;

  /// Creates an empty decode accumulator after checking the input size.
  SwatchDecodeContext({
    required this.source,
    required this.options,
    required this.format,
  }) {
    if (source.length > options.maxFileBytes) {
      throw SwatchFormatException(message: '$format file size ${source.length} exceeds the configured ${options.maxFileBytes} byte limit', source: source, offset: 0);
    }
  }

  /// Runs [decode], rethrowing low-level failures as [SwatchFormatException].
  T guard<T>(T Function() decode) {
    try {
      return decode();
    } on SwatchFormatException {
      rethrow;
    } on PsFormatException catch (error) {
      throw SwatchFormatException(message: error.message, source: source, offset: error.offset);
    } on RangeError catch (error) {
      throw SwatchFormatException(message: 'Invalid $format numeric range: $error', source: source);
    }
  }

  /// Throws a format error at [offset].
  Never fail(String message, int offset) => throw SwatchFormatException(message: message, source: source, offset: offset);

  /// Rejects an entry count above the configured limit.
  void checkCount(int count, int offset) {
    if (count > options.maxSwatches) {
      fail('$format entry count $count exceeds the configured ${options.maxSwatches} limit', offset);
    }
  }

  /// Reads [length] UTF-16 code units, removing one terminal null.
  String readName(PsBinaryReader reader, int length) {
    if (length > options.maxNameCodeUnits) {
      fail('$format name length $length exceeds the configured ${options.maxNameCodeUnits} limit', reader.offset);
    }
    final List<int> codeUnits = [for (int index = 0; index < length; index++) reader.readUint16()];
    if (codeUnits.isNotEmpty && codeUnits.last == 0) {
      codeUnits.removeLast();
    }
    return String.fromCharCodes(codeUnits);
  }

  /// Promotes a compatibility issue in strict mode or records a warning.
  void issue(String message, int offset) {
    if (options.mode == SwatchDecodeMode.strict) {
      fail(message, offset);
    }
    warnings.add(SwatchWarning(message: message, offset: offset, entryIndex: entryIndex));
  }
}

/// Writes [name] as UTF-16 code units followed by a terminal null.
void writeSwatchName(PsBinaryWriter writer, String name) => writer.writeUint16List([...name.codeUnits, 0]);
