package QRSmith;
# Pure-Perl QR Code encoder. See README.md for an overview.
use strict;
use warnings;
use Carp qw(croak);
use QRSmith::Encoder qw(plan_text plan_segments data_codewords split_blocks interleave);
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
