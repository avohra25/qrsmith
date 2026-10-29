use strict;
use warnings;
use Test::More;
use lib 'lib';
use QRSmith::GF256 qw(gf_mul gf_div gf_inv gf_pow gf_exp gf_log poly_eval poly_mul poly_add);

is(gf_exp(0), 1, 'alpha^0 = 1');
is(gf_exp(8), 0x1D, 'alpha^8 reduces by 0x11D');
is(gf_exp(255), 1, 'multiplicative order is 255');
my %seen;
$seen{ gf_exp($_) }++ for 0 .. 254;
is(scalar keys %seen, 255, 'alpha generates every non-zero element');

# Carry-less reference multiplication modulo 0x11D
sub slow_mul {
    my ($a, $b) = @_;
    my $r = 0;
    while ($b) {
        $r ^= $a if $b & 1;
        $a <<= 1;
        $a ^= 0x11D if $a & 0x100;
        $b >>= 1;
    }
    return $r;
}

my $ok = 1;
for my $a (0 .. 255) {
    for my $b (0 .. 255) {
        $ok = 0, last if gf_mul($a, $b) != slow_mul($a, $b);
    }
}
ok($ok, 'table multiplication matches shift-and-add for all 65536 pairs');

my $inv_ok = 1;
for my $a (1 .. 255) {
    $inv_ok = 0 unless gf_mul($a, gf_inv($a)) == 1;
    $inv_ok = 0 unless gf_log(gf_exp(gf_log($a))) == gf_log($a);
    for my $b (1, 7, 200) {
        $inv_ok = 0 unless gf_mul(gf_div($a, $b), $b) == $a;
    }
}
ok($inv_ok, 'inverse and division are consistent');
is(gf_pow(3, 0), 1, 'x^0 = 1');
is(gf_pow(2, 300), gf_exp(45), 'exponents wrap mod 255');
is(gf_pow(5, -1), gf_inv(5), 'negative exponent is inverse');
eval { gf_div(3, 0) };
like($@, qr/division by zero/, 'division by zero croaks');

# (x + 1)(x + 2) = x^2 + 3x + 2
is_deeply(poly_mul([1, 1], [1, 2]), [1, 3, 2], 'poly_mul');
is_deeply(poly_add([1, 0, 5], [3, 4]), [1, 3, 1], 'poly_add aligns low degrees');
is(poly_eval([1, 3, 2], 2), 0, 'root of (x+1)(x+2)');
done_testing;
