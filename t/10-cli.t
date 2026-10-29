use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

my $bin = "$^X bin/qrsmith";
my $dir = tempdir(CLEANUP => 1);

my $out = `$bin --format ascii --quiet 0 HELLO WORLD 2>&1`;
is($?, 0, 'exit status 0');
like($out, qr/\A#{14}/, 'ascii output starts with the finder row');

my $info = `$bin --info -e H -f ascii 'ORDER 12345678901234567890 shipped' 2>&1 >/dev/null`;
like($info, qr/version \d+ \(\d+x\d+\), level H, mask \d, segments: alphanumeric\(6\), numeric\(20\), byte\(8\)/,
    '--info reports the plan');

`echo 'from stdin' | $bin -o $dir/a.svg`;
ok(-s "$dir/a.svg", 'svg written from stdin');
open my $fh, '<', "$dir/a.svg" or die; my $svg = do { local $/; <$fh> };
like($svg, qr/<svg/, 'format inferred from extension');

`$bin -s 2 -o $dir/b.png https://example.com`;
open $fh, '<:raw', "$dir/b.png" or die; read $fh, my $sig, 8;
is($sig, "\x89PNG\r\n\x1a\n", 'png written');

my $err = `$bin -e Z hi 2>&1`;
isnt($?, 0, 'bad level fails');
like($err, qr/unknown error correction level/, 'error message');
$err = `$bin --max-version 1 -e H 'this is far too long for a version one symbol' 2>&1`;
like($err, qr/does not fit/, 'capacity error');
like(`$bin -h`, qr/Usage: qrsmith/, 'help');
my $m3 = `$bin -f ascii -m 3 --info x 2>&1`;
like($m3, qr/mask 3/, 'forced mask');
done_testing;
