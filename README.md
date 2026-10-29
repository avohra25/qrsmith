# qrsmith

A pure-Perl QR Code encoder, built from the ground up with no CPAN dependencies.

Work in progress. This first piece is the error-correction core:

- `QRSmith::GF256`: arithmetic in GF(2^8) with the QR field polynomial `0x11D`
  (log/antilog tables, polynomial helpers).
- `QRSmith::ReedSolomon`: systematic Reed-Solomon encoding plus a full decoder
  (syndromes, Berlekamp-Massey, Chien search, Forney) that corrects up to
  `n/2` byte errors, or more when erasure positions are known (`2e + f <= n`).
- `QRSmith::BitBuffer`: MSB-first bit packing.

```sh
prove -l t/
```

MIT licensed.
