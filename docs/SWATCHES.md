# Swatch library format support

This document describes the ACO, ASE, and ACT structures accepted by SwatchKit, their color conventions, and the boundaries of source reconstruction. Multibyte numeric values are big-endian.

## Supported containers

| Format | Model | Contents |
| --- | --- | --- |
| Photoshop swatches (`.aco`) | `AcoFile` | Process colors and matching-system references, with optional names |
| Adobe Swatch Exchange (`.ase`) | `AseFile` | Named swatches and groups, with color types |
| Photoshop color table (`.act`) | `ActFile` | An indexed RGB palette with an optional transparent entry |

Call the decoder matching the file format. Each format also has an encoder and a `dart:convert` codec for complete in-memory files.

## ACO layout

A file holds one or two sections. Each starts with a 16-bit version and a 16-bit swatch count, followed by the swatches. A swatch is a 16-bit color-space identifier and four 16-bit components; version 2 adds a 32-bit length and a null-terminated UTF-16 name, the length counting the terminator. Photoshop writes a version 1 section followed by a version 2 section; when both are present, the named section wins and a count mismatch is reported.

| Identifier | Space | Components |
| --- | --- | --- |
| 0 | RGB | 0–65535 per channel |
| 1 | HSB | Hue, saturation, and brightness over 0–65535 |
| 2 | CMYK | 0–65535, where 0 is full ink |
| 3, 4, 5, 6, 10 | Pantone, Focoltone, Trumatch, Toyo, HKS | Matching-system references |
| 7 | Lab | Lightness 0–10000, then signed a and b in hundredths |
| 8 | Grayscale | 0–10000, where 10000 is white |
| 9 | Wide CMYK | 0–10000, where 10000 is full ink |

`AcoSwatch.colorSpaceId` and `components` retain the original numeric values. `toColor()` converts supported process colors to `PsColor`; matching-system references and unknown color spaces return `null` while their raw values remain accessible.

`AcoFile.swatches` contains the effective section only. It does not retain separate version 1 and version 2 lists when both exist.

## ASE layout

The header is `ASEF`, a 16-bit major and minor version (1.0), and a 32-bit block count. Each block is a 16-bit type and a 32-bit payload length:

| Type | Payload |
| --- | --- |
| `0xC001` | Group start: 16-bit name length, then the null-terminated UTF-16 name |
| `0xC002` | Group end: empty |
| `0x0001` | Color: name as above, a four-character model, 32-bit floats, then a 16-bit type (0 global, 1 spot, 2 normal) |

| Model | Values |
| --- | --- |
| `RGB ` | Three values in 0–1 |
| `CMYK` | Four ink values in 0–1 |
| `LAB ` | Lightness in 0–1, then a and b in −128–127 |
| `Gray` | One value in 0–1, where 1 is white |

Groups do not nest. SwatchKit closes an open group when another one starts, and reports it.

`AseFile.entries` preserves the order of top-level swatches and `AseGroup` values. `AseFile.swatches` provides flattened iteration with each swatch's enclosing group name. `AseSwatch.modelCode`, `values`, and `type` expose the stored color representation; an unknown type is reported and represented by `null`.

## ACT layout

256 RGB triplets (768 bytes), optionally followed by a 16-bit color count and a 16-bit transparent index (`0xFFFF` for none).

| Field | Size | Meaning |
| --- | ---: | --- |
| RGB table | 768 bytes | 256 entries of three unsigned 8-bit components |
| Active color count | 2 bytes, optional | Number of active entries, from 1 through 256 |
| Transparent index | 2 bytes, optional | Zero-based active entry index, or `0xFFFF` |

The decoder accepts exactly 768 or 772 bytes. Without a trailer, all 256 entries are active. `ActFile.colors` contains only active entries, `transparentIndex` is nullable, and `hasTrailer` records whether the optional fields were present.

In tolerant mode, an invalid count is reported and treated as 256; an out-of-range transparent index is reported and ignored. Strict mode rejects either issue.

## Color conversions

`toColor()` exposes process colors in Photoshop descriptor units:

| Space | `PsColor` convention |
| --- | --- |
| RGB | Channels from 0 through 255 |
| CMYK | Ink percentages from 0 through 100 |
| HSB | Hue in degrees; saturation and brightness as percentages |
| Grayscale | Ink percentage, where 0 is white |
| Lab | CIE L*a*b* values |

