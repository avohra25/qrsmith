use strict;
use warnings;
use Test::More;
use lib 'lib';
use QRSmith;
use QRSmith::Matrix;
use QRSmith::Tables qw(raw_data_modules);

# Format information values from ISO/IEC 18004 Annex C
is(sprintf('%015b', QRSmith::Matrix::format_bits('M', 5)), '100000011001110', 'format M/5');
is(sprintf('%015b', QRSmith::Matrix::format_bits('L', 4)), '110011000101111', 'format L/4');
is(sprintf('%015b', QRSmith::Matrix::format_bits('H', 7)), '000100000111011', 'format H/7');
# Version information from Annex D
is(sprintf('%018b', QRSmith::Matrix::version_bits(7)),  '000111110010010100', 'version 7 bits');
is(sprintf('%018b', QRSmith::Matrix::version_bits(40)), '101000110001101001', 'version 40 bits');

# All 32 format words are distinct with pairwise Hamming distance >= 7 (BCH)
my @f = map { my $e = $_; map { QRSmith::Matrix::format_bits($e, $_) } 0 .. 7 } qw(L M Q H);
my $min = 99;
for my $i (0 .. $#f) { for my $j ($i + 1 .. $#f) {
    my $d = unpack '%32b*', pack 'N', $f[$i] ^ $f[$j];
    $min = $d if $d < $min;
} }
cmp_ok($min, '>=', 7, 'format codes have minimum distance 7');

# The count of non-function modules equals the raw capacity for every version
my $ok = 1;
for my $v (1 .. 40) {
    my $m = QRSmith::Matrix->new(version => $v);
    my $free = 0;
    for my $y (0 .. $m->size - 1) { for my $x (0 .. $m->size - 1) { $free++ unless $m->is_function($x, $y) } }
    $ok = 0 if $free != raw_data_modules($v);
}
ok($ok, 'free modules match raw_data_modules for versions 1-40');

my $q = QRSmith->encode('HELLO WORLD', ecl => 'Q', mask => 6);
is($q->size, 21, 'symbol size');
is($q->mask, 6, 'explicit mask used');
# Finder pattern corners and the dark module
is($q->module(0, 0), 1, 'top-left finder corner dark');
is($q->module(7, 7), 0, 'separator light');
is($q->module(8, $q->size - 8), 1, 'dark module set');
is(join('', map { $q->module($_, 6) } 8 .. 12), '10101', 'timing pattern alternates');

my $auto = QRSmith->encode('https://github.com/avohra25/qrsmith');
my @pen;
for my $m (0 .. 7) {
    push @pen, QRSmith->encode('https://github.com/avohra25/qrsmith', mask => $m)->{matrix}->penalty;
}
my ($minpen) = sort { $a <=> $b } @pen;
is($auto->{matrix}->penalty, $minpen, 'automatic mask has the lowest penalty');

# Masking twice is the identity
my $m = QRSmith::Matrix->new(version => 3);
$m->place_codewords([ map { $_ * 37 % 256 } 1 .. 70 ]);
my $before = $m->rows;
$m->apply_mask(4); $m->apply_mask(4);
is_deeply($m->rows, $before, 'mask is an involution');

like($q->as_text(quiet => 1, dark => '#', light => '.'), qr/^\.{23}\n\.#######\./, 'text rendering');
eval { QRSmith->encode('x', mask => 9) }; like($@, qr/mask must be/, 'bad mask rejected');
eval { QRSmith->encode('x', colour => 1) }; like($@, qr/unknown option/, 'unknown option rejected');
done_testing;
