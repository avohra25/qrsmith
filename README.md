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
```

```sh
qrsmith -e H -s 10 --dark '#1a1a2e' -o examples/hello.svg https://github.com/avohra25/qrsmith
qrsmith -s 6 -o examples/hello.png https://github.com/avohra25/qrsmith
echo 'WIFI:T:WPA;S:home;P:hunter22;;' | qrsmith        # scan to join Wi-Fi
```

## Library

```perl
use QRSmith;
use QRSmith::Render qw(to_svg to_png to_terminal);

my $qr = QRSmith->encode('https://example.com', ecl => 'M');
printf "%d-%s mask %d, %dx%d\n", $qr->version, $qr->ecl, $qr->mask, $qr->size, $qr->size;
$qr->module($x, $y);          # 1 = dark
$qr->rows;                    # arrayref of rows of 0/1
$qr->segments;                # [{ mode => 'byte', chars => 19 }]

open my $fh, '>:raw', 'qr.png' or die; print {$fh} to_png($qr, scale => 6);
print to_svg($qr, scale => 8, quiet => 4, dark => '#000', light => '#fff');
```

`encode` takes these options: `ecl`, `strategy` (`optimal`, `auto`, `byte`), `min_version`, `max_version`, `mask`, `boost` and `eci`. If the text cannot fit, it dies with a "does not fit" message. To control the segments yourself, build them with `QRSmith::Segment` (`make_numeric`, `make_alphanumeric`, `make_bytes`, `make_eci`) and pass them to `QRSmith->encode_segments(\@segs, %opt)`.

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
| `QRSmith::Segment` | Mode encoders and the optimal segmentation DP. Costs are kept in sixths of a bit so that numeric (10/3 bits per character) and alphanumeric (11/2) are exact. The DP runs once for each character-count-width group (versions 1 to 9, 10 to 26 and 27 to 40) |
| `QRSmith::Tables` | EC block tables and the capacity formulas for all versions |
| `QRSmith::Encoder` | Version and level choice, terminator and padding, the block split (short blocks first) and interleaving |
| `QRSmith::Matrix` | Function patterns, alignment positions, BCH(15,5) format and BCH(18,6) version bits, zigzag placement, masking and penalty scoring |
| `QRSmith::Render` | SVG, PNG, PBM and terminal output |

## Testing

```sh
prove -l t/
```

There are 192 tests. They cover the GF(256) field axioms and Reed-Solomon round trips with random errors and erasures. Encoded data codewords are compared against the ISO/IEC 18004 Annex I worked example ("01234567" at 1-M). The structure tests check every version for the expected size, function-pattern and data-module counts, and the BCH format and version words. The renderers' output is parsed back, and the CLI is run end to end.

`t/09-decode.t` checks the output against an **independent decoder**. It renders PNGs and decodes them with [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp), or with OpenCV if zxing-cpp is missing. The cases cover every mask, every level, UTF-8 and ECI, and a near-capacity symbol for each of versions 1 to 40. The test is skipped when neither decoder is installed:

```sh
pip install zxing-cpp pillow
```

## License

MIT © 2026 Aryan Vohra
