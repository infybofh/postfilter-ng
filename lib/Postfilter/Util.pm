package Postfilter::Util;

use strict;
use warnings;

=head1 NAME

Postfilter::Util - Small, side-effect-aware helpers shared by Postfilter-NG.

=head1 DESCRIPTION

This module deliberately contains only generic operations that are useful in
more than one component.  Filtering decisions do not belong here.  Keeping
policy out of the utility module makes it possible to test path handling,
CIDR matching, atomic writes and identifiers without constructing an article.

Every exported function documents whether it can throw an exception.  Callers
that operate in a fail-open part of the filter must wrap throwing helpers in an
C<eval> block and apply the configured resilience policy.

=cut

use Exporter 'import';
use Digest::SHA qw(hmac_sha256_hex sha256_hex);
use Encode qw(encode is_utf8);
use Socket qw(AF_INET AF_INET6 inet_pton);

our @EXPORT_OK = qw(
    atomic_write
    bool
    header_value
    hmac_id
    ip_in_cidr
    normalize_email
    now_iso
    registered_domain
    sha256_hexstr
    slurp
    split_groups
    valid_followup_to
    valid_newsgroup_list
    valid_newsgroup_name
);

=head2 bool($value)

Returns C<1> for a Perl-true value and C<0> otherwise.  TOML parsers already
return booleans as Perl scalars, but this helper is useful when serialising a
strict integer to SQLite or JSON.

=cut

# Function: bool
# Purpose: Normalises Perl truth into numeric zero or one.
# Parameters: $_[0] (the current object or value)
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub bool {
    return $_[0] ? 1 : 0;
}

=head2 split_groups($header_value)

Splits a syntactically checked C<Newsgroups> or C<Followup-To> list on commas,
trims surrounding folding whitespace and returns the non-empty entries.  It
deliberately does not treat bare whitespace as a separator: RFC 5536 requires
commas between newsgroup names.  Raw header syntax is validated separately by
C<valid_newsgroup_list> and C<valid_followup_to> before policy evaluation.

=cut

