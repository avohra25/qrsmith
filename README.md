# qrsmith

A QR Code encoder written from scratch in pure Perl. It has no CPAN dependencies: everything from GF(2^8) arithmetic to PNG output uses only modules that ship with Perl.

```console
$ qrsmith --info -e Q 'HELLO WORLD'
version 1 (21x21), level Q, mask 0, segments: alphanumeric(11)

  █▀▀▀▀▀█ █▀ ▄  █▀▀▀▀▀█
  █ ███ █ █  ▀▀ █ ███ █
  █ ▀▀▀ █ ▀ █   █ ▀▀▀ █
  ▀▀▀▀▀▀▀ █ ▀ ▀ ▀▀▀▀▀▀▀
   █▀ ▀ ▀▀▄▄▄▄▀ ▀ █▀▀▀█
   ▄█▀▄█▀█ ▀█▄ ▄▀▄▀█▄▄
  ▀   ▀ ▀ █▄▀█▀ █▀▀ █ █
  █▀▀▀▀▀█ ▀▄▀▄▄ ▄█ █▀
  █ ███ █ ▀▄▀▄ ▄▀█▀▀▀█▀
  █ ▀▀▀ █ █ ▄█▄█▀▀ █ ▄█
  ▀▀▀▀▀▀▀    ▀ ▀▀▀    ▀
```

## Features

- All 40 versions and all four error-correction levels (L, M, Q, H).
- Numeric, alphanumeric, byte (UTF-8) and ECI segments. An **optimal segmenter** picks the cheapest mix of modes, so `Call 4155550123 ...` becomes `byte(5), numeric(10), byte(45)` instead of one long byte segment.
- Automatic version selection. The EC level is **boosted for free** to the highest one that still fits in the same version (turn this off with `boost => 0`).
- All eight data masks, scored with the ISO/IEC 18004 penalty rules (N1 to N4). You can also force a mask.
- A Reed-Solomon codec for GF(256) that **decodes** as well as encodes. The decoder uses Berlekamp-Massey, a Chien search and Forney's algorithm, and corrects up to `2e + f <= n` errors (`e`) and erasures (`f`).
- Renderers for SVG (one compact `<path>`), 1-bit PNG (via core `Compress::Zlib`), PBM and the terminal (Unicode half blocks or ASCII).
- **Payload helpers** (`QRSmith::Payload`) that build properly escaped Wi-Fi, vCard, mailto, SMS, geo and URL strings.
- **Structured Append** (`QRSmith->encode_structured`): split one logical payload across 2–16 linked symbols with ISO parity.

## Install

```sh
perl Makefile.PL && make && make test && make install
# or just run it in place:
perl bin/qrsmith 'hello'
```

Requires Perl 5.16 or newer and nothing else.

## Command line

```
Usage: qrsmith [options] [TEXT]
Encode TEXT (or standard input) as a QR Code.

  -e, --ecl L|M|Q|H      error correction level (default M)
  -f, --format FMT       term (default), ascii, svg, png or pbm; inferred
                         from the --output extension when not given
  -o, --output FILE      write to FILE instead of standard output
  -s, --scale N          pixels per module for svg/png (default 8)
  -q, --quiet N          quiet-zone width in modules (default 4; 2 for term)
      --min-version N    smallest version to consider (1-40)
      --max-version N    largest version to consider (1-40)
  -m, --mask N           force data mask 0-7 (default: lowest penalty)
      --strategy S       optimal (default), auto or byte segmentation
      --no-boost         keep the requested EC level even if a higher fits
      --eci N            prefix an ECI designator (26 = UTF-8)
      --dark COLOUR      dark colour for svg, e.g. #1a1a2e
      --light COLOUR     light colour for svg
  -i, --invert           invert terminal output (for light-on-dark themes)
      --info             print version, level, mask and segments to stderr

  Payload helpers:
      --wifi SSID        Wi-Fi join payload (with --password/--security/--hidden)
      --mailto ADDR      mailto: URI (with --subject/--body)
      --sms NUMBER       SMSTO: payload (with --body)
      --geo LAT,LON      geo: URI (with --geo-query)
      --vcard-name NAME  minimal vCard 3.0
      --url URL          normalise / passthrough a URL

  Structured Append:
      --parts N          split across N symbols (2-16); alias --structured-append
                         With -o FILE, siblings FILE-01.ext .. FILE-NN.ext are written.
```

```sh
qrsmith -e H -s 10 --dark '#1a1a2e' -o examples/hello.svg https://github.com/avohra25/qrsmith
qrsmith -s 6 -o examples/hello.png https://github.com/avohra25/qrsmith
qrsmith --wifi 'LabNet' --password 's3cret!' -o examples/wifi.svg
qrsmith --vcard-name 'Ada Lovelace' --vcard-email ada@example.com -o examples/vcard.svg
qrsmith --geo 37.7749,-122.4194 --geo-query 'San Francisco' -o examples/geo.svg
qrsmith --parts 3 -o /tmp/chunk.svg 'a long payload split across three symbols'
```

## Library

```perl
use QRSmith;
use QRSmith::Payload qw(wifi vcard mailto sms geo url);
use QRSmith::Render qw(to_svg to_png to_terminal);

my $qr = QRSmith->encode('https://example.com', ecl => 'M');
printf "%d-%s mask %d, %dx%d\n", $qr->version, $qr->ecl, $qr->mask, $qr->size, $qr->size;
$qr->module($x, $y);          # 1 = dark
$qr->rows;                    # arrayref of rows of 0/1
$qr->segments;                # [{ mode => 'byte', chars => 19 }]

open my $fh, '>:raw', 'qr.png' or die; print {$fh} to_png($qr, scale => 6);
print to_svg($qr, scale => 8, quiet => 4, dark => '#000', light => '#fff');
```

