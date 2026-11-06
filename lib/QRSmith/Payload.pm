package QRSmith::Payload;
# Pure-Perl builders for common QR payload formats (Wi-Fi, vCard, mailto,
# SMS, geo). No CPAN dependencies; strings are escaped per each format's
# usual rules so the resulting payload can be handed straight to
# QRSmith->encode.
use strict;
use warnings;
use Exporter 'import';
use Carp qw(croak);

our @EXPORT_OK = qw(wifi vcard mailto sms geo url);
our $VERSION   = '0.2.0';

# WIFI:T:...;S:...;P:...;H:true;;  — MeCard-style Wi-Fi join string.
# Backslash, semicolon, comma and double-quote are escaped with '\'.
sub _wifi_escape {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/([\\;,\"])/\\$1/g;
    return $s;
}

sub wifi {
    my (%o) = @_;
    croak 'ssid required' unless defined $o{ssid};
    my $sec = $o{security} // 'WPA';
    croak "security must be WPA, WEP or nopass, got '$sec'"
        unless $sec =~ /\A(?:WPA|WEP|nopass)\z/;
    my $ssid = _wifi_escape($o{ssid});
    my $out  = "WIFI:T:$sec;S:$ssid;";
    if ($sec ne 'nopass' || defined $o{password}) {
        $out .= 'P:' . _wifi_escape($o{password} // '') . ';';
    }
    $out .= 'H:true;' if $o{hidden};
    return $out . ';';
}

# Minimal vCard 3.0. Unknown keys are ignored; multiline NOTE is folded
# with a single-line join so scanners stay happy.
sub vcard {
    my (%o) = @_;
    my $fn = $o{fn} // $o{name};
    croak 'name (or fn) required' unless defined $fn && length $fn;
    my @lines = ('BEGIN:VCARD', 'VERSION:3.0');
    if (defined $o{n}) {
        push @lines, 'N:' . _vcard_text($o{n});
    }
    else {
        # Treat "Last, First" or a single display name as FN; put FN into N too.
        my ($last, $first) = $fn =~ /,/ ? map { s/^\s+|\s+$//gr } split(/,/, $fn, 2)
                                        : ('', $fn);
        push @lines, 'N:' . _vcard_text($last) . ';' . _vcard_text($first) . ';;;';
    }
    push @lines, 'FN:' . _vcard_text($fn);
    push @lines, 'ORG:'   . _vcard_text($o{org})   if defined $o{org}   && length $o{org};
    push @lines, 'TEL:'   . _vcard_text($o{phone}) if defined $o{phone} && length $o{phone};
    push @lines, 'EMAIL:' . _vcard_text($o{email}) if defined $o{email} && length $o{email};
    push @lines, 'URL:'   . _vcard_text($o{url})   if defined $o{url}   && length $o{url};
    if (defined $o{note} && length $o{note}) {
        my $note = $o{note};
        $note =~ s/\r?\n/\\n/g;
        push @lines, 'NOTE:' . _vcard_text($note);
    }
    push @lines, 'END:VCARD';
    return join("\n", @lines) . "\n";
}

sub _vcard_text {
    my ($s) = @_;
    $s = '' unless defined $s;
    # RFC 6350 TEXT escaping: \, ;, ,
    $s =~ s/([\\;,])/\\$1/g;
    return $s;
}

# mailto: URI with proper percent-encoding of subject/body.
sub mailto {
    my (%o) = @_;
    croak 'email required' unless defined $o{email} && length $o{email};
    my $addr = $o{email};
    # Leave the address itself alone aside from stripping whitespace.
    $addr =~ s/^\s+|\s+$//g;
    my @q;
    push @q, 'subject=' . _uri_escape($o{subject}) if defined $o{subject};
    push @q, 'body='    . _uri_escape($o{body})    if defined $o{body};
    my $uri = 'mailto:' . $addr;
    $uri .= '?' . join('&', @q) if @q;
    return $uri;
}

# SMSTO:number:body is widely recognised; also accept sms:number?body=.
# Default form is SMSTO for scanner compatibility.
sub sms {
    my (%o) = @_;
    croak 'number required' unless defined $o{number} && length $o{number};
    my $num = $o{number};
    $num =~ s/[\s()-]//g;
    my $style = $o{style} // 'smsto';
    if ($style eq 'sms') {
        my $uri = 'sms:' . $num;
        $uri .= '?body=' . _uri_escape($o{body}) if defined $o{body};
        return $uri;
    }
    my $body = defined $o{body} ? $o{body} : '';
    # SMSTO does not percent-encode; keep body literal (scanners expect that).
    return 'SMSTO:' . $num . ':' . $body;
}

# geo:lat,lon or geo:lat,lon?q=query
sub geo {
    my (%o) = @_;
    croak 'lat required' unless defined $o{lat};
    croak 'lon required' unless defined $o{lon};
    my ($lat, $lon) = ($o{lat}, $o{lon});
    croak "lat must be numeric, got '$lat'" unless $lat =~ /\A-?\d+(?:\.\d+)?\z/;
    croak "lon must be numeric, got '$lon'" unless $lon =~ /\A-?\d+(?:\.\d+)?\z/;
    croak 'lat out of range' if $lat < -90  || $lat > 90;
    croak 'lon out of range' if $lon < -180 || $lon > 180;
    my $uri = "geo:$lat,$lon";
    $uri .= '?q=' . _uri_escape($o{query}) if defined $o{query} && length $o{query};
    return $uri;
}

# Passthrough / light normalisation for bare URLs.
sub url {
    my ($u) = @_;
    croak 'url required' unless defined $u && length $u;
    $u =~ s/^\s+|\s+$//g;
    return $u if $u =~ /\A[a-z][a-z0-9+.-]*:/i;    # already has a scheme
    return 'https://' . $u if $u =~ /\A[\w.-]+\.[a-z]{2,}(?:[\/?#].*)?\z/i;
    return $u;
}

# RFC 3986 unreserved stay literal; everything else is percent-encoded as UTF-8.
sub _uri_escape {
    my ($s) = @_;
    $s = '' unless defined $s;
    utf8::encode($s) if utf8::is_utf8($s);
    $s =~ s/([^A-Za-z0-9\-._~])/sprintf '%%%02X', ord $1/eg;
    return $s;
}

1;
