use strict;
use warnings;
use Test::More;
use Compress::Zlib ();
use lib 'lib';
use QRSmith;
use QRSmith::Render qw(to_svg to_png to_pbm to_terminal);

my $q = QRSmith->encode('render me', ecl => 'M');
my $n = $q->size;

my $svg = to_svg($q, scale => 5, dark => '#123456');
like($svg, qr/<svg[^>]+width="${\ (($n + 8) * 5)}"/, 'svg size includes quiet zone');
like($svg, qr/fill="#123456"/, 'svg dark colour');
# Reconstruct the modules from the SVG path and compare
my %dark;
while ($svg =~ /M(\d+),(\d+)h(\d+)v1/g) { $dark{"@{[$_]},$2"} = 1 for $1 .. $1 + $3 - 1 }
my $ok = 1;
for my $y (0 .. $n - 1) { for my $x (0 .. $n - 1) {
    $ok = 0 if !!$dark{ ($x + 4) . ',' . ($y + 4) } != !!$q->module($x, $y);
} }
ok($ok, 'svg path runs reproduce every module');
eval { to_svg($q, dark => 'red') }; like($@, qr/colour must/, 'colour validated');

my $png = to_png($q, scale => 3, quiet => 2);
is(substr($png, 0, 8), "\x89PNG\r\n\x1a\n", 'png signature');
my ($w, $h, $depth, $ctype) = unpack 'NNCC', substr($png, 16, 10);
is($w, ($n + 4) * 3, 'png width');
is($h, $w, 'png is square');
is("$depth/$ctype", '1/0', '1-bit greyscale');
# Walk chunks, verify CRCs, inflate IDAT and check the pixel under module (0,0)
my ($pos, $idat, $crc_ok) = (8, '', 1);
while ($pos < length $png) {
    my ($len, $type) = unpack 'Na4', substr($png, $pos, 8);
    my $data = substr($png, $pos + 8, $len);
    $crc_ok = 0 if unpack('N', substr($png, $pos + 8 + $len, 4)) != Compress::Zlib::crc32($type . $data);
    $idat .= $data if $type eq 'IDAT';
    $pos += 12 + $len;
}
ok($crc_ok, 'png chunk CRCs valid');
my $raw = Compress::Zlib::uncompress($idat);
my $stride = 1 + int(($w + 7) / 8);
is(length $raw, $stride * $h, 'decompressed scanlines');
my $row = unpack 'B*', substr($raw, $stride * 6, $stride);    # pixel row 6 = module row 0
is(substr($row, 8 + 6, 3), '000', 'finder corner is black');
is(substr($row, 8, 6), '111111', 'quiet zone is white');

my $pbm = to_pbm($q, quiet => 0);
like($pbm, qr/\AP1\n$n $n\n1 1 1 1 1 1 1 0/, 'pbm header and first row');

my $half = to_terminal($q, quiet => 1);
my @lines = split /\n/, $half;
is(scalar @lines, int(($n + 2 + 1) / 2), 'half-block output packs two rows per line');
like($lines[0], qr/\A \x{2584}{7}/, 'top edge uses lower half blocks');
my $ascii = to_terminal($q, style => 'ascii', quiet => 0);
is((split /\n/, $ascii)[0], $q->as_text(quiet => 0) =~ s/\n.*//sr, 'ascii matches as_text');
my $inv = to_terminal($q, style => 'ascii', quiet => 0, invert => 1);
isnt($inv, $ascii, 'invert changes output');
eval { to_terminal($q, style => 'braille') }; like($@, qr/unknown terminal style/, 'style validated');
done_testing;
