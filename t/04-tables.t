use strict;
use warnings;
use Test::More;
use lib 'lib';
use QRSmith::Tables qw(num_data_codewords num_raw_codewords raw_data_modules
                       alignment_positions symbol_size ec_codewords_per_block num_ec_blocks);

is(symbol_size(1), 21, 'version 1 is 21x21');
is(symbol_size(40), 177, 'version 40 is 177x177');
is(raw_data_modules(1), 208, 'v1 raw modules');
is(num_raw_codewords(40), 3706, 'v40 total codewords');
# Data capacities from ISO/IEC 18004 Table 7
my %cap = ('1L' => 19, '1M' => 16, '1Q' => 13, '1H' => 9, '5Q' => 62, '7H' => 66,
           '10M' => 216, '21L' => 932, '40L' => 2956, '40H' => 1276);
for my $k (sort keys %cap) {
    my ($v, $l) = $k =~ /(\d+)(.)/;
    is(num_data_codewords($v, $l), $cap{$k}, "data codewords $k");
}
my $ok = 1;
for my $v (1 .. 40) {
    for my $l (qw(L M Q H)) {
        my $raw = num_raw_codewords($v);
        my $nb  = num_ec_blocks($v, $l);
        my $short = int($raw / $nb) - ec_codewords_per_block($v, $l);
        $ok = 0 if $short < 1 || num_data_codewords($v, $l) < 1;
        $ok = 0 if $l ne 'L' && num_data_codewords($v, $l) >= num_data_codewords($v, 'L');
    }
}
ok($ok, 'every version/level has positive, decreasing capacity');
is_deeply([ alignment_positions(1) ], [], 'v1 has no alignment patterns');
is_deeply([ alignment_positions(7) ], [6, 22, 38], 'v7 alignment');
is_deeply([ alignment_positions(32) ], [6, 34, 60, 86, 112, 138], 'v32 special step');
is_deeply([ alignment_positions(40) ], [6, 30, 58, 86, 114, 142, 170], 'v40 alignment');
eval { symbol_size(41) };
like($@, qr/version must be/, 'version range checked');
eval { num_ec_blocks(1, 'X') };
like($@, qr/unknown error correction level/, 'level checked');
done_testing;
