use strict;
use warnings;
use utf8;
use Test::More;
use lib 'lib';
use QRSmith;
use QRSmith::Segment qw(make_structured_append total_bits);
use QRSmith::Encoder qw(data_codewords);
use QRSmith::Tables qw(num_data_codewords);

# --- low-level SA segment ---
my $sa = make_structured_append(0, 4, 0xA5);
is($sa->mode, 'structured_append', 'SA mode name');
is($sa->mode_indicator, 0x3, 'SA mode indicator 0011');
is($sa->num_chars, 0, 'SA has no char count');
is($sa->data->length, 16, 'SA header is 16 bits');
is($sa->data->as_string, '0000001110100101', 'SA bits: idx=0, total-1=3, parity=0xA5');
# index 3 of 4, parity 0
my $sa2 = make_structured_append(3, 4, 0);
is($sa2->data->as_string, '0011001100000000', 'SA bits: idx=3, total-1=3, parity=0');
eval { make_structured_append(4, 4, 0) }; like($@, qr/less than total/, 'index < total');
eval { make_structured_append(0, 1, 0) }; like($@, qr/2\.\.16/, 'total >= 2');
eval { make_structured_append(0, 17, 0) }; like($@, qr/2\.\.16/, 'total <= 16');

# --- encode_structured basics ---
my $text = 'Hello, Structured Append!';
my $parts = QRSmith->encode_structured($text, parts => 3, ecl => 'M', boost => 0);
is(ref $parts, 'ARRAY', 'returns arrayref');
is(scalar @$parts, 3, 'three symbols');

my $parity = 0;
{ my $b = $text; utf8::encode($b) if utf8::is_utf8($b); $parity ^= ord for split //, $b }

my $byte_sum = 0;
my $version;
for my $i (0 .. 2) {
    my $qr = $parts->[$i];
    isa_ok($qr, 'QRSmith');
    my $st = $qr->structured;
    ok($st, "part $i has structured metadata");
    is($st->{index}, $i, "part $i index");
    is($st->{total}, 3, "part $i total");
    is($st->{parity}, $parity, "part $i parity matches ISO XOR");
    $byte_sum += $st->{bytes};
    $version //= $qr->version;
    is($qr->version, $version, "part $i shares version $version");
    is($qr->ecl, 'M', "part $i ecl M");
    ok($qr->size == 4 * $qr->version + 17, "part $i size sanity");
    ok($qr->mask =~ /^[0-7]$/, "part $i mask sanity");

    my $segs = $qr->segments;
    is($segs->[0]{mode}, 'structured_append', "part $i leads with SA segment");
    # Peek at the raw SA header bits via the plan
    my $raw = $qr->{plan}{segments}[0];
    my $bits = $raw->data->as_string;
    my $idx_bits = substr($bits, 0, 4);
    my $tot_bits = substr($bits, 4, 4);
    my $par_bits = substr($bits, 8, 8);
    is(oct('0b' . $idx_bits), $i, "part $i header index bits");
    is(oct('0b' . $tot_bits), 2, "part $i header total-1 bits");
    is(oct('0b' . $par_bits), $parity, "part $i header parity bits");
}
is($byte_sum, length $text, 'byte coverage reconstructs the full payload');

# Parity consistency across all parts (already checked equal to $parity)
is($parts->[0]->structured->{parity}, $parts->[1]->structured->{parity}, 'parity 0==1');
is($parts->[1]->structured->{parity}, $parts->[2]->structured->{parity}, 'parity 1==2');

# --- capacity: too big for one symbol at max_version=1, but fine when split ---
my $big = 'X' x 40;    # 40 bytes; version 1-M holds 14 byte-mode bytes
eval { QRSmith->encode($big, ecl => 'M', boost => 0, max_version => 1, strategy => 'byte') };
like($@, qr/does not fit/, '40 bytes do not fit in a single version-1 symbol');
my $split = QRSmith->encode_structured($big, parts => 4, ecl => 'M', boost => 0, max_version => 1);
is(scalar @$split, 4, '40 bytes fit across 4 version-1 symbols');
is($split->[0]->version, 1, 'split uses version 1');
my $cov = 0; $cov += $_->structured->{bytes} for @$split;
is($cov, 40, 'split covers all 40 bytes');
# each part should have ~10 bytes + SA; confirm they encode
ok($_->size == 21, 'each part is 21x21') for @$split;

# --- empty-ish / short text still produces N symbols ---
my $short = QRSmith->encode_structured('ab', parts => 2, ecl => 'L', boost => 0);
is(scalar @$short, 2, 'short text still yields N symbols');
is($short->[0]->structured->{bytes} + $short->[1]->structured->{bytes}, 2, 'short coverage');

# --- UTF-8 parity is over encoded octets (codepoints > 255 force UTF-8) ---
my $uni = "cafe\x{263A}";  # cafe + WHITE SMILING FACE
my $ub = $uni; utf8::encode($ub);
my $up = 0; $up ^= ord for split //, $ub;
is(length $ub, 7, 'emoji expands to 3 UTF-8 bytes (sanity)');
my $uq = QRSmith->encode_structured($uni, parts => 2, boost => 0);
is($uq->[0]->structured->{parity}, $up, 'UTF-8 parity over octets');
is($uq->[0]->structured->{bytes} + $uq->[1]->structured->{bytes}, length $ub, 'UTF-8 byte coverage');

# --- boost raises ecl consistently ---
my $boosted = QRSmith->encode_structured('hi', parts => 2, ecl => 'L');
is($boosted->[0]->ecl, $boosted->[1]->ecl, 'boosted ecl matches across parts');
ok(QRSmith::Tables::ecl_index($boosted->[0]->ecl) >= QRSmith::Tables::ecl_index('L'),
   'boost does not lower ecl');

# --- validation ---
eval { QRSmith->encode_structured('x', parts => 1) }; like($@, qr/2\.\.16/, 'parts=1 rejected');
eval { QRSmith->encode_structured('x') }; like($@, qr/parts/, 'parts required');
eval { QRSmith->encode_structured('x' x 5000, parts => 2, max_version => 5, ecl => 'H', boost => 0) };
like($@, qr/does not fit/, 'oversize structured rejected');

# Ordinary encode has no structured metadata
ok(!defined QRSmith->encode('plain')->structured, 'plain encode has no SA meta');

# data_codewords includes the 20-bit SA header without blowing up
my $plan = $parts->[0]{plan};
my $cw = data_codewords($plan);
is(scalar @$cw, num_data_codewords($plan->{version}, $plan->{ecl}),
   'SA symbol produces a full data-codeword block');

done_testing;
