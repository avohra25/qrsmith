# qrsmith

A pure-Perl QR Code encoder, built from the ground up with no CPAN dependencies.

Work in progress. Implemented so far:

- `QRSmith::GF256`: arithmetic in GF(2^8) with the QR field polynomial `0x11D`.
- `QRSmith::ReedSolomon`: systematic Reed-Solomon encoding plus a full decoder
  (syndromes, Berlekamp-Massey, Chien search, Forney) that corrects up to
  `n/2` byte errors, or more when erasure positions are known (`2e + f <= n`).
- `QRSmith::Segment`: numeric, alphanumeric, byte and ECI segments, and an
  optimal mode-switching planner (dynamic programming over characters).
- `QRSmith::Tables`: capacity tables for all 40 versions and 4 EC levels,
  alignment pattern positions.
- `QRSmith::Encoder`: version selection with free EC-level boosting,
  terminator/padding, block split and interleaving.

```sh
prove -l t/
```

MIT licensed.
