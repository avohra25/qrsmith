use strict;
use warnings;
use Test::More;
use lib 'lib';
use QRSmith::Encoder qw(plan_text plan_segments data_codewords split_blocks interleave);
use QRSmith::ReedSolomon qw(rs_syndromes);
use QRSmith::Tables qw(num_raw_codewords);

my $p = plan_text('HELLO WORLD', ecl => 'Q', boost => 0);
is($p->{version}, 1, 'HELLO WORLD fits version 1-Q');
is_deeply(data_codewords($p), [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236],
    'HELLO WORLD 1-Q data codewords');
my $blocks = split_blocks(data_codewords($p), 1, 'Q');
is_deeply($blocks->[0][1], [168, 72, 22, 82, 217, 54, 156, 0, 46, 15, 180, 122, 16], 'and its EC codewords');

my $n = plan_text('01234567', ecl => 'M', boost => 0);
is_deeply(data_codewords($n), [16, 32, 12, 86, 97, 128, 236, 17, 236, 17, 236, 17, 236, 17, 236, 17],
    '01234567 1-M data codewords (ISO Annex I)');

is(plan_text('HELLO WORLD', ecl => 'L')->{ecl}, 'Q', 'boost raises the level when free');
is(plan_text('A' x 90, ecl => 'M', boost => 0)->{version}, 4, '90 alphanumerics fit version 4-M');
is(plan_text('A' x 91, ecl => 'M', boost => 0)->{version}, 5, '91 need version 5-M');
is(plan_text('A', min_version => 5)->{version}, 5, 'min_version respected');
eval { plan_text('x' x 3000, ecl => 'H') };
like($@, qr/does not fit/, 'oversize input rejected');
eval { plan_text('x' x 200, ecl => 'H', max_version => 5) };
like($@, qr/does not fit/, 'max_version respected');

# Capacity edge: 2953 bytes is the most a symbol holds (40-L)
is(plan_text('x' x 2953, ecl => 'L', strategy => 'byte')->{version}, 40, 'maximum byte capacity');
eval { plan_text('x' x 2954, ecl => 'L', strategy => 'byte') };
like($@, qr/does not fit/, 'one byte over maximum');
is(plan_text('7' x 7089, ecl => 'L')->{version}, 40, 'maximum numeric capacity');

# Interleaving: every block is a valid RS codeword and the total length is right
my $ok = 1;
for my $v (1, 5, 9, 10, 20, 26, 27, 33, 40) {
    for my $l (qw(L M Q H)) {
        my $plan = plan_text('QR' x (3 * $v), ecl => $l, min_version => $v, max_version => $v, boost => 0);
        my $bl = split_blocks(data_codewords($plan), $v, $l);
        for my $b (@$bl) {
            my $cw = [ @{ $b->[0] }, @{ $b->[1] } ];
            $ok = 0 if grep { $_ } @{ rs_syndromes($cw, scalar @{ $b->[1] }) };
        }
        $ok = 0 if @{ interleave($bl) } != num_raw_codewords($v);
        $ok = 0 if @{ $bl->[0][0] } > @{ $bl->[-1][0] };
    }
}
ok($ok, 'blocks are valid RS codewords; interleaved length equals raw capacity');
is_deeply(interleave([ [ [1, 2], [9] ], [ [3, 4, 5], [8] ] ]), [1, 3, 2, 4, 5, 9, 8], 'interleave order');
done_testing;
