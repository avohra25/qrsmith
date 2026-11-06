package QRSmith;
# Pure-Perl QR Code encoder. See README.md for an overview.
use strict;
use warnings;
use Carp qw(croak);
use QRSmith::Encoder qw(plan_text plan_segments data_codewords split_blocks interleave);
use QRSmith::Segment qw(make_structured_append make_bytes make_eci total_bits);
use QRSmith::Tables qw(num_data_codewords);
use QRSmith::Matrix;

our $VERSION = '0.1.0';

# QRSmith->encode($text, ecl => 'M', strategy => 'optimal', min_version => 1,
#                 max_version => 40, mask => undef, boost => 1, eci => undef)
sub encode {
    my ($class, $text, %opt) = @_;
    croak 'text required' unless defined $text;
    my %known = map { $_ => 1 } qw(ecl strategy min_version max_version mask boost eci);
    for (keys %opt) { croak "unknown option '$_'" unless $known{$_} }
    croak 'mask must be 0..7' if defined $opt{mask} && $opt{mask} !~ /^[0-7]$/;
    my $plan = plan_text($text, %opt);
    return $class->_build($plan, $opt{mask});
}

# Encode prebuilt QRSmith::Segment objects.
sub encode_segments {
    my ($class, $segs, %opt) = @_;
    my $plan = plan_segments($segs, %opt);
    return $class->_build($plan, $opt{mask});
}

# Thin wrapper: encode a string built by QRSmith::Payload (or any other
# preformatted payload). Equivalent to QRSmith->encode($payload, %opt).
sub encode_payload {
    my ($class, $payload, %opt) = @_;
    return $class->encode($payload, %opt);
}

# ISO/IEC 18004 Structured Append: split one logical payload across N
# symbols (2..16). Each returned QRSmith carries a Structured Append
# header (mode 0011 + index + total-1 + parity) followed by its byte
# slice. Parity is the bytewise XOR of the original UTF-8 octets and is
# identical in every symbol.
#
# Version / EC rule: every part is forced to the *same* version — the
# smallest version in [min_version, max_version] where the largest part
# (SA header + its data) fits at the requested ecl. If boost is on
# (default), the EC level is then raised to the strongest level that
# still fits every part at that version.
#
# Returns an arrayref of QRSmith objects (also list-context friendly via
# @{ ... }). Options match encode(), plus the required parts => N.
sub encode_structured {
    my ($class, $text, %opt) = @_;
    croak 'text required' unless defined $text;
    my $n = delete $opt{parts};
    croak 'parts => N required (integer 2..16)' unless defined $n;
    croak 'parts must be an integer 2..16'
        unless $n =~ /^\d+$/ && $n >= 2 && $n <= 16;
    my %known = map { $_ => 1 } qw(ecl strategy min_version max_version mask boost eci);
    for (keys %opt) { croak "unknown option '$_'" unless $known{$_} }
    # strategy is accepted for API symmetry but Structured Append always
    # encodes each slice as a byte segment (the split is over raw octets).
    delete $opt{strategy};

    my $bytes = $text;
    utf8::encode($bytes) if utf8::is_utf8($bytes) || $bytes =~ /[^\x00-\xFF]/;

    my $parity = 0;
    $parity ^= ord for split //, $bytes;

    my $len  = length $bytes;
    my $base = int($len / $n);
    my $rem  = $len % $n;
    my (@slices, $off);
    $off = 0;
    for my $i (0 .. $n - 1) {
        my $sz = $base + ($i < $rem ? 1 : 0);
        push @slices, substr($bytes, $off, $sz);
        $off += $sz;
    }

    my @seg_lists;
    for my $i (0 .. $n - 1) {
        my @segs = (make_structured_append($i, $n, $parity));
        push @segs, make_eci($opt{eci}) if defined $opt{eci};
        push @segs, make_bytes($slices[$i]) if length $slices[$i];
        push @seg_lists, \@segs;
    }

    my $ecl  = $opt{ecl} // 'M';
    my $minv = $opt{min_version} // 1;
    my $maxv = $opt{max_version} // 40;
    my $boost = $opt{boost} // 1;
    croak 'invalid version range' if $minv < 1 || $maxv > 40 || $minv > $maxv;

    my ($chosen_v, $chosen_ecl);
    for my $v ($minv .. $maxv) {
        my $ok = 1;
        for my $segs (@seg_lists) {
            my $bits = total_bits($segs, $v);
            if (!defined $bits || $bits > num_data_codewords($v, $ecl) * 8) {
                $ok = 0; last;
            }
        }
        next unless $ok;
        $chosen_v   = $v;
        $chosen_ecl = $ecl;
        if ($boost) {
            for my $better (qw(L M Q H)) {
                next if QRSmith::Tables::ecl_index($better) <= QRSmith::Tables::ecl_index($ecl);
                my $fits = 1;
                for my $segs (@seg_lists) {
                    my $bits = total_bits($segs, $v);
                    if ($bits > num_data_codewords($v, $better) * 8) { $fits = 0; last }
                }
                $chosen_ecl = $better if $fits;
            }
        }
        last;
    }
    die "structured data does not fit in $n version $minv-$maxv symbols at level $ecl\n"
        unless defined $chosen_v;

    my @out;
    for my $i (0 .. $n - 1) {
        my $qr = $class->encode_segments($seg_lists[$i],
            ecl => $chosen_ecl, boost => 0,
            min_version => $chosen_v, max_version => $chosen_v,
            defined $opt{mask} ? (mask => $opt{mask}) : (),
        );
        $qr->{structured} = {
            index  => $i,
            total  => $n,
            parity => $parity,
            bytes  => length $slices[$i],
        };
        push @out, $qr;
    }
    return \@out;
}

sub _build {
    my ($class, $plan, $mask) = @_;
    my ($v, $ecl) = @$plan{qw(version ecl)};
    my $cw = interleave(split_blocks(data_codewords($plan), $v, $ecl));
    my $m = QRSmith::Matrix->new(version => $v, ecl => $ecl);
    $m->place_codewords($cw);
    $m->finish($mask);
    return bless { matrix => $m, plan => $plan }, $class;
}

sub version  { $_[0]{matrix}->version }
sub ecl      { $_[0]{matrix}->ecl }
sub mask     { $_[0]{matrix}->mask }
sub size     { $_[0]{matrix}->size }
sub module   { $_[0]{matrix}->module($_[1], $_[2]) }   # (x, y), 1 = dark
sub rows     { $_[0]{matrix}->rows }
sub segments { [ map { { mode => $_->mode, chars => $_->num_chars } } @{ $_[0]{plan}{segments} } ] }
# Structured Append metadata (undef when the symbol was not produced by
# encode_structured): { index, total, parity, bytes }.
sub structured { $_[0]{structured} }

# Plain text rendering, '#' for dark and ' ' for light, with a quiet zone.
sub as_text {
    my ($self, %o) = @_;
    my $q = $o{quiet} // 4;
    my ($on, $off) = ($o{dark} // '##', $o{light} // '  ');
    my $n = $self->size;
    my @out;
    for my $y (-$q .. $n - 1 + $q) {
        push @out, join '', map {
            ($_ >= 0 && $_ < $n && $y >= 0 && $y < $n && $self->module($_, $y)) ? $on : $off
        } -$q .. $n - 1 + $q;
    }
    return join("\n", @out) . "\n";
}

1;
