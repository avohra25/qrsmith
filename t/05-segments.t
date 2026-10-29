use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use QRSmith::Segment qw(make_numeric make_alphanumeric make_bytes make_eci
                        segments_for_text total_bits);

is(make_numeric('01234567')->data->as_string, '000000110001010110011000011', 'numeric packing (ISO example)');
is(make_alphanumeric('AC-42')->data->as_string, '0011100111011100111001000010', 'alphanumeric packing (ISO example)');
is(make_bytes("\x00\xFF")->data->as_string, '0000000011111111', 'byte packing');
is(make_eci(26)->data->as_string, '00011010', 'one-byte ECI');
is(make_eci(1000)->data->length, 16, 'two-byte ECI');
eval { make_numeric('12a') }; like($@, qr/only 0-9/, 'numeric validation');
eval { make_alphanumeric('abc') }; like($@, qr/alphanumeric/, 'alphanumeric validation');
eval { make_bytes("\x{263A}") }; like($@, qr/UTF-8/, 'byte segment needs bytes');

my $hw = segments_for_text('HELLO WORLD', strategy => 'auto');
is($hw->[0]->mode, 'alphanumeric', 'auto picks alphanumeric');
is(total_bits($hw, 1), 4 + 9 + 61, 'HELLO WORLD bit length');

my $u = segments_for_text('héllo ☺', strategy => 'auto');
is($u->[0]->mode, 'byte', 'non-ASCII falls back to bytes');
is($u->[0]->num_chars, 10, 'UTF-8 byte count');

my $mixed = 'ORDER 12345678901234567890 shipped';
my $opt = segments_for_text($mixed, strategy => 'optimal', version => 3);
is_deeply([ map { $_->mode } @$opt ], [qw(alphanumeric numeric byte)], 'optimal splits a mixed string');
cmp_ok(total_bits($opt, 3), '<', total_bits(segments_for_text($mixed, strategy => 'auto'), 3),
    'optimal beats single-mode');

# Optimal is never worse than any single-mode encoding
srand(7);
my @alphabet = (0 .. 9, 'A' .. 'Z', ' ', '$', 'a' .. 'f', '%', 'é');
my $ok = 1;
for (1 .. 300) {
    my $s = join '', map { $alphabet[ rand @alphabet ] } 1 .. 1 + int rand 40;
    for my $v (1, 10, 27) {
        my $o = segments_for_text($s, strategy => 'optimal', version => $v);
        my $a = segments_for_text($s, strategy => 'auto');
        my $b = segments_for_text($s, strategy => 'byte');
        $ok = 0 if total_bits($o, $v) > total_bits($a, $v) || total_bits($o, $v) > total_bits($b, $v);
    }
}
ok($ok, 'optimal segmentation is never longer than auto or byte mode');
is_deeply(segments_for_text(''), [], 'empty text has no segments');
done_testing;
