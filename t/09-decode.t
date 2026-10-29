# Cross-check against an independent decoder (zxing-cpp, or OpenCV as a
# fallback) through t/tools/decode.py. Skipped when neither is installed:
#   pip install zxing-cpp pillow
use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use Encode qw(encode_utf8 decode_utf8);
use lib 'lib';
use QRSmith;
use QRSmith::Render qw(to_png);
use QRSmith::Encoder qw(plan_text);
use QRSmith::Tables qw(num_data_codewords);

my $have = system('python3 t/tools/decode.py --check >/dev/null 2>&1') == 0;
plan skip_all => 'no python3 QR decoder (zxing-cpp or OpenCV) available' unless $have;

my $dir = tempdir(CLEANUP => 1);
srand(1029);
my @alpha = ('a' .. 'z', 'A' .. 'Z', 0 .. 9, ' ', '/', ':', '.', '-');
my @cases;
push @cases, ['HELLO WORLD', ecl => $_] for qw(L M Q H);
push @cases, ['masked text', ecl => 'M', mask => $_] for 0 .. 7;
push @cases, ['3141592653589793238462643383279502884197', ecl => 'H'];
push @cases, ['Café ☕ naïve 日本語', ecl => 'Q'];
push @cases, ['INVOICE 0042 total 1234567890 USD, paid', ecl => 'L'];
push @cases, ['byte only 123 ABC', ecl => 'M', strategy => 'byte'];
push @cases, ['eci utf8 ✓', ecl => 'M', eci => 26];
for my $v (1 .. 40) {   # fill each version close to capacity at a random level
    my $l = (qw(L M Q H))[ rand 4 ];
    my $s = join '', map { $alpha[ rand @alpha ] } 1 .. 12 + int rand 30;
    my $text = $s;
    my $cap = num_data_codewords($v, $l);
    $text .= $s while length($text) < $cap;
    $text = substr $text, 0, $cap;
    my %o = (ecl => $l, min_version => $v, max_version => $v, boost => 0);
    chop $text until eval { plan_text($text, %o) };    # trim until it just fits
    push @cases, [$text, ecl => $l, min_version => $v, max_version => $v, boost => 0];
}

my @paths;
my @meta;
for my $i (0 .. $#cases) {
    my ($text, %opt) = @{ $cases[$i] };
    my $q = QRSmith->encode($text, %opt);
    my $scale = $q->version > 25 ? 3 : 4;
    my $p = "$dir/$i.png";
    open my $fh, '>:raw', $p or die $!;
    print {$fh} to_png($q, scale => $scale);
    close $fh;
    push @paths, $p;
    push @meta, sprintf 'v%d-%s mask %d', $q->version, $q->ecl, $q->mask;
}

open my $in, '-|', "printf '%s\\n' " . join(' ', @paths) . ' | python3 t/tools/decode.py' or die $!;
my @out = <$in>;
close $in;
chomp @out;
for my $i (0 .. $#cases) {
    my $want = $cases[$i][0];
    my $got = ($out[$i] // 'ERR') eq 'ERR' ? undef : decode_utf8(pack 'H*', $out[$i]);
    $got =~ s/\A\x{feff}// if defined $got;
    is($got, $want, "decodes $meta[$i]") or diag 'length ' . length $want;
}
done_testing;
