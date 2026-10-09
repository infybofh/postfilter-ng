package Postfilter::RFC5536;

use strict;
use warnings;

=head1 NAME

Postfilter::RFC5536 - Netnews article syntax validation and Injection-Info parsing.

=head1 DESCRIPTION

This module centralises the RFC 5536 syntax that Postfilter-NG must treat as an
injection invariant.  It intentionally separates standards validity from local
site policy.  The nnrpd Perl hook exposes headers as a hash, so duplicate-field
counts are no longer observable here; INN remains responsible for rejecting
multiple occurrences before/after the hook as appropriate.

=cut

use Exporter 'import';
use Postfilter::Util qw(valid_followup_to valid_newsgroup_list valid_newsgroup_name);

our @EXPORT_OK = qw(
    parse_injection_info
    serialize_injection_info
    validate_article
    valid_injection_info
    valid_message_id
);

my $ATEXT = q{A-Za-z0-9!#$%&'*+\-/=?^_`{|}~};
my $DOT_ATOM = qr/[$ATEXT]+(?:\.[$ATEXT]+)*/;
my $MSG_ID_RIGHT = qr/(?:$DOT_ATOM|\[[\x21-\x3d\x3f-\x5a\x5e-\x7e]*\])/;
my $MSG_ID = qr/<$DOT_ATOM\@$MSG_ID_RIGHT>/;
my $TOKEN = qr/[A-Za-z0-9!#$%&'*+\-.^_`{|}~]+/;

# Function: valid_message_id
# Purpose: Validates the restricted RFC 5536 msg-id syntax and 250-octet limit.
# Parameters: $value
# Operational notes: Surrounding WSP is accepted because Message-ID permits *WSP around msg-id.
sub valid_message_id {
    my ($value) = @_;
    return 0 unless defined $value;
    $value =~ s/^[ \t]+|[ \t]+$//g;
    return 0 if length($value) > 250;
    return $value =~ /\A$MSG_ID\z/ ? 1 : 0;
}

# Function: _strip_cfws
# Purpose: Removes simple RFC comments and folding whitespace used around structured elements.
# Parameters: $value
# Operational notes: Handles nesting and quoted pairs conservatively; malformed comments fail.
sub _strip_cfws {
    my ($value) = @_;
    return undef unless defined $value;
    my $out = '';
    my $depth = 0;
    my $escaped = 0;
    for my $ch (split //, $value) {
        if ($escaped) {
            $escaped = 0;
            next if $depth;
            $out .= $ch;
            next;
        }
        if ($ch eq '\\') {
            $escaped = 1;
            $out .= $ch unless $depth;
            next;
        }
        if ($ch eq '(') {
            $depth++;
            next;
        }
        if ($ch eq ')') {
            return undef unless $depth;
            $depth--;
            next;
        }
        next if $depth;
        $out .= $ch;
    }
    return undef if $depth || $escaped;
    $out =~ s/(?:\r?\n)?[ \t]+/ /g;
    $out =~ s/^ +| +$//g;
    return $out;
}

# Function: _unfold_field_body
# Purpose: Converts a physically folded RFC 5322 field body into its logical single-line form.
# Parameters: $value
# Operational notes: Only legal CRLF/LF followed by WSP is unfolded; malformed bare line breaks fail.
sub _unfold_field_body {
    my ($value) = @_;
    return undef unless defined $value;
    return undef if $value =~ /\r(?!\n)/;
    return undef if $value =~ /(?<!\r)\n(?![ \t])/;
    return undef if $value =~ /\r\n(?![ \t])/;
    $value =~ s/\r?\n(?=[ \t])//g;
    return $value;
}

# Function: _split_semicolons
# Purpose: Splits an RFC parameter list without splitting semicolons inside quoted strings/comments.
# Parameters: $value
# Operational notes: Returns undef on unterminated quote/comment or dangling quoted-pair.
sub _split_semicolons {
    my ($value) = @_;
    my @parts;
    my $part = '';
    my ($quote, $comment, $escaped) = (0, 0, 0);
    for my $ch (split //, $value // '') {
        if ($escaped) {
            $part .= $ch;
            $escaped = 0;
            next;
        }
        if ($ch eq '\\' && ($quote || $comment)) {
            $part .= $ch;
            $escaped = 1;
            next;
        }
        if ($quote) {
            $part .= $ch;
            $quote = 0 if $ch eq '"';
            next;
        }
        if ($comment) {
            $part .= $ch;
            $comment++ if $ch eq '(';
            $comment-- if $ch eq ')';
            next;
        }
        if ($ch eq '"') {
            $quote = 1;
            $part .= $ch;
            next;
        }
        if ($ch eq '(') {
            $comment = 1;
            $part .= $ch;
            next;
        }
        if ($ch eq ';') {
            push @parts, $part;
            $part = '';
            next;
        }
        $part .= $ch;
    }
    return undef if $quote || $comment || $escaped;
    push @parts, $part;
    return \@parts;
}

# Function: _unquote_value
# Purpose: Decodes one MIME parameter token/quoted-string while preserving its semantic value.
# Parameters: $raw
# Operational notes: Returns undef for malformed values.
sub _unquote_value {
    my ($raw) = @_;
    return undef unless defined $raw;
    $raw =~ s/^[ \t]+|[ \t]+$//g;
    return $raw if $raw =~ /\A$TOKEN\z/;
    return undef unless $raw =~ /\A"(.*)"\z/s;
    my $inner = $1;
    my $out = '';
    my $escaped = 0;
    for my $ch (split //, $inner) {
        if ($escaped) {
            return undef if ord($ch) > 127 || ord($ch) == 0;
            $out .= $ch;
            $escaped = 0;
            next;
        }
        if ($ch eq '\\') {
            $escaped = 1;
            next;
        }
        return undef if $ch eq '"' || $ch eq "\r" || $ch eq "\n" || ord($ch) == 0;
        return undef if ord($ch) > 127;
        $out .= $ch;
    }
    return undef if $escaped;
    return $out;
}

# Function: _quote_value
# Purpose: Serializes one Injection-Info parameter as a safe MIME quoted-string.
# Parameters: $value
# Operational notes: CR, LF and NUL are rejected rather than emitted.
sub _quote_value {
    my ($value) = @_;
    $value //= '';
    return undef if $value =~ /[\r\n\0]/ || $value =~ /[^\x00-\x7f]/;
    $value =~ s/([\\"])/\\$1/g;
    return qq{"$value"};
}

# Function: _valid_path_identity
# Purpose: Validates the RFC 5536 path-identity form used by Injection-Info.
# Parameters: $value
# Operational notes: Accepts legacy single-label path-nodot identities and multi-label domain forms.
sub _valid_path_identity {
    my ($value) = @_;
    return 0 unless defined $value && length $value;
    return 1 if $value =~ /\A[A-Za-z0-9_-]+\z/;
    return 0 unless $value =~ /\A[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z/;
    my @labels = split /\./, $value;
    return 0 if grep { !length($_) || $_ =~ /^-/ || $_ =~ /-$/ } @labels;
    return 0 unless $labels[-1] =~ /[A-Za-z]/;
    return 1;
}

# Function: parse_injection_info
# Purpose: Parses RFC 5536 Injection-Info without losing quoted semicolons or equals signs.
# Parameters: $value
# Operational notes: Returns undef on malformed syntax; preserves parameter order and unknown x-* extensions.
sub parse_injection_info {
    my ($value) = @_;
    return undef unless defined $value && length $value;
    return undef if $value =~ /\0/;
    $value = _unfold_field_body($value);
    return undef unless defined $value;

    my $parts = _split_semicolons($value) or return undef;
    return undef unless @{$parts};
    my $identity = _strip_cfws(shift @{$parts});
    return undef unless defined $identity && _valid_path_identity($identity);

    my @params;
    my %standard_seen;
    for my $raw (@{$parts}) {
        my $clean = _strip_cfws($raw);
        return undef unless defined $clean && length $clean; # catches trailing ';'
        my ($attribute, $raw_value) = $clean =~ /\A($TOKEN)\s*=\s*(.+)\z/s;
        return undef unless defined $attribute && defined $raw_value;
        my $decoded = _unquote_value($raw_value);
        return undef unless defined $decoded;
        my $name = lc $attribute;
        if ($name =~ /\A(?:posting-host|posting-account|logging-data|mail-complaints-to)\z/) {
            return undef if $standard_seen{$name}++;
        }
        elsif ($name !~ /\Ax-/) {
            return undef;
        }
        push @params, { name => $name, value => $decoded };
    }

    return { identity => $identity, parameters => \@params };
}

# Function: serialize_injection_info
# Purpose: Serializes a parsed Injection-Info structure without a trailing semicolon.
# Parameters: $parsed
# Operational notes: Always quotes parameter values to avoid ambiguity with MIME tspecials.
sub serialize_injection_info {
    my ($parsed) = @_;
    return undef unless ref($parsed) eq 'HASH' && _valid_path_identity($parsed->{identity});
    my @out = ($parsed->{identity});
    for my $item (@{ $parsed->{parameters} // [] }) {
        return undef unless ref($item) eq 'HASH';
        my $name = lc($item->{name} // '');
        return undef unless $name =~ /\A$TOKEN\z/;
        my $quoted = _quote_value($item->{value});
        return undef unless defined $quoted;
        push @out, "$name=$quoted";
    }
    return join('; ', @out);
}

# Function: valid_injection_info
# Purpose: Reports whether an Injection-Info field is RFC 5536 parseable.
# Parameters: $value
# Operational notes: Validation is round-trip safe for fields Postfilter may rewrite.
sub valid_injection_info {
    my ($value) = @_;
    return defined parse_injection_info($value) ? 1 : 0;
}

# Function: _valid_references
# Purpose: Validates References as one or more RFC 5536 msg-id values separated by CFWS.
# Parameters: $value
# Operational notes: Comments are accepted between identifiers and stripped conservatively.
sub _valid_references {
    my ($value) = @_;
    return 0 unless defined $value && length $value;
    my @ids = ($value =~ /($MSG_ID)/g);
    return 0 unless @ids;
    for my $id (@ids) { return 0 unless valid_message_id($id); }
    my $rest = $value;
    $rest =~ s/$MSG_ID/ /g;
    $rest = _strip_cfws($rest);
    return defined($rest) && $rest !~ /\S/ ? 1 : 0;
}

# Function: _valid_distribution
# Purpose: Validates RFC 5536 Distribution dist-list syntax.
# Parameters: $value
# Operational notes: This is syntax only; local allow-list policy is applied elsewhere.
sub _valid_distribution {
    my ($value) = @_;
    return 0 unless defined $value && length $value;
    my @items = split /,/, $value, -1;
    return 0 unless @items;
    for my $item (@items) {
        $item =~ s/^[ \t]+|[ \t]+$//g;
        return 0 unless $item =~ /\A[A-Za-z0-9][A-Za-z0-9+_-]*\z/;
        return 0 if lc($item) eq 'all';
    }
    return 1;
}

# Function: _valid_control
# Purpose: Validates RFC 5536 generic Control syntax and Control/Supersedes exclusivity is checked separately.
# Parameters: $value
# Operational notes: Specific control verbs remain governed by RFC 5537 and local policy.
sub _valid_control {
    my ($value) = @_;
    return 0 unless defined $value;
    $value =~ s/^[ \t]+|[ \t]+$//g;
    return 0 unless length $value;
    return $value =~ /\A$TOKEN(?:[ \t]+[\x21-\x7e]+)*\z/ ? 1 : 0;
}

# Function: _valid_archive
# Purpose: Validates the RFC 5536 Archive yes/no form and MIME-style parameters.
# Parameters: $value
# Operational notes: Unknown parameters are syntactically accepted as the RFC permits.
sub _valid_archive {
    my ($value) = @_;
    return 0 unless defined $value;
    my $parts = _split_semicolons($value) or return 0;
    my $first = _strip_cfws(shift @{$parts});
    return 0 unless defined $first && $first =~ /\A(?:yes|no)\z/i;
    for my $raw (@{$parts}) {
        my $clean = _strip_cfws($raw);
        return 0 unless defined $clean && length $clean;
        my ($attribute, $raw_value) = $clean =~ /\A($TOKEN)\s*=\s*(.+)\z/s;
        return 0 unless defined $attribute && defined _unquote_value($raw_value);
    }
    return 1;
}

# Function: _valid_date
# Purpose: Validates the current RFC 5322 date-time syntax used by RFC 5536.
# Parameters: $value
# Operational notes: RFC 5536 additionally requires accepting GMT; obsolete named zones are
#                    otherwise not accepted. Semantic calendar validation remains deliberately
#                    limited to field ranges because RFC 5322 grammar does not encode month/day.
sub _valid_date {
    my ($value) = @_;
    return 0 unless defined $value && length $value;
    my $clean = _strip_cfws($value);
    return 0 unless defined $clean && length $clean;
    my ($dow, $day, $month, $year, $hour, $minute, $second, $zone) =
        $clean =~ /\A(?:(Mon|Tue|Wed|Thu|Fri|Sat|Sun),\s+)?(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{4,})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s+([+-]\d{4}|GMT)\z/i;
    return 0 unless defined $day;
    return 0 if $day < 1 || $day > 31;
    return 0 if $hour > 23 || $minute > 59;
    return 0 if defined($second) && $second > 60;
    if ($zone ne 'GMT' && $zone ne 'gmt') {
        my $zh = substr($zone, 1, 2);
        my $zm = substr($zone, 3, 2);
        return 0 if $zh > 23 || $zm > 59;
    }
    return 1;
}

# Function: _valid_mime_version
# Purpose: Validates the canonical MIME-Version grammar used by MIME-conformant Netnews articles.
# Parameters: $value
# Operational notes: RFC 2045 permits comments/CFWS; these are stripped before the 1.0 check.
sub _valid_mime_version {
    my ($value) = @_;
    my $clean = _strip_cfws($value);
    return defined($clean) && $clean =~ /\A1\s*\.\s*0\z/ ? 1 : 0;
}

# Function: _valid_cte
# Purpose: Validates Content-Transfer-Encoding token syntax.
# Parameters: $value
# Operational notes: Extension encodings beginning x- are syntactically permitted by MIME.
sub _valid_cte {
    my ($value) = @_;
    return 0 unless defined $value;
    $value =~ s/^[ \t]+|[ \t]+$//g;
    return $value =~ /\A(?:7bit|8bit|binary|quoted-printable|base64|x-[A-Za-z0-9!#$%&'*+.^_`{|}~-]+)\z/i ? 1 : 0;
}

# Function: _valid_parameterized_header
# Purpose: Validates a MIME token/token or token value followed by RFC-style parameters.
# Parameters: $value, $media_type
# Operational notes: Semicolons inside quoted parameter values are preserved.
sub _valid_parameterized_header {
    my ($value, $media_type) = @_;
    return 0 unless defined $value && length $value;
    my $parts = _split_semicolons($value) or return 0;
    my $first = _strip_cfws(shift @{$parts});
    return 0 unless defined $first && length $first;
    return 0 if $media_type && $first !~ /\A$TOKEN\/$TOKEN\z/;
    return 0 if !$media_type && $first !~ /\A$TOKEN\z/;
    my %seen;
    for my $raw (@{$parts}) {
        my $clean = _strip_cfws($raw);
        return 0 unless defined $clean && length $clean;
        my ($attribute, $raw_value) = $clean =~ /\A($TOKEN)\s*=\s*(.+)\z/s;
        return 0 unless defined $attribute && defined _unquote_value($raw_value);
        return 0 if $seen{lc $attribute}++;
    }
    return 1;
}

# Function: _valid_mailbox_list
# Purpose: Applies a conservative current-syntax mailbox-list check to Netnews address fields.
# Parameters: $value, $single
# Operational notes: Accepts common mailbox forms without obsolete RFC 5322 syntax.
sub _valid_mailbox_list {
    my ($value, $single) = @_;
    return 0 unless defined $value && length $value;
    return 0 if $value =~ /[\r\n\0]/;
    my @parts;
    my $part = '';
    my ($quote, $angle, $comment, $escaped) = (0, 0, 0, 0);
    for my $ch (split //, $value) {
        if ($escaped) { $part .= $ch; $escaped = 0; next; }
        if ($ch eq '\\' && ($quote || $comment)) { $part .= $ch; $escaped = 1; next; }
        if ($quote) { $part .= $ch; $quote = 0 if $ch eq '"'; next; }
        if ($comment) { $part .= $ch; $comment++ if $ch eq '('; $comment-- if $ch eq ')'; next; }
        if ($ch eq '"') { $quote = 1; $part .= $ch; next; }
        if ($ch eq '(') { $comment = 1; $part .= $ch; next; }
        if ($ch eq '<') { return 0 if $angle; $angle = 1; $part .= $ch; next; }
        if ($ch eq '>') { return 0 unless $angle; $angle = 0; $part .= $ch; next; }
        if ($ch eq ',' && !$angle) { push @parts, $part; $part=''; next; }
        $part .= $ch;
    }
    return 0 if $quote || $angle || $comment || $escaped;
    push @parts, $part;
    return 0 if $single && @parts != 1;
    return 0 unless @parts;
    my $local_atom = qr/[$ATEXT]+(?:\.[$ATEXT]+)*/;
    my $quoted_local = qr/"(?:[^"\\\r\n]|\\[\x20-\x7e])*"/;
    my $domain = qr/(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?))*/;
    my $literal = qr/\[[^\[\]\r\n]+\]/;
    my $addr = qr/(?:$local_atom|$quoted_local)\@(?:$domain|$literal)/;
    for my $mailbox (@parts) {
        $mailbox =~ s/^[ \t]+|[ \t]+$//g;
        return 0 unless length $mailbox;
        my $clean = _strip_cfws($mailbox);
        return 0 unless defined $clean && length $clean;
        if ($clean =~ /<([^<>]+)>\s*\z/) {
            return 0 unless $1 =~ /\A$addr\z/;
        }
        else {
            return 0 unless $clean =~ /\A$addr\z/;
        }
    }
    return 1;
}

# Function: _valid_xref
# Purpose: Validates the RFC 5536 Xref server-name and newsgroup:article-locator list.
# Parameters: $value
# Operational notes: Malformed values are never allowed through the final invariant.
sub _valid_xref {
    my ($value) = @_;
    return 0 unless defined $value;
    my @parts = grep { length } split /[ \t]+/, $value;
    return 0 unless @parts >= 2;
    my $server = shift @parts;
    return 0 unless _valid_path_identity($server);
    for my $item (@parts) {
        my ($group, $locator) = split /:/, $item, 2;
        return 0 unless defined $group && defined $locator;
        return 0 unless valid_newsgroup_name($group);
        return 0 unless length($locator) && $locator !~ /[\s();]/ && $locator =~ /\A[\x21-\x7e]+\z/;
    }
    return 1;
}

# Function: _valid_path
# Purpose: Validates RFC 5536 Path including match/other diagnostics and a legacy tail entry.
# Parameters: $value
# Operational notes: Diagnostic IP syntax is checked conservatively; ordinary path identities
#                    use the same validator as Injection-Info.
sub _valid_path {
    my ($value) = @_;
    return 0 unless defined $value && length $value;
    $value =~ s/^[ \t]+|[ \t]+$//g;
    return 0 if $value =~ /[\r\n\0]/;
    my @parts = split /!/, $value, -1;
    return 0 unless @parts;
    my $tail = pop @parts;
    return 0 unless $tail =~ /\A[A-Za-z0-9_-]+\z/;
    my $i = 0;
    while ($i < @parts) {
        my $identity = $parts[$i++];
        $identity =~ s/[ \t]+$//;
        return 0 unless _valid_path_identity($identity);
        next unless $i < @parts;
        my $candidate = $parts[$i];
        $candidate =~ s/^[ \t]+|[ \t]+$//g;
        if ($candidate eq '') { $i++; next; }
        if ($candidate =~ /\A\.[A-Za-z]+(?:\.(?:[A-Za-z0-9_.:-]+))?\z/) { $i++; next; }
        if ($candidate =~ /\A(?:\d{1,3}\.){3}\d{1,3}\z/) { $i++; next; }
        # Otherwise it begins the next path-identity and is consumed next loop.
    }
    return 1;
}

# Function: _valid_inn_nnrpd_staging_path
# Purpose: Validates the temporary Path form produced by INN nnrpd before filter_post runs.
# Parameters: $value
# Operational notes: nnrpd prepends .POSTED[.source]! before the Perl hook and innd later
#                    prepends the server path-identity.  Only that leading POSTED diagnostic
#                    is accepted as a non-final form; arbitrary leading diagnostics remain invalid.
sub _valid_inn_nnrpd_staging_path {
    my ($value) = @_;
    return 0 unless defined $value && length $value;
    $value =~ s/^[ \t]+|[ \t]+$//g;
    return 0 if $value =~ /[\r\n\0]/;
    return 0 unless $value =~ /\A\.POSTED(?:\.|!)/i;

    # RFC 5537 requires the injecting/relaying agent to prepend its primary
    # path-identity.  Test the exact future grammar with a harmless synthetic
    # identity rather than weakening the normal RFC 5536 Path validator.
    return _valid_path('postfilter.invalid!' . $value);
}

# Function: _valid_user_agent
# Purpose: Validates the RFC 5536 sequence of product[/version] tokens with optional CFWS.
# Parameters: $value
# Operational notes: Comments are stripped only where CFWS is permitted.
sub _valid_user_agent {
    my ($value) = @_;
    my $clean = _strip_cfws($value);
    return 0 unless defined $clean && length $clean;
    $clean =~ s/[ \t]*\/[ \t]*/\//g;
    my @products = split /[ \t]+/, $clean;
    return 0 unless @products;
    for my $product (@products) {
        return 0 unless $product =~ /\A$TOKEN(?:\/$TOKEN)?\z/;
    }
    return 1;
}

# Function: _valid_content_language
# Purpose: Validates common RFC 3282 Content-Language language lists.
# Parameters: $value
# Operational notes: Language tags are syntax-checked only; registry membership is not policy here.
sub _valid_content_language {
    my ($value) = @_;
    return 0 unless defined $value && length $value;
    my @items = split /,/, $value, -1;
    return 0 unless @items;
    for my $item (@items) {
        $item =~ s/^[ \t]+|[ \t]+$//g;
        return 0 unless $item =~ /\A(?:\*|[A-Za-z]{1,8}(?:-[A-Za-z0-9]{1,8})*)\z/;
    }
    return 1;
}

# Function: _body_error
# Purpose: Enforces RFC 5322 body line and NUL constraints independently of site policy limits.
# Parameters: $body
# Operational notes: The 998-octet hard line limit cannot be disabled by local policy.
sub _body_error {
    my ($body) = @_;
    $body //= '';
    return 'nul-in-body' if $body =~ /\0/;
    return 'bare-cr-in-body' if $body =~ /\r(?!\n)/;
    for my $line (split /\r?\n/, $body, -1) {
        return 'body-line-too-long' if length($line) > 998;
    }
    return undef;
}

# Function: _general_header_error
# Purpose: Applies RFC 5322/5536 invariants common to every exposed header field.
# Parameters: $name, $value
# Operational notes: INN has already parsed field boundaries, but embedded bare newlines/NUL remain invalid.
sub _general_header_error {
    my ($name, $value) = @_;
    return 'invalid-header-name' unless defined $name && $name =~ /\A[!-9;-~]+\z/;
    return undef unless defined $value; # undef is INN's deletion marker
    return 'nul-in-header' if $value =~ /\0/;
    return 'non-ascii-header' if $value =~ /[^\x00-\x7f]/;
    return 'invalid-header-control' if $value =~ /[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]/;
    return 'bare-cr' if $value =~ /\r(?!\n)/;
    return 'invalid-folding' if $value =~ /\n(?![ \t])/;
    return 'invalid-folding' if $value =~ /\r(?!\n)/;
    my @lines = split /\r?\n/, $value, -1;
    for my $index (0 .. $#lines) {
        my $line = $lines[$index];
        return 'empty-folded-line' unless $line =~ /\S/;
        # RFC 5322 limits each physical line to 998 characters excluding CRLF.
        # The first line also contains the field name, colon and generated SP.
        my $physical_length = $index == 0
            ? length($name) + 2 + length($line)
            : length($line);
        return 'header-line-too-long' if $physical_length > 998;
    }
    return undef;
}

# Function: _validation_header_view
# Purpose: Builds a case-insensitive, unfolded view of headers for structured syntax validation.
# Parameters: $headers, $errors
# Operational notes: Physical folding is validated separately; duplicate spellings differing only by case are rejected.
sub _validation_header_view {
    my ($headers, $errors) = @_;
    my %known = map { lc($_) => $_ } qw(
        From Newsgroups Subject Message-ID Followup-To Distribution Date Expires
        Injection-Date References Supersedes Control Archive Injection-Info MIME-Version
        User-Agent Content-Language Content-Transfer-Encoding Approved Sender Content-Type
        Content-Disposition Xref Lines Path
    );
    my %view;
    my %seen;
    for my $name (keys %{ $headers || {} }) {
        next if $name =~ /^__/;
        my $lc = lc $name;
        next unless exists $known{$lc};
        if (exists $seen{$lc}) {
            push @{$errors}, { header => $known{$lc}, reason => 'duplicate-header-name-case-insensitive' };
            next;
        }
        $seen{$lc} = $name;
        my $value = $headers->{$name};
        if (defined $value) {
            my $unfolded = _unfold_field_body($value);
            $view{ $known{$lc} } = defined($unfolded) ? $unfolded : $value;
        }
        else {
            $view{ $known{$lc} } = undef;
        }
    }
    return \%view;
}

# Function: validate_article
# Purpose: Validates syntax invariants visible to the nnrpd hook before an article can be accepted.
# Parameters: $headers, $body, %options
# Operational notes: Date, Message-ID and Path may be absent in a proto-article because RFC 5537 allows the injecting agent to add them.
#                    Set allow_inn_nnrpd_staging_path only inside INN's filter_post hook, where
#                    nnrpd has already prepended .POSTED but innd has not yet prepended its identity.
sub validate_article {
    my ($headers, $body, %options) = @_;
    $headers ||= {};
    my @errors;

    for my $name (keys %{$headers}) {
        next if $name =~ /^__/;
        my $error = _general_header_error($name, $headers->{$name});
        push @errors, { header => $name, reason => $error } if $error;
    }

    my $validation_headers = _validation_header_view($headers, \@errors);
    $headers = $validation_headers;

    for my $required (qw(From Newsgroups Subject)) {
        push @errors, { header => $required, reason => 'missing-mandatory-header' }
            unless defined($headers->{$required}) && length($headers->{$required});
    }

    if (defined($headers->{'Message-ID'}) && length($headers->{'Message-ID'})) {
        push @errors, { header => 'Message-ID', reason => 'invalid-message-id' }
            unless valid_message_id($headers->{'Message-ID'});
    }
    push @errors, { header => 'Newsgroups', reason => 'invalid-newsgroups' }
        unless valid_newsgroup_list($headers->{Newsgroups});
    if (exists $headers->{'Followup-To'} && defined $headers->{'Followup-To'}) {
        push @errors, { header => 'Followup-To', reason => 'invalid-followup-to' }
            unless valid_followup_to($headers->{'Followup-To'});
    }
    if (defined($headers->{Distribution}) && length($headers->{Distribution})) {
        push @errors, { header => 'Distribution', reason => 'invalid-distribution' }
            unless _valid_distribution($headers->{Distribution});
    }
    for my $date_name (qw(Date Expires Injection-Date)) {
        next unless defined($headers->{$date_name}) && length($headers->{$date_name});
        push @errors, { header => $date_name, reason => 'invalid-date-time' }
            unless _valid_date($headers->{$date_name});
    }
    if (defined($headers->{References}) && length($headers->{References})) {
        push @errors, { header => 'References', reason => 'invalid-references' }
            unless _valid_references($headers->{References});
    }
    if (defined($headers->{Supersedes}) && length($headers->{Supersedes})) {
        push @errors, { header => 'Supersedes', reason => 'invalid-supersedes' }
            unless valid_message_id($headers->{Supersedes});
    }
    if (defined($headers->{Control}) && length($headers->{Control})) {
        push @errors, { header => 'Control', reason => 'invalid-control' }
            unless _valid_control($headers->{Control});
        push @errors, { header => 'Control', reason => 'control-and-supersedes-mutually-exclusive' }
            if defined($headers->{Supersedes}) && length($headers->{Supersedes});
    }
    if (defined($headers->{Archive}) && length($headers->{Archive})) {
        push @errors, { header => 'Archive', reason => 'invalid-archive' }
            unless _valid_archive($headers->{Archive});
    }
    if (defined($headers->{'Injection-Info'}) && length($headers->{'Injection-Info'})) {
        push @errors, { header => 'Injection-Info', reason => 'invalid-injection-info' }
            unless valid_injection_info($headers->{'Injection-Info'});
    }
    if (defined($headers->{'MIME-Version'}) && length($headers->{'MIME-Version'})) {
        push @errors, { header => 'MIME-Version', reason => 'invalid-mime-version' }
            unless _valid_mime_version($headers->{'MIME-Version'});
    }
    if (defined($headers->{'User-Agent'}) && length($headers->{'User-Agent'})) {
        push @errors, { header => 'User-Agent', reason => 'invalid-user-agent' }
            unless _valid_user_agent($headers->{'User-Agent'});
    }
    if (defined($headers->{'Content-Language'}) && length($headers->{'Content-Language'})) {
        push @errors, { header => 'Content-Language', reason => 'invalid-content-language' }
            unless _valid_content_language($headers->{'Content-Language'});
    }
    if (defined($headers->{'Content-Transfer-Encoding'}) && length($headers->{'Content-Transfer-Encoding'})) {
        push @errors, { header => 'Content-Transfer-Encoding', reason => 'invalid-content-transfer-encoding' }
            unless _valid_cte($headers->{'Content-Transfer-Encoding'});
    }
    for my $field (qw(From Approved)) {
        next unless defined($headers->{$field}) && length($headers->{$field});
        push @errors, { header => $field, reason => 'invalid-mailbox-list' }
            unless _valid_mailbox_list($headers->{$field}, 0);
    }
    if (defined($headers->{Sender}) && length($headers->{Sender})) {
        push @errors, { header => 'Sender', reason => 'invalid-mailbox' }
            unless _valid_mailbox_list($headers->{Sender}, 1);
    }
    if (defined($headers->{'Content-Type'}) && length($headers->{'Content-Type'})) {
        push @errors, { header => 'Content-Type', reason => 'invalid-content-type' }
            unless _valid_parameterized_header($headers->{'Content-Type'}, 1);
    }
    if (defined($headers->{'Content-Disposition'}) && length($headers->{'Content-Disposition'})) {
        push @errors, { header => 'Content-Disposition', reason => 'invalid-content-disposition' }
            unless _valid_parameterized_header($headers->{'Content-Disposition'}, 0);
    }
    if (defined($headers->{Xref}) && length($headers->{Xref})) {
        push @errors, { header => 'Xref', reason => 'invalid-xref' }
            unless _valid_xref($headers->{Xref});
    }
    if (defined($headers->{Lines}) && length($headers->{Lines})) {
        push @errors, { header => 'Lines', reason => 'invalid-lines' }
            unless $headers->{Lines} =~ /\A[ \t]*\d+[ \t]*\z/;
    }

    if (defined($headers->{Path}) && length($headers->{Path})) {
        my $path_ok = _valid_path($headers->{Path});
        if (!$path_ok && $options{allow_inn_nnrpd_staging_path}) {
            $path_ok = _valid_inn_nnrpd_staging_path($headers->{Path});
        }
        push @errors, { header => 'Path', reason => 'invalid-path' }
            unless $path_ok;
    }

    my $body_error = _body_error($body);
    push @errors, { header => '(body)', reason => $body_error } if $body_error;

    return wantarray ? (!@errors, \@errors) : !@errors;
}

1;
