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
# --- payload helpers & structured append (v0.2.0) ---
my $wifi = `$bin --wifi 'a;b' --password 'p,q' -f ascii --quiet 0 2>&1`;
is($?, 0, '--wifi exit 0');
like($wifi, qr/\A#{14}/, '--wifi produces a symbol');

my $mail = `$bin --mailto 'a\@b.co' --subject 'Hi there' -f ascii --quiet 0 2>&1`;
is($?, 0, '--mailto exit 0');

my $sms = `$bin --sms 5550100 --body hello -f ascii --quiet 0 2>&1`;
is($?, 0, '--sms exit 0');

my $geo = `$bin --geo 1.5,-2.5 --geo-query 'spot' -f ascii --quiet 0 2>&1`;
is($?, 0, '--geo exit 0');

my $vc = `$bin --vcard-name 'Test User' --vcard-email t\@ex.com -f ascii --quiet 0 2>&1`;
is($?, 0, '--vcard-name exit 0');

my $bad = `$bin --wifi x --mailto y 2>&1`;
isnt($?, 0, 'two payload helpers rejected');
like($bad, qr/at most one/, 'mutual exclusion message');

my $pinfo = `$bin --parts 3 --info -f ascii --quiet 0 'ABCDEFGHIJKLMNOP' 2>&1 >/dev/null`;
like($pinfo, qr/part 1\/3 version \d+/, '--parts --info shows part 1');
like($pinfo, qr/part 3\/3/, '--parts --info shows part 3');
like($pinfo, qr/SA 1\/3 parity=0x[0-9A-Fa-f]+/, '--parts --info shows SA meta');

`$bin --parts 2 -o $dir/chunk.svg 'split payload please'`;
ok(-s "$dir/chunk-01.svg", 'structured out-01.svg written');
ok(-s "$dir/chunk-02.svg", 'structured out-02.svg written');
ok(!-e "$dir/chunk.svg", 'base -o name is not left behind when split');

my $badp = `$bin --parts 1 hi 2>&1`;
isnt($?, 0, '--parts 1 rejected');
like($badp, qr/2\.\.16/, '--parts range message');

done_testing;
