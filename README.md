# qrsmith

A pure-Perl QR Code encoder, built from the ground up with no CPAN dependencies.

```perl
use QRSmith;
my $qr = QRSmith->encode('HELLO WORLD', ecl => 'Q');
print $qr->as_text;                 # '##' for dark modules, with a quiet zone
printf "version %d-%s, mask %d\n", $qr->version, $qr->ecl, $qr->mask;
```

Implemented so far:

- `QRSmith::GF256` and `QRSmith::ReedSolomon`: GF(2^8) arithmetic and a
  Reed-Solomon encoder plus full errors-and-erasures decoder.
- `QRSmith::Segment`: numeric, alphanumeric, byte and ECI segments, and an
  optimal mode-switching planner.
- `QRSmith::Tables` and `QRSmith::Encoder`: all 40 versions and 4 EC levels,
  version selection with free EC-level boosting, padding, block interleaving.
- `QRSmith::Matrix`: finder/timing/alignment patterns, BCH-coded format and
  version information, zigzag data placement, the eight masks and ISO penalty
  scoring for automatic mask choice.

```sh
prove -l t/
```

MIT licensed.
