import 'package:pscore/pscore.dart';

/// Controls whether recoverable swatch-library issues stop decoding.
enum SwatchDecodeMode {
  /// Rejects unknown records and malformed optional data.
  strict,

  /// Skips or preserves recoverable defects and reports them as warnings.
  tolerant,
}

/// Resource limits applied while decoding a swatch library.
final class SwatchDecodeOptions {
  /// Handling policy for recoverable defects.
  final SwatchDecodeMode mode;

  /// Maximum accepted input size.
  final int maxFileBytes;

  /// Maximum number of swatches or blocks declared by one library.
  final int maxSwatches;

  /// Maximum UTF-16 code-unit count accepted for one name.
  final int maxNameCodeUnits;

  /// Creates bounded decode options suitable for untrusted input.
  const SwatchDecodeOptions({
    this.mode = SwatchDecodeMode.tolerant,
    this.maxFileBytes = 64 * 1024 * 1024,
    this.maxSwatches = 100000,
    this.maxNameCodeUnits = 4096,
  });
}

/// Describes a recoverable compatibility issue found while decoding.
final class SwatchWarning extends PsWarning {
  /// Zero-based swatch or block index associated with the issue, when known.
  final int? entryIndex;

  /// Creates a warning with optional source context.
  const SwatchWarning({
    required super.message,
    super.offset,
    this.entryIndex,
  });

  @override
  String get typeName => 'SwatchWarning';

  @override
  String get context {
    final int? currentEntryIndex = entryIndex;
    return currentEntryIndex == null ? '' : ' in entry ${currentEntryIndex + 1}';
  }
}

/// Reports malformed, truncated, unsupported, or unsafe swatch input.
final class SwatchFormatException extends PsFormatException {
  /// Creates an error at an optional absolute byte [offset].
  const SwatchFormatException({
    required super.message,
    super.source,
    super.offset,
  });

  @override
  String get typeName => 'SwatchFormatException';
}

/// Reports a swatch that cannot be represented by the requested format.
final class SwatchWriteException extends PsWriteException {
  /// Creates an encoding error with a user-facing [message].
  const SwatchWriteException({
    required super.message,
  });

  @override
  String get typeName => 'SwatchWriteException';
}