`AcoSwatch.fromColor` and `AseSwatch.fromColor` perform the inverse conversion for supported process colors. ASE has no HSB model, so HSB input is stored as RGB. `ActColor.fromColor` converts to an approximate 8-bit sRGB value.

These conversions do not apply ICC profiles or resolve proprietary matching-system references. Preserve the stored components when an application's own color-management pipeline needs the original representation.

## Decoding modes and limits

`SwatchDecodeMode.tolerant` is the default. Recoverable issues are reported as `SwatchWarning` values in each file's `warnings` list. They include unknown ACO color spaces, mismatched ACO section counts, unknown ASE blocks, models or color types, unbalanced ASE groups, invalid ACT trailers, and unrecognized trailing bytes.

`SwatchDecodeMode.strict` promotes the first compatibility issue to `SwatchFormatException`. Structural truncation, unsupported ACO versions, invalid ASE signatures, and invalid ACT file lengths stop decoding in either mode.

The shared `SwatchDecodeOptions` bounds input size with `maxFileBytes`, swatch or block counts with `maxSwatches`, and UTF-16 name lengths with `maxNameCodeUnits`. Resource-limit failures always throw rather than becoming warnings.

## Encoding and preservation boundaries

Encoders write the current semantic models. They do not preserve complete source files or arbitrary trailing bytes.

| Format | Output behavior |
| --- | --- |
| ACO | Writes a version 1 section, followed by a named version 2 section when `AcoFile.version` is at least 2 |
| ASE | Rebuilds block lengths and counts from `AseFile.entries`, including group start and end blocks |
| ACT | Writes 256 RGB slots, fills unused slots with black, and includes the count/transparency trailer when `hasTrailer` is true |

Supported samples can re-encode byte for byte, but this is not a general guarantee for tolerant input:

- ACO retains one effective swatch list, so differing source sections are not independently reconstructed. A version 2-only source is written as a version 1 plus version 2 pair.
- ASE skips unknown blocks and trailing bytes, and normalizes unbalanced groups. An unknown color type cannot be encoded until the caller supplies a supported type.
- ACT retains active entries only. Unused source slots are replaced with black, and invalid trailer values are normalized during tolerant decoding.

ACO output is limited to 65,535 swatches. ACT output requires 1–256 colors and a transparent index within that list; a table without a trailer must contain 256 opaque colors. The encoders report these model errors through `SwatchWriteException`.

## Integration guidance

Keep palette decoding outside the presentation layer. Retain names, source order, ASE groups and color types, and the original component values alongside any preview color. A `null` process-color conversion means the application needs another way to interpret or display that entry.

The models are immutable. Build a new `AcoFile`, `AseFile`, or `ActFile` when editing; use `AseGroup` to retain grouping and `ActFile.transparentIndex` to retain indexed transparency. SwatchKit does not support Adobe Color Book (`.acb`) files or perform color-managed rendering.

## Validation corpus

The bundled fixtures exercise decoding without warnings and byte-exact re-encoding:

- [`adobe-aco`](https://github.com/szydlovski/adobe-aco) (MIT): a named version 2 ACO, kept as a test fixture;
- [`swatch`](https://github.com/nsfmc/swatch) (MIT): `sampler.ase` and `solarized.ase`, covering groups and process or spot colors.

Synthetic tests also cover process-color conversions, matching-system references, group recovery, ACT transparency, and malformed input. Fixture provenance is recorded in [test/fixtures/NOTICE.txt](../test/fixtures/NOTICE.txt).

The broader implementation corpus recorded successful round trips of five `swatch` ASE files, plus Krita's pigment test data: an RGB-only version 1 ACO with 18 swatches, an ASE with 249 swatches, and a 16-color ACT with a transparent entry. The Krita files are GPL-licensed, were used locally only, and are not bundled.

The inspector reports warnings and byte equality for individual local files:

```console
dart run tool/inspect_swatches.dart swatches.aco palette.ase colors.act
```

## References

- [Adobe Photoshop File Formats Specification: Color Swatches](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/#50577411_pgfId-1055819)
- [Cyotek: Reading Photoshop color swatch files](https://www.cyotek.com/blog/reading-photoshop-color-swatch-aco-files-using-csharp)
- [`swatch` format notes](https://github.com/nsfmc/swatch)