`encode` takes these options: `ecl`, `strategy` (`optimal`, `auto`, `byte`), `min_version`, `max_version`, `mask`, `boost` and `eci`. If the text cannot fit, it dies with a "does not fit" message. To control the segments yourself, build them with `QRSmith::Segment` (`make_numeric`, `make_alphanumeric`, `make_bytes`, `make_eci`, `make_structured_append`) and pass them to `QRSmith->encode_segments(\@segs, %opt)`.

### Payload helpers

`QRSmith::Payload` builds the usual scanner-friendly strings. Every helper returns a plain Perl string that you pass to `QRSmith->encode` (or the thin `QRSmith->encode_payload` wrapper):

```perl
use QRSmith::Payload qw(wifi vcard mailto sms geo url);

wifi(ssid => 'home', password => 'hunter22', security => 'WPA');
# → WIFI:T:WPA;S:home;P:hunter22;;
#   (; , \ " inside fields are backslash-escaped; hidden => 1 adds H:true)

vcard(name => 'Ada Lovelace', org => 'Analytical Engines',
      phone => '+1-555-0100', email => 'ada@example.com');
# → BEGIN:VCARD / VERSION:3.0 / N:… / FN:… / … / END:VCARD

mailto(email => 'a@b.co', subject => 'Hi', body => 'line & 2');
# → mailto:a@b.co?subject=Hi&body=line%20%26%202

sms(number => '+1 555 0100', body => 'hello');   # SMSTO:+15550100:hello
geo(lat => 37.7749, lon => -122.4194, query => 'SF');
url('example.com/x');   # → https://example.com/x
```

### Structured Append

ISO/IEC 18004 Structured Append links 2–16 symbols into one logical payload. Each symbol starts with a Structured Append header (mode indicator `0011`, a 4-bit 0-based index, a 4-bit `total−1` field and an 8-bit parity) followed by its data slice. The parity is the bytewise XOR of every raw input octet and is identical in every symbol.

```perl
my $parts = QRSmith->encode_structured($long_text, parts => 4, ecl => 'M');
for my $i (0 .. $#$parts) {
    my $qr = $parts->[$i];
    my $st = $qr->structured;   # { index, total, parity, bytes }
    printf "part %d/%d parity=%02X (%d bytes) → version %d\n",
        $st->{index} + 1, $st->{total}, $st->{parity}, $st->{bytes}, $qr->version;
}
```

**Version / EC rule.** Every part is forced to the same version: the smallest version in `[min_version, max_version]` where the largest part (SA header + its data) fits at the requested EC level. If `boost` is on (the default), the EC level is then raised to the strongest level that still fits every part at that version. Slices are split over the UTF-8 octet sequence and encoded as byte segments.

You can also use the Reed-Solomon codec on its own:

```perl
use QRSmith::ReedSolomon qw(rs_encode rs_decode);
my $ecc = rs_encode(\@data, 10);                     # 10 check bytes
my ($fixed, $n) = rs_decode([@data, @$ecc], 10, \@known_bad_positions);
```

## How it works

| Module | Responsibility |
| --- | --- |
| `QRSmith::GF256` | Log and antilog tables for GF(2^8) with polynomial `0x11D`, plus polynomial helpers |
| `QRSmith::ReedSolomon` | Generator polynomials, systematic encoding, syndrome decoding with erasures |
| `QRSmith::BitBuffer` | Bit-level append and pack |
| `QRSmith::Segment` | Mode encoders (including Structured Append) and the optimal segmentation DP. Costs are kept in sixths of a bit so that numeric (10/3 bits per character) and alphanumeric (11/2) are exact. The DP runs once for each character-count-width group (versions 1 to 9, 10 to 26 and 27 to 40) |
| `QRSmith::Tables` | EC block tables and the capacity formulas for all versions |
| `QRSmith::Encoder` | Version and level choice, terminator and padding, the block split (short blocks first) and interleaving |
| `QRSmith::Matrix` | Function patterns, alignment positions, BCH(15,5) format and BCH(18,6) version bits, zigzag placement, masking and penalty scoring |
| `QRSmith::Render` | SVG, PNG, PBM and terminal output |
| `QRSmith::Payload` | Wi-Fi / vCard / mailto / SMS / geo / URL payload builders |

## Testing

```sh
prove -l t/
```

Encoded data codewords are compared against the ISO/IEC 18004 Annex I worked example ("01234567" at 1-M). The structure tests check every version for the expected size, function-pattern and data-module counts, and the BCH format and version words. The renderers' output is parsed back, and the CLI is run end to end. Payload helpers cover escaping edge cases and round-trip symbol builds; Structured Append checks parity consistency, reconstructable byte coverage and capacity that needs a split.

`t/09-decode.t` checks the output against an **independent decoder**. It renders PNGs and decodes them with [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp), or with OpenCV if zxing-cpp is missing. The cases cover every mask, every level, UTF-8 and ECI, and a near-capacity symbol for each of versions 1 to 40. The test is skipped when neither decoder is installed:

```sh
pip install zxing-cpp pillow
```

## License

MIT © 2026 Aryan Vohra
