package QRSmith::Matrix;
# Module placement: finder, separator, timing and alignment patterns,
# format and version information (BCH coded), the zigzag data path, the
# eight data masks and the ISO penalty rules used to choose between them.
use strict;
use warnings;
use Carp qw(croak);
use QRSmith::Tables qw(symbol_size alignment_positions ecl_format_bits);

use constant { N1 => 3, N2 => 3, N3 => 40, N4 => 10 };

my @MASKS = (
    sub { ($_[0] + $_[1]) % 2 == 0 },
    sub { $_[1] % 2 == 0 },
    sub { $_[0] % 3 == 0 },
    sub { ($_[0] + $_[1]) % 3 == 0 },
    sub { (int($_[0] / 3) + int($_[1] / 2)) % 2 == 0 },
    sub { ($_[0] * $_[1]) % 2 + ($_[0] * $_[1]) % 3 == 0 },
    sub { (($_[0] * $_[1]) % 2 + ($_[0] * $_[1]) % 3) % 2 == 0 },
    sub { (($_[0] + $_[1]) % 2 + ($_[0] * $_[1]) % 3) % 2 == 0 },
);

sub mask_function { $MASKS[ $_[0] ] }

# 15-bit format information: 2 bits level, 3 bits mask, BCH(15,5), XOR 0x5412.
sub format_bits {
    my ($ecl, $mask) = @_;
    my $data = (ecl_format_bits($ecl) << 3) | $mask;
    my $rem = $data;
    $rem = ($rem << 1) ^ (($rem >> 9) * 0x537) for 1 .. 10;
    return (($data << 10) | $rem) ^ 0x5412;
}

# 18-bit version information for versions >= 7: BCH(18,6).
sub version_bits {
    my ($v) = @_;
    my $rem = $v;
    $rem = ($rem << 1) ^ (($rem >> 11) * 0x1F25) for 1 .. 12;
    return ($v << 12) | $rem;
}

sub new {
    my ($class, %a) = @_;
    my $v = $a{version} // croak 'version required';
    my $size = symbol_size($v);
    my $self = bless {
        version => $v,
        ecl     => $a{ecl} // 'M',
        size    => $size,
        mod     => [ map { [ (0) x $size ] } 1 .. $size ],   # [y][x], 1 = dark
        func    => [ map { [ (0) x $size ] } 1 .. $size ],
    }, $class;
    $self->_draw_function_patterns;
    return $self;
}

sub size    { $_[0]{size} }
sub version { $_[0]{version} }
sub ecl     { $_[0]{ecl} }
sub mask    { $_[0]{mask} }
sub module  { $_[0]{mod}[ $_[2] ][ $_[1] ] }       # (x, y)
sub is_function { $_[0]{func}[ $_[2] ][ $_[1] ] }
sub rows    { [ map { [@$_] } @{ $_[0]{mod} } ] }

sub _set {
    my ($self, $x, $y, $dark) = @_;
    $self->{mod}[$y][$x]  = $dark ? 1 : 0;
    $self->{func}[$y][$x] = 1;
}