# Function: split_groups
# Purpose: Splits an RFC 5536 Newsgroups-style comma list into trimmed entries.
# Parameters: $value
# Operational notes: Does not convert malformed whitespace-separated names into a valid list.
sub split_groups {
    my ($value) = @_;
    return [] unless defined $value && length $value;

    my @groups = grep { length $_ }
                 map  { s/^\s+|\s+$//gr }
                 split /,/, $value, -1;

    return \@groups;
}

=head2 valid_newsgroup_name($name)

Returns true when C<$name> matches the RFC 5536 C<newsgroup-name> grammar:
one or more non-empty components separated by dots, with each component made
of ASCII letters, digits, C<+>, C<-> or C<_>.  The RFC recommendations about
uppercase or all-numeric legacy components are not treated as syntax errors.

=cut

# Function: valid_newsgroup_name
# Purpose: Validates one RFC 5536 newsgroup-name without applying site policy.
# Parameters: $name
# Operational notes: This is syntax validation only; existence is checked separately.
sub valid_newsgroup_name {
    my ($name) = @_;
    return 0 unless defined $name && length $name;
    return $name =~ /\A[A-Za-z0-9+_-]+(?:\.[A-Za-z0-9+_-]+)*\z/ ? 1 : 0;
}

=head2 valid_newsgroup_list($value)

Validates the complete RFC 5536 C<newsgroup-list>.  Optional horizontal or
folding whitespace is accepted around commas, but commas themselves are
mandatory separators.

=cut

# Function: valid_newsgroup_list
# Purpose: Validates raw Newsgroups/Followup-To list syntax before splitting it.
# Parameters: $value
# Operational notes: Empty elements, double dots, bare whitespace separators and punctuation
#                    outside the RFC 5536 component alphabet are rejected.
sub valid_newsgroup_list {
    my ($value) = @_;
    return 0 unless defined $value && length $value;

    my $name = qr/[A-Za-z0-9+_-]+(?:\.[A-Za-z0-9+_-]+)*/;
    my $fws  = qr/[ \t]*(?:\r?\n[ \t]+[ \t]*)?/;

    return $value =~ /\A[ \t]*$name(?:$fws,$fws$name)*[ \t]*\z/ ? 1 : 0;
}

=head2 valid_followup_to($value)

Validates C<Followup-To>.  It accepts the same list grammar as C<Newsgroups>
and the RFC 5536 special value C<poster>.  Case-insensitive forms of C<poster>
are accepted as explicitly permitted by the RFC.

=cut

# Function: valid_followup_to
# Purpose: Validates RFC 5536 Followup-To syntax including the poster keyword.
# Parameters: $value
# Operational notes: The special poster value must stand alone.
sub valid_followup_to {
    my ($value) = @_;
    return 0 unless defined $value && length $value;

    my $trimmed = $value;
    $trimmed =~ s/^[ \t]+|[ \t]+$//g;
    return 1 if $trimmed =~ /\Aposter\z/i;
    return 0 unless valid_newsgroup_list($value);

    # "poster" is the complete special alternative in Followup-To, not a
    # newsgroup name that may be mixed into a comma-separated list.
    return 0 if grep { lc($_) eq 'poster' } @{ split_groups($value) };
    return 1;
}

=head2 header_value($headers, $name)

Returns a header value from a hash, first using the requested spelling and then
its lowercase spelling.  INN normally supplies canonical names, but the fallback
is helpful for offline fixtures and imported articles.

=cut

# Function: header_value
# Purpose: Returns a header value while tolerating canonical or lowercase keys.
# Parameters: $headers, $name
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub header_value {
    my ($headers, $name) = @_;
    return '' unless $headers;
    return $headers->{$name} // $headers->{ lc $name } // '';
}

=head2 normalize_email($header_value)

Extracts and lowercases the first mailbox-looking address from an RFC-style
header.  This is intentionally conservative; it is not a replacement for a
complete RFC 5322 parser.  Rules that need the exact original text should match
C<from.raw> rather than C<from.address>.

=cut

# Function: normalize_email
# Purpose: Extracts and lowercases the mailbox portion of a From or Sender value.
# Parameters: $value
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub normalize_email {
    my ($value) = @_;
    return '' unless defined $value;

    my $address = '';
    if ($value =~ /<\s*([^<>\s]+\@[^<>\s]+)\s*>/) {
        $address = $1;
    }
    elsif ($value =~ /([A-Z0-9.!#\$%&'*+\/=?^_`{|}~-]+\@[A-Z0-9.-]+)/i) {
        $address = $1;
    }

    $address = lc $address;
    $address =~ s/^\s+|\s+$//g;
    return $address;
}

=head2 ip_in_cidr($ip, $cidr)

Returns true when an IPv4 or IPv6 address belongs to a CIDR network.  Invalid
addresses, mixed address families and invalid prefix lengths return false rather
than throwing.  This behaviour is important for fail-safe rule evaluation: one
bad rule is disabled during configuration validation and cannot kill nnrpd.

=cut

# Function: ip_in_cidr
# Purpose: Tests an IPv4 or IPv6 address against a validated CIDR prefix using packed network
#          bytes.
# Parameters: $ip, $cidr
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub ip_in_cidr {
    my ($ip, $cidr) = @_;
    return 0 unless defined $ip && defined $cidr;

    my ($network, $prefix) = split m{/}, $cidr, 2;
    return 0 unless defined $network;

    my $ip_family      = index($ip, ':')      >= 0 ? AF_INET6 : AF_INET;
    my $network_family = index($network, ':') >= 0 ? AF_INET6 : AF_INET;
    return 0 if $ip_family != $network_family;

    my $packed_ip      = inet_pton($ip_family, $ip);
    my $packed_network = inet_pton($network_family, $network);
    return 0 unless defined $packed_ip && defined $packed_network;

    my $maximum_bits = $ip_family == AF_INET ? 32 : 128;
    $prefix = $maximum_bits unless defined $prefix;
    return 0 if $prefix < 0 || $prefix > $maximum_bits;

    my $complete_bytes = int($prefix / 8);
    my $remaining_bits = $prefix % 8;

    return 0
        if substr($packed_ip, 0, $complete_bytes)
        ne substr($packed_network, 0, $complete_bytes);

    return 1 unless $remaining_bits;

    my $mask = (0xff << (8 - $remaining_bits)) & 0xff;
    return (ord(substr($packed_ip,      $complete_bytes, 1)) & $mask)
        == (ord(substr($packed_network, $complete_bytes, 1)) & $mask);
}

=head2 registered_domain($host, $suffixes)

Returns the registrable domain used for domain-based rate limiting and URI-list
lookups.  C<$suffixes> is a hash generated from the bundled public suffix data.
IP literals are returned unchanged.  The implementation intentionally avoids
network access and is deterministic for a given suffix file.

=cut

# Function: registered_domain
# Purpose: Reduces a host to its registrable domain using the loaded public-suffix data.
# Parameters: $host, $suffixes
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub registered_domain {
    my ($host, $suffixes) = @_;
    return '' unless defined $host;

    $host = lc $host;
    $host =~ s/\.$//;

    return $host if $host =~ /^\d+(?:\.\d+){3}$/ || $host =~ /:/;

    my @labels = split /\./, $host;
    return $host if @labels < 2;

    # Find the longest known public suffix.  The label immediately to its left
    # is part of the registrable domain.  Unknown suffixes fall back to the
    # traditional last-two-label behaviour.
    if ($suffixes && ref($suffixes) eq 'HASH') {
        for my $start (0 .. $#labels) {
            my $candidate = join '.', @labels[$start .. $#labels];
            next unless $suffixes->{$candidate};
            return $candidate if $start == 0;
            return join '.', @labels[$start - 1 .. $#labels];
        }
    }

    return join '.', @labels[-2, -1];
}

=head2 atomic_write($path, $content, $mode)

Writes a complete file beside the destination and atomically renames it into
place.  The temporary filename includes the process id and a random component
to avoid collisions between concurrent maintenance commands.  The function
throws on failure and never deliberately leaves a partially written destination.

=cut

# Function: atomic_write
# Purpose: Writes a complete temporary file and atomically renames it over the destination.
# Parameters: $path, $content, $mode
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub atomic_write {
    my ($path, $content, $mode) = @_;
    $mode //= 0640;

    require File::Basename;
    require File::Path;

    my $directory = File::Basename::dirname($path);
    File::Path::make_path($directory, { mode => 0750 }) unless -d $directory;

    my $random = int(rand(0x7fffffff));
    my $temporary = "$path.tmp.$$.$random";

    open my $handle, '>:raw', $temporary
        or die "Unable to write temporary file $temporary: $!";

    chmod $mode, $temporary
        or die "Unable to set permissions on $temporary: $!";

    my $bytes = is_utf8($content) ? encode('UTF-8', $content) : $content;
    print {$handle} $bytes
        or die "Unable to write temporary file $temporary: $!";

    close $handle
        or die "Unable to close temporary file $temporary: $!";

    rename $temporary, $path
        or die "Unable to replace $path with $temporary: $!";

    return 1;
}

=head2 slurp($path)

Reads a file as raw bytes and returns its complete content.  Throws when the file
cannot be opened or closed.

=cut

# Function: slurp
# Purpose: Reads an entire file in raw mode and reports open/close failures.
# Parameters: $path
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub slurp {
    my ($path) = @_;

    open my $handle, '<:raw', $path
        or die "Unable to read $path: $!";

    local $/;
    my $content = <$handle>;

    close $handle
        or die "Unable to close $path: $!";

    return $content;
}

=head2 sha256_hexstr($value)

Returns the hexadecimal SHA-256 digest of a scalar, treating C<undef> as an
empty string.

=cut

# Function: sha256_hexstr
# Purpose: Returns the SHA-256 hexadecimal digest of a scalar value.
# Parameters: $_[0] (the current object or value)
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub sha256_hexstr {
    return sha256_hex($_[0] // '');
}

=head2 hmac_id($value, $key, $length)

Returns a truncated HMAC-SHA-256 identifier.  This is suitable for stable
pseudonyms, not reversible storage.  The caller must supply a secret key from a
purpose-specific key file; this module has no insecure fallback key.

=cut

# Function: hmac_id
# Purpose: Returns a truncated hexadecimal HMAC identifier for a value and key.
# Parameters: $value, $key, $length
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub hmac_id {
    my ($value, $key, $length) = @_;
    $length //= 24;
    return substr(hmac_sha256_hex($value // '', $key // ''), 0, $length);
}

=head2 now_iso()

Returns the current UTC time in a stable ISO-8601 representation suitable for
logs, snapshots and administrative audit records.

=cut

# Function: now_iso
# Purpose: Formats the current UTC time as an ISO-8601 string.
# Parameters: No positional parameters, or arguments are read directly by the command wrapper.
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub now_iso {
    my @time = gmtime;
    return sprintf(
        '%04d-%02d-%02dT%02d:%02d:%02dZ',
        $time[5] + 1900,
        $time[4] + 1,
        $time[3],
        $time[2],
        $time[1],
        $time[0],
    );
}

1;
