use strict;
use warnings;
use Test::More;
use lib 'lib';
use QRSmith::ReedSolomon qw(rs_generator rs_encode rs_syndromes rs_decode);
use QRSmith::GF256 qw(poly_eval gf_exp);

# Generator for 10 EC codewords, in alpha exponent form from ISO/IEC 18004
# Annex A: 0 251 67 46 61 118 70 64 94 32 45
my @exps = map { $_ == 0 ? 0 : QRSmith::GF256::gf_log($_) } @{ rs_generator(10) };
is_deeply(\@exps, [0, 251, 67, 46, 61, 118, 70, 64, 94, 32, 45], 'degree-10 generator');
is(poly_eval(rs_generator(7), gf_exp($_)), 0, "alpha^$_ is a root of g7") for 0 .. 6;

# "HELLO WORLD" version 1-Q data codewords and their 13 EC codewords
my @data = (32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236);
is_deeply(rs_encode(\@data, 13),
    [168, 72, 22, 82, 217, 54, 156, 0, 46, 15, 180, 122, 16],
    'known 1-Q codeword');

# Version 1-M "01234567"
is_deeply(rs_encode([16, 32, 12, 86, 97, 128, 236, 17, 236, 17, 236, 17, 236, 17, 236, 17], 10),
    [165, 36, 212, 193, 237, 54, 199, 135, 44, 85],
    'known 1-M codeword');

my $cw = [ @data, @{ rs_encode(\@data, 13) } ];
ok(!(grep { $_ } @{ rs_syndromes($cw, 13) }), 'valid codeword has zero syndromes');
my ($same, $nfix) = rs_decode($cw, 13);
is_deeply($same, $cw, 'clean codeword decodes unchanged');
is($nfix, 0, 'no corrections on clean input');

srand(20261029);
my ($trials, $good) = (0, 0);
for my $round (1 .. 300) {
    my $k = 1 + int rand 60;
    my $n = 2 + int rand 30;
    my @d = map { int rand 256 } 1 .. $k;
    my @c = (@d, @{ rs_encode(\@d, $n) });
    my $t = int($n / 2);
    my $ne = int rand($t + 1);
    my %where;
    $where{ int rand @c } = 1 while keys %where < $ne;
    my @bad = @c;
    $bad[$_] ^= 1 + int rand 255 for keys %where;
    $trials++;
    my ($fixed, $count) = eval { rs_decode(\@bad, $n) };
    $good++ if $fixed && "@$fixed" eq "@c" && $count == $ne;
}
is($good, $trials, "corrected random errors up to n/2 in all $trials trials");

# Erasures: with known positions we can fix up to n corrupted bytes.
my ($etrials, $egood) = (0, 0);
for my $round (1 .. 200) {
    my $k = 1 + int rand 40;
    my $n = 4 + int rand 20;
    my @d = map { int rand 256 } 1 .. $k;
    my @c = (@d, @{ rs_encode(\@d, $n) });
    my $f = int rand($n + 1);                  # erasures
    my $e = int(($n - $f) / 2 * rand);         # plus unknown errors, 2e + f <= n
    my %where;
    $where{ int rand @c } = 1 while keys %where < $f + $e;
    my @all = keys %where;
    my @eras = @all[ 0 .. $f - 1 ];
    my @bad = @c;
    $bad[$_] ^= 1 + int rand 255 for @all;
    $etrials++;
    my ($fixed) = eval { rs_decode(\@bad, $n, \@eras) };
    $egood++ if $fixed && "@$fixed" eq "@c";
}
is($egood, $etrials, "corrected erasures+errors with 2e+f <= n in all $etrials trials");

# Too many errors must be reported, never silently "corrected" to garbage
my $detected = 0;
for my $round (1 .. 200) {
    my @d = map { int rand 256 } 1 .. 20;
    my @c = (@d, @{ rs_encode(\@d, 10) });
    my @bad = @c;
    $bad[$_] ^= 1 + int rand 255 for 0 .. 7;    # 8 errors > capacity 5
    my ($fixed) = eval { rs_decode(\@bad, 10) };
    $detected++ if !$fixed || "@$fixed" ne "@c";
}
is($detected, 200, 'over-capacity corruption never decodes to the original');
eval { rs_encode([ (0) x 250 ], 10) };
like($@, qr/too long/, 'codeword length limit enforced');
done_testing;
