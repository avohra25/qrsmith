package QRSmith::BitBuffer;
# A growable sequence of bits, most significant bit first.
use strict;
use warnings;
use Carp qw(croak);

sub new { my ($class) = @_; return bless { bits => [] }, $class }

sub append {
    my ($self, $value, $len) = @_;
    croak "bit length must be 0..31, got $len" if $len < 0 || $len > 31;
    croak "value $value does not fit in $len bits" if $value < 0 || $value >> $len;
    push @{ $self->{bits} }, ($value >> $_) & 1 for reverse 0 .. $len - 1;
    return $self;
}

sub append_buffer {
    my ($self, $other) = @_;
    push @{ $self->{bits} }, @{ $other->{bits} };
    return $self;
}

sub length { scalar @{ $_[0]{bits} } }
sub bits   { [ @{ $_[0]{bits} } ] }
sub get    { $_[0]{bits}[ $_[1] ] }

# Pack into bytes; the length must be a multiple of 8.
sub to_bytes {
    my ($self) = @_;
    my $bits = $self->{bits};
    croak 'bit length is not a multiple of 8' if @$bits % 8;
    my @out;
    for (my $i = 0; $i < @$bits; $i += 8) {
        my $b = 0;
        $b = ($b << 1) | $bits->[ $i + $_ ] for 0 .. 7;
        push @out, $b;
    }
    return \@out;
}

sub as_string { join '', @{ $_[0]{bits} } }

1;
