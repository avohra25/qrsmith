package QRSmith::Render;
# Output formats for a QRSmith symbol: SVG, PNG, PBM, and terminal art.
# Every renderer adds a quiet zone (default 4 modules, as the standard asks).
use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak);
use Compress::Zlib ();

our @EXPORT_OK = qw(to_svg to_png to_pbm to_terminal);

sub _grid {
    my ($qr, $quiet) = @_;
    $quiet //= 4;
    croak 'quiet zone must be a non-negative integer' unless $quiet =~ /^\d+$/;
    my $n = $qr->size;
    my $t = $n + 2 * $quiet;
    my @g = map { [ (0) x $t ] } 1 .. $t;
    for my $y (0 .. $n - 1) {
        for my $x (0 .. $n - 1) { $g[ $y + $quiet ][ $x + $quiet ] = $qr->module($x, $y) }
    }
    return (\@g, $t);
}

sub _colour {
    my ($c, $default) = @_;
    $c //= $default;
    croak "colour must look like #rgb or #rrggbb, got '$c'" unless $c =~ /^#(?:[0-9a-fA-F]{3}){1,2}$/;
    return $c;
}

# One <path> with a horizontal run per row of dark modules; scales cleanly.
sub to_svg {
    my ($qr, %o) = @_;
    my ($g, $t) = _grid($qr, $o{quiet});
    my $scale = $o{scale} // 8;
    croak 'scale must be a positive integer' unless $scale =~ /^\d+$/ && $scale > 0;
    my $fg = _colour($o{dark}, '#000000');
    my $bg = _colour($o{light}, '#ffffff');
    my @d;
    for my $y (0 .. $t - 1) {
        my $x = 0;
        while ($x < $t) {
            if (!$g->[$y][$x]) { $x++; next }
            my $start = $x;
            $x++ while $x < $t && $g->[$y][$x];
            push @d, "M$start,${y}h" . ($x - $start) . 'v1h-' . ($x - $start) . 'z';
        }
    }
    my $px = $t * $scale;
    return qq{<?xml version="1.0" encoding="UTF-8"?>\n}
         . qq{<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="$px" height="$px" }
         . qq{viewBox="0 0 $t $t" shape-rendering="crispEdges">\n}
         . qq{<rect width="100%" height="100%" fill="$bg"/>\n}
         . qq{<path fill="$fg" d="} . join('', @d) . qq{"/>\n</svg>\n};
}

sub _chunk {
    my ($type, $data) = @_;
    return pack('N', length $data) . $type . $data . pack('N', Compress::Zlib::crc32($type . $data));
}

# 1-bit greyscale PNG.
sub to_png {
    my ($qr, %o) = @_;
    my ($g, $t) = _grid($qr, $o{quiet});
    my $scale = $o{scale} // 8;
    croak 'scale must be a positive integer' unless $scale =~ /^\d+$/ && $scale > 0;
    my $px = $t * $scale;
    my $raw = '';
    for my $y (0 .. $t - 1) {
        my $bits = join '', map { ($g->[$y][$_] ? '0' : '1') x $scale } 0 .. $t - 1;   # 1 = white
        my $row = "\0" . pack('B*', $bits);
        $raw .= $row x $scale;
    }
    return "\x89PNG\r\n\x1a\n"
         . _chunk('IHDR', pack('NNCCCCC', $px, $px, 1, 0, 0, 0, 0))
         . _chunk('IDAT', Compress::Zlib::compress($raw, 9))
         . _chunk('IEND', '');
}

# Plain PBM (P1), handy for piping into other tools.
sub to_pbm {
    my ($qr, %o) = @_;
    my ($g, $t) = _grid($qr, $o{quiet});
    return "P1\n$t $t\n" . join('', map { join(' ', @$_) . "\n" } @$g);
}

# Terminal output. 'half' packs two rows per line with Unicode half blocks
# (light-on-dark terminals invert with invert => 1); 'ascii' uses ## and spaces.
sub to_terminal {
    my ($qr, %o) = @_;
    my $style = $o{style} // 'half';
    my ($g, $t) = _grid($qr, $o{quiet} // 2);
    my $inv = $o{invert} ? 1 : 0;
    my @out;
    if ($style eq 'ascii') {
        for my $row (@$g) { push @out, join '', map { ($_ ^ $inv) ? '##' : '  ' } @$row }
    }
    elsif ($style eq 'half') {
        my %ch = ('00' => ' ', '10' => "\x{2580}", '01' => "\x{2584}", '11' => "\x{2588}");
        for (my $y = 0; $y < $t; $y += 2) {
            push @out, join '', map {
                my $top = $g->[$y][$_] ^ $inv;
                my $bot = ($y + 1 < $t ? $g->[ $y + 1 ][$_] : 0) ^ $inv;
                $ch{"$top$bot"};
            } 0 .. $t - 1;
        }
    }
    else { croak "unknown terminal style '$style' (use half or ascii)" }
    return join("\n", @out) . "\n";
}

1;