sub _draw_function_patterns {
    my ($self) = @_;
    my $n = $self->{size};
    for my $i (0 .. $n - 1) {                       # timing patterns
        $self->_set(6, $i, $i % 2 == 0);
        $self->_set($i, 6, $i % 2 == 0);
    }
    $self->_finder(3, 3);
    $self->_finder($n - 4, 3);
    $self->_finder(3, $n - 4);
    my @al = alignment_positions($self->{version});
    for my $i (0 .. $#al) {
        for my $j (0 .. $#al) {
            next if ($i == 0 && $j == 0) || ($i == 0 && $j == $#al) || ($i == $#al && $j == 0);
            $self->_alignment($al[$i], $al[$j]);
        }
    }
    $self->_draw_format(0);                         # reserve; redrawn after masking
    $self->_draw_version;
}

sub _finder {                                      # 7x7 finder plus light separator
    my ($self, $cx, $cy) = @_;
    my $n = $self->{size};
    for my $dy (-4 .. 4) {
        for my $dx (-4 .. 4) {
            my ($x, $y) = ($cx + $dx, $cy + $dy);
            next if $x < 0 || $y < 0 || $x >= $n || $y >= $n;
            my $d = abs($dx) > abs($dy) ? abs($dx) : abs($dy);
            $self->_set($x, $y, $d != 2 && $d != 4);
        }
    }
}

sub _alignment {
    my ($self, $cx, $cy) = @_;
    for my $dy (-2 .. 2) {
        for my $dx (-2 .. 2) {
            my $d = abs($dx) > abs($dy) ? abs($dx) : abs($dy);
            $self->_set($cx + $dx, $cy + $dy, $d != 1);
        }
    }
}

sub _draw_format {
    my ($self, $mask) = @_;
    my $bits = format_bits($self->{ecl}, $mask);
    my $n = $self->{size};
    my $bit = sub { ($bits >> $_[0]) & 1 };
    $self->_set(8, $_, $bit->($_)) for 0 .. 5;      # copy around the top-left finder
    $self->_set(8, 7, $bit->(6));
    $self->_set(8, 8, $bit->(7));
    $self->_set(7, 8, $bit->(8));
    $self->_set(14 - $_, 8, $bit->($_)) for 9 .. 14;
    $self->_set($n - 1 - $_, 8, $bit->($_)) for 0 .. 7;       # second copy
    $self->_set(8, $n - 15 + $_, $bit->($_)) for 8 .. 14;
    $self->_set(8, $n - 8, 1);                                # the always-dark module
}

sub _draw_version {
    my ($self) = @_;
    return if $self->{version} < 7;
    my $bits = version_bits($self->{version});
    my $n = $self->{size};
    for my $i (0 .. 17) {
        my $b = ($bits >> $i) & 1;
        my ($a, $c) = ($n - 11 + $i % 3, int($i / 3));
        $self->_set($a, $c, $b);
        $self->_set($c, $a, $b);
    }
}

# Place codewords along the two-column zigzag, skipping function modules.
sub place_codewords {
    my ($self, $cw) = @_;
    my $n = $self->{size};
    my $total = @$cw * 8;
    my $i = 0;
    for (my $right = $n - 1; $right >= 1; $right -= 2) {
        $right = 5 if $right == 6;                  # skip the vertical timing column
        my $upward = (($right + 1) & 2) == 0;
        for my $vert (0 .. $n - 1) {
            my $y = $upward ? $n - 1 - $vert : $vert;
            for my $j (0, 1) {
                my $x = $right - $j;
                next if $self->{func}[$y][$x];
                if ($i < $total) {
                    $self->{mod}[$y][$x] = ($cw->[ $i >> 3 ] >> (7 - ($i & 7))) & 1;
                    $i++;
                }
                # remaining remainder bits stay light (0)
            }
        }
    }
    croak "placed $i of $total bits" if $i != $total;
}

# XOR a mask onto data modules; applying it twice undoes it.
sub apply_mask {
    my ($self, $m) = @_;
    croak "mask must be 0..7" if $m !~ /^[0-7]$/;
    my $f = $MASKS[$m];
    my $n = $self->{size};
    for my $y (0 .. $n - 1) {
        for my $x (0 .. $n - 1) {
            $self->{mod}[$y][$x] ^= 1 if !$self->{func}[$y][$x] && $f->($x, $y);
        }
    }
}

# Finalise with a fixed mask, or pick the lowest-penalty mask when undef.
sub finish {
    my ($self, $mask) = @_;
    if (!defined $mask) {
        my ($best, $bestp);
        for my $m (0 .. 7) {
            $self->apply_mask($m);
            $self->_draw_format($m);
            my $p = $self->penalty;
            ($best, $bestp) = ($m, $p) if !defined $bestp || $p < $bestp;
            $self->apply_mask($m);
        }
        $mask = $best;
    }
    $self->apply_mask($mask);
    $self->_draw_format($mask);
    $self->{mask} = $mask;
    return $self;
}

# ISO/IEC 18004 section 7.8.3 penalty score.
sub penalty {
    my ($self) = @_;
    my $n = $self->{size};
    my $m = $self->{mod};
    my $score = 0;
    my @lines = @$m;
    push @lines, [ map { my $x = $_; [ map { $m->[$_][$x] } 0 .. $n - 1 ] } 0 .. $n - 1 ]->@*;
    for my $line (@lines) {
        # Rule 1: runs of five or more same-colour modules
        my $run = 1;
        for my $i (1 .. $n) {
            if ($i < $n && $line->[$i] == $line->[ $i - 1 ]) { $run++; next }
            $score += N1 + $run - 5 if $run >= 5;
            $run = 1;
        }
        # Rule 3: 1:1:3:1:1 finder-like pattern with 4 light modules on a side;
        # the area outside the symbol counts as light.
        my $s = ('0' x 4) . join('', @$line) . ('0' x 4);
        for my $pat ('00001011101', '10111010000') {
            my $pos = 0;
            while (($pos = index($s, $pat, $pos)) >= 0) { $score += N3; $pos++ }
        }
    }
    # Rule 3 counts a pattern with light on both sides twice above; that is
    # the behaviour of the reference encoder and the standard's wording.
    # Rule 2: 2x2 blocks of one colour
    my $dark = 0;
    for my $y (0 .. $n - 1) {
        for my $x (0 .. $n - 1) {
            $dark += $m->[$y][$x];
            next if $x == $n - 1 || $y == $n - 1;
            my $c = $m->[$y][$x];
            $score += N2 if $c == $m->[$y][ $x + 1 ] && $c == $m->[ $y + 1 ][$x] && $c == $m->[ $y + 1 ][ $x + 1 ];
        }
    }
    # Rule 4: dark proportion, 10 points per 5% away from 50%
    my $total = $n * $n;
    my $k = int((abs($dark * 20 - $total * 10) + $total - 1) / $total) - 1;
    $score += $k * N4 if $k > 0;
    return $score;
}

1;
