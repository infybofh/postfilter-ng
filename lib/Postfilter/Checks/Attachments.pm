package Postfilter::Checks::Attachments;

use strict;
use warnings;

=head1 NAME

Postfilter::Checks::Attachments - Strict MIME attachment and Base64 detection.

=head1 PURPOSE

This module protects text newsgroups from binary payloads that do not use the
historical yEnc or uuencode markers.  It recognises MIME containers, attachment
metadata, forbidden media types and long unlabelled Base64 runs.

The check is intentionally profile-aware.  It is enabled by default for text
articles and disabled by default for binary articles.  A newsmaster can change
both profiles independently in C<[article_types.TYPE.mime]>.

=head1 PGP, GNUPG AND CERTIFICATE SAFETY

Ordinary cryptographic signatures and small public-key/certificate examples
must not be mistaken for file attachments.  The default policy therefore:

=over 4

=item * allows C<multipart/signed> and the common PGP/S/MIME signature types;

=item * allows a bounded set of certificate/public-key media types;

=item * removes configured ASCII-armoured blocks from the Base64 heuristic;

=item * ignores quoted Base64 examples by default;

=item * requires both a minimum line count and decoded-byte estimate before the
heuristic can reject an article.

=back

The allowances are deliberately bounded.  An attacker cannot label a ten-megabyte
archive as a PGP signature and bypass the text policy because allowed MIME parts
and armoured blocks have independent maximum sizes.

=head1 FAILURE MODEL

Malformed multipart syntax follows C<on_malformed>.  The strict default is
C<reject>.  Setting it to C<accept> logs the problem and skips only the malformed
MIME structure; yEnc, uuencode, size, rule and other checks continue normally.

=cut

use Postfilter::Codes;
use Postfilter::Result;

my %MEDIA_GLOB_CACHE;

=head2 run($context)

Inspects one article using the MIME policy selected by its text/binary profile.
Returns a C<Postfilter::Result>.  The method never changes the article body or
headers.

=cut

# Function: run
# Purpose: Applies MIME attachment rules and the bounded Base64 heuristic.
# Parameters: $class, $context
# Operational notes: The check is normally enabled only for text articles.
sub run {
    my ($class, $context) = @_;

    if (
        exists($context->{config}{modules}{attachments})
        && !$context->{config}{modules}{attachments}
    ) {
        return _pass('Attachment checks disabled globally');
    }

    my $policy = $context->{article_type_profile}{mime} || {};
    return _pass('Attachment checks disabled for this article type')
        unless $policy->{enabled};

    my $maximum_scan_bytes = $context->limit('max_body_scan_bytes') // 0;
    my $state = {
        parts_seen => 0,
        scan_bytes_remaining => $maximum_scan_bytes > 0
            ? $maximum_scan_bytes
            : undef,
        scan_segments => [],
    };

    my $top_headers = {
        'Content-Disposition' => $context->{headers}{'Content-Disposition'} // '',
        'Content-Transfer-Encoding' =>
            $context->{headers}{'Content-Transfer-Encoding'} // '',
        'Content-Type' => $context->{headers}{'Content-Type'} // 'text/plain',
    };

    my $result = _inspect_entity(
        $context,
        $top_headers,
        $context->{body},
        $policy,
        $state,
        0,
        'top-level',
    );
    return $result if $result;

    if ($policy->{base64_heuristic_enabled}) {
        for my $segment (@{ $state->{scan_segments} }) {
            my $base64_result = _detect_large_base64_block(
                $context,
                $segment,
                $policy,
            );
            return $base64_result if $base64_result;
        }
    }

    return _pass('MIME attachment and Base64 checks passed');
}

=head2 top_level_content_type_is_managed($context)

Returns true when the top-level media type is managed by the dedicated
article-type MIME policy.  C<Postfilter::Checks::Style> uses this narrow helper
so complex containers and forbidden media reach the full MIME inspector
instead of being rejected prematurely by the historical text/plain-only check.

=cut

# Function: top_level_content_type_is_managed
# Purpose: Defers MIME containers and managed media types to the dedicated attachment check.
# Parameters: $class, $context
# Operational notes: Full recursive validation still occurs in run().
sub top_level_content_type_is_managed {
    my ($class, $context) = @_;

    # If the complete attachment-defense module was disabled globally, the
    # historical Content-Type check must remain responsible for non-text MIME
    # types.  Without this guard Style.pm would defer the decision to a module
    # that never runs, accidentally allowing multipart/application articles.
    my $modules = $context->{config}{modules} || {};
    return 0 if exists $modules->{attachments} && !$modules->{attachments};

    my $policy = $context->{article_type_profile}{mime} || {};
    return 0 unless $policy->{enabled};

    my ($media_type) = _parse_parameterised_header(
        $context->{headers}{'Content-Type'} // 'text/plain',
        'text/plain',
    );

    # Every multipart container is managed here so the module can return a
    # precise code for multipart/mixed, an unlisted subtype or malformed
    # boundary syntax.  Forbidden and explicitly allowed leaf media are also
    # deferred so they receive PF-MIME-110 rather than the older generic code 5.
    return 1 if $media_type =~ m{\Amultipart/}i;
    return 1 if _media_matches_any(
        $media_type,
        $policy->{allowed_media_types},
    );
    return 1 if _media_matches_any(
        $media_type,
        $policy->{forbidden_media_types},
    );

    return 0;
}

=head2 _inspect_entity(...)

Recursively inspects one MIME entity.  It checks disposition metadata before
parsing multipart children, enforces part/depth limits and returns bodies that
remain eligible for the Base64 heuristic.

=cut

# Function: _inspect_entity
# Purpose: Recursively validates one MIME entity and collects safe text-like bodies.
# Parameters: $context, $headers, $body, $policy, $state, $depth, $location
# Operational notes: Returns undef on success or a rejection result on failure.
sub _inspect_entity {
    my (
        $context,
        $headers,
        $body,
        $policy,
        $state,
        $depth,
        $location,
    ) = @_;

    $state->{parts_seen}++;
    my $maximum_parts = $policy->{max_mime_parts} // 100;
    return _malformed_result(
        $context,
        $policy,
        'maximum MIME part count exceeded',
        location => $location,
        parts    => $state->{parts_seen},
    ) if $state->{parts_seen} > $maximum_parts;

    my $maximum_depth = $policy->{max_mime_depth} // 8;
    return _malformed_result(
        $context,
        $policy,
        'maximum MIME nesting depth exceeded',
        depth    => $depth,
        location => $location,
    ) if $depth > $maximum_depth;

    my ($media_type, $content_parameter) = _parse_parameterised_header(
        $headers->{'Content-Type'} // 'text/plain',
        'text/plain',
    );
    my ($disposition, $disposition_parameter) = _parse_parameterised_header(
        $headers->{'Content-Disposition'} // '',
        '',
    );

    my $allowed_media = _media_matches_any(
        $media_type,
        $policy->{allowed_media_types},
    );

    my $disposition_filename = _first_parameter_value(
        $disposition_parameter,
        qr/\Afilename(?:\*.*)?\z/i,
    );
    my $content_name = _first_parameter_value(
        $content_parameter,
        qr/\Aname(?:\*.*)?\z/i,
    );
    my $has_filename = length($disposition_filename) || length($content_name);
    my $is_attachment = $disposition eq 'attachment';

    if (
        $policy->{reject_attachment_disposition}
        && ($is_attachment || ($policy->{reject_filename_parameter} && $has_filename))
        && !(
            $allowed_media
            && $policy->{allow_attachment_disposition_for_allowed_media}
        )
    ) {
        return _reject(
            111,
            disposition => $disposition,
            filename    => length($disposition_filename)
                ? $disposition_filename
                : $content_name,
            location    => $location,
            media_type  => $media_type,
        );
    }

    if ($media_type =~ m{\Amultipart/}i) {
        return _reject(
            109,
            location   => $location,
            media_type => $media_type,
        ) if $policy->{reject_multipart_mixed}
            && $media_type eq 'multipart/mixed';

        if (
            $policy->{reject_unlisted_multipart}
            && !_media_matches_any(
                $media_type,
                $policy->{allowed_multipart_types},
            )
        ) {
            return _reject(
                114,
                location   => $location,
                media_type => $media_type,
            );
        }

        my $boundary = $content_parameter->{boundary} // '';
        if (!length $boundary) {
            return _malformed_result(
                $context,
                $policy,
                'multipart entity has no boundary parameter',
                location   => $location,
                media_type => $media_type,
            );
        }

        my ($parts, $split_error) = _split_multipart_body($body, $boundary);
        if ($split_error) {
            return _malformed_result(
                $context,
                $policy,
                $split_error,
                location   => $location,
                media_type => $media_type,
            );
        }

        my $part_number = 0;
        for my $raw_part (@{$parts}) {
            $part_number++;
            my ($part_headers, $part_body, $parse_error) =
                _parse_mime_part($raw_part);

            if ($parse_error) {
                return _malformed_result(
                    $context,
                    $policy,
                    $parse_error,
                    location => "$location part $part_number",
                );
            }

            my $child_result = _inspect_entity(
                $context,
                $part_headers,
                $part_body,
                $policy,
                $state,
                $depth + 1,
                "$location part $part_number",
            );
            return $child_result if $child_result;
        }

        return;
    }

    if ($allowed_media) {
        my $maximum_allowed_bytes =
            $policy->{allowed_media_max_decoded_bytes}
            // 262_144;
        my $estimated_bytes = _estimated_decoded_bytes(
            $body,
            $headers->{'Content-Transfer-Encoding'} // '',
        );

        if ($estimated_bytes > $maximum_allowed_bytes) {
            return _reject(
                110,
                allowed_limit => $maximum_allowed_bytes,
                estimated_decoded_bytes => $estimated_bytes,
                location      => $location,
                media_type    => $media_type,
                reason        => 'allowed cryptographic MIME part exceeds size limit',
            );
        }

        # The Base64 inside a permitted signature/key/certificate part is not an
        # attachment heuristic candidate.  Its media type and bounded size have
        # already been checked explicitly above.
        return;
    }

    if (_media_matches_any($media_type, $policy->{forbidden_media_types})) {
        return _reject(
            110,
            location   => $location,
            media_type => $media_type,
        );
    }

    _add_scan_segment($state, $body);
    return;
}

=head2 _add_scan_segment($state, $body)

Adds text-like data to the Base64 heuristic while respecting the per-article
C<max_body_scan_bytes> budget.  MIME structure itself is parsed from the complete
body so a valid long multipart message is not misdiagnosed as truncated.

=cut

# Function: _add_scan_segment
# Purpose: Adds a bounded body segment to the Base64 heuristic work queue.
# Parameters: $state, $body
# Operational notes: An undefined remaining budget means unlimited scanning.
sub _add_scan_segment {
    my ($state, $body) = @_;

    if (!defined $state->{scan_bytes_remaining}) {
        push @{ $state->{scan_segments} }, $body;
        return;
    }

    return if $state->{scan_bytes_remaining} <= 0;

    my $segment = substr($body, 0, $state->{scan_bytes_remaining});
    push @{ $state->{scan_segments} }, $segment;
    $state->{scan_bytes_remaining} -= length $segment;
    return;
}

=head2 _parse_parameterised_header($value, $default)

Parses a Content-Type or Content-Disposition style value.  It supports quoted
parameter values and escaped characters without attempting to implement the
entire RFC 2231 continuation mechanism.  Unknown parameters are preserved.

=cut

# Function: _parse_parameterised_header
# Purpose: Parses a token plus semicolon-separated parameters into lowercase keys.
# Parameters: $value, $default
# Operational notes: Malformed individual parameters are ignored safely.
sub _parse_parameterised_header {
    my ($value, $default) = @_;

    $value = $default unless defined($value) && length($value);
    my @piece = _split_semicolon_fields($value // '');
    my $token = lc(shift(@piece) // $default // '');
    $token =~ s/^\s+|\s+$//g;

    my %parameter;
    for my $field (@piece) {
        my ($name, $parameter_value) = split /\s*=\s*/, $field, 2;
        next unless defined $name && defined $parameter_value;

        $name = lc $name;
        $name =~ s/^\s+|\s+$//g;
        $parameter_value =~ s/^\s+|\s+$//g;

        if (
            length($parameter_value) >= 2
            && substr($parameter_value, 0, 1) eq '"'
            && substr($parameter_value, -1, 1) eq '"'
        ) {
            $parameter_value = substr($parameter_value, 1, -1);
            $parameter_value =~ s/\\([\\"])/$1/g;
        }

        $parameter{$name} = $parameter_value;
    }

    return ($token, \%parameter);
}

=head2 _first_parameter_value($parameters, $name_pattern)

Returns the first non-empty parameter whose name matches the supplied pattern.
This recognises ordinary C<filename=> plus RFC 2231 forms such as
C<filename*=> and C<filename*0*=> without needing to decode the value.

=cut

# Function: _first_parameter_value
# Purpose: Finds ordinary or RFC 2231 attachment-name parameters.
# Parameters: $parameters, $name_pattern
# Operational notes: The encoded value is used only as attachment evidence.
sub _first_parameter_value {
    my ($parameters, $name_pattern) = @_;

    for my $name (sort keys %{$parameters}) {
        next unless $name =~ $name_pattern;
        my $value = $parameters->{$name} // '';
        return $value if length $value;
    }

    return '';
}

# Function: _split_semicolon_fields
# Purpose: Splits parameterised header fields without breaking quoted semicolons.
# Parameters: $value
# Operational notes: Backslash escapes are honoured inside double quotes.
sub _split_semicolon_fields {
    my ($value) = @_;

    my (@field, $buffer, $quoted, $escaped);
    $buffer = '';

    for my $character (split //, $value) {
        if ($escaped) {
            $buffer .= $character;
            $escaped = 0;
            next;
        }

        if ($quoted && $character eq '\\') {
            $buffer .= $character;
            $escaped = 1;
            next;
        }

        if ($character eq '"') {
            $quoted = !$quoted;
            $buffer .= $character;
            next;
        }

        if ($character eq ';' && !$quoted) {
            push @field, $buffer;
            $buffer = '';
            next;
        }

        $buffer .= $character;
    }

    push @field, $buffer;
    return @field;
}

=head2 _split_multipart_body($body, $boundary)

Splits a multipart body using boundary lines only.  Boundary-looking text in the
middle of a content line is therefore not treated as a delimiter.

=cut

# Function: _split_multipart_body
# Purpose: Extracts raw MIME parts and validates opening/closing boundary syntax.
# Parameters: $body, $boundary
# Operational notes: Returns ($parts, $error_text).
sub _split_multipart_body {
    my ($body, $boundary) = @_;

    return ([], 'multipart boundary contains CR, LF or NUL')
        if $boundary =~ /[\r\n\0]/;
    return ([], 'multipart boundary is unreasonably long')
        if length($boundary) > 200;

    my $quoted_boundary = quotemeta($boundary);
    my @line = split /(?<=\n)/, $body, -1;
    my (@parts, @current);
    my ($inside, $opened, $closed) = (0, 0, 0);

    for my $line (@line) {
        my $comparison = $line;
        $comparison =~ s/\r?\n\z//;

        if ($comparison =~ /\A--$quoted_boundary(--)?[ \t]*\z/) {
            my $is_closing = defined($1) && $1 eq '--';

            if ($inside && @current) {
                push @parts, join('', @current);
                @current = ();
            }

            $opened = 1;
            if ($is_closing) {
                $closed = 1;
                $inside = 0;
                last;
            }

            $inside = 1;
            next;
        }

        push @current, $line if $inside;
    }

    return ([], 'multipart opening boundary was not found') unless $opened;
    return ([], 'multipart closing boundary was not found') unless $closed;
    return ([], 'multipart body contains no parts') unless @parts;

    return (\@parts, undef);
}

=head2 _parse_mime_part($raw_part)

Parses MIME part headers, unfolds continuation lines and returns the remaining
body without decoding it.  Binary transfer decoding is unnecessary for policy
classification and would increase memory use.

=cut

# Function: _parse_mime_part
# Purpose: Separates and unfolds one MIME part's headers and body.
# Parameters: $raw_part
# Operational notes: Returns ($headers, $body, $error_text).
sub _parse_mime_part {
    my ($raw_part) = @_;

    my ($header_block, $body) = split /\r?\n\r?\n/, $raw_part, 2;
    return ({}, '', 'MIME part has no header/body separator')
        unless defined $body;

    my @physical_line = split /\r?\n/, $header_block, -1;
    my @logical_line;

    for my $line (@physical_line) {
        if ($line =~ /^[ \t]/ && @logical_line) {
            $line =~ s/^[ \t]+/ /;
            $logical_line[-1] .= $line;
            next;
        }
        push @logical_line, $line;
    }

    my %headers;
    for my $line (@logical_line) {
        next unless length $line;
        my ($name, $value) = split /:\s*/, $line, 2;
        return ({}, '', "malformed MIME part header '$line'")
            unless defined $name;

        # RFC-style fields may legally contain an empty value (for example,
        # "X-Foo:").  Treat the missing second split field as an empty string
        # rather than reporting the entire MIME entity as malformed.
        $value //= '';

        my $canonical = join '-', map { ucfirst lc $_ } split /-/, $name;
        $headers{$canonical} = length($headers{$canonical} // '')
            ? $headers{$canonical} . ', ' . $value
            : $value;
    }

    return (\%headers, $body, undef);
}

=head2 _media_matches_any($media_type, $patterns)

Matches case-insensitive MIME globs such as C<application/*>.  The patterns are
anchored, and regex metacharacters other than C<*> and C<?> are literal.

=cut

# Function: _media_matches_any
# Purpose: Tests one normalised MIME type against configured shell-style globs.
# Parameters: $media_type, $patterns
# Operational notes: Compiled matchers are cached for the nnrpd process lifetime.
sub _media_matches_any {
    my ($media_type, $patterns) = @_;
    return 0 unless ref($patterns) eq 'ARRAY';

    for my $pattern (@{$patterns}) {
        next unless defined($pattern) && length($pattern);
        my $cache_key = lc $pattern;

        if (!exists $MEDIA_GLOB_CACHE{$cache_key}) {
            my $regex = quotemeta($cache_key);
            $regex =~ s/\\\*/.*/g;
            $regex =~ s/\\\?/./g;
            $MEDIA_GLOB_CACHE{$cache_key} = qr/\A$regex\z/i;
        }

        return 1 if $media_type =~ $MEDIA_GLOB_CACHE{$cache_key};
    }

    return 0;
}

=head2 _estimated_decoded_bytes($body, $encoding)

Estimates decoded payload size without allocating a decoded copy.  The estimate
is exact enough for the configured safety ceiling and deliberately conservative
for unknown encodings.

=cut

# Function: _estimated_decoded_bytes
# Purpose: Estimates the decoded size of a permitted cryptographic MIME part.
# Parameters: $body, $encoding
# Operational notes: Base64 whitespace is ignored; other encodings use raw bytes.
sub _estimated_decoded_bytes {
    my ($body, $encoding) = @_;

    $encoding = lc($encoding // '');
    $encoding =~ s/^\s+|\s+$//g;

    if ($encoding eq 'base64') {
        my $compact = $body;
        $compact =~ s/\s+//g;
        my $padding = $compact =~ /(=*)\z/ ? length($1) : 0;
        my $estimated = int(length($compact) * 3 / 4) - $padding;
        return $estimated > 0 ? $estimated : 0;
    }

    return length $body;
}

=head2 _detect_large_base64_block(...)

Finds long contiguous Base64-looking runs.  A rejection requires both the
configured number of lines and estimated decoded bytes.  Small examples,
ordinary signatures and quoted material therefore remain accepted.

=cut

# Function: _detect_large_base64_block
# Purpose: Detects unlabelled large Base64 payloads while excluding safe armoured blocks.
# Parameters: $context, $body, $policy
# Operational notes: Returns undef on no match or PF-BODY-112 on a probable attachment.
sub _detect_large_base64_block {
    my ($context, $body, $policy) = @_;

    my $scan = _remove_allowed_armoured_blocks($body, $policy);
    my @line = split /\r?\n/, $scan, -1;

    my $minimum_lines = $policy->{base64_min_contiguous_lines} // 12;
    my $minimum_line_length = $policy->{base64_min_line_length} // 60;
    my $maximum_line_length = $policy->{base64_max_line_length} // 100;
    my $minimum_decoded_bytes = $policy->{base64_min_decoded_bytes} // 4_096;
    my $single_line_minimum =
        $policy->{base64_single_line_min_decoded_bytes}
        // 8_192;

    my ($run_lines, $encoded_characters) = (0, 0);

    for my $line (@line) {
        if ($policy->{base64_ignore_quoted_lines} && $line =~ /^\s*>/) {
            my $result = _evaluate_base64_run(
                $run_lines,
                $encoded_characters,
                $minimum_lines,
                $minimum_decoded_bytes,
            );
            return _reject(112, %{$result}) if $result;
            ($run_lines, $encoded_characters) = (0, 0);
            next;
        }

        if ($policy->{base64_ignore_indented_lines} && $line =~ /^[ \t]+/) {
            my $result = _evaluate_base64_run(
                $run_lines,
                $encoded_characters,
                $minimum_lines,
                $minimum_decoded_bytes,
            );
            return _reject(112, %{$result}) if $result;
            ($run_lines, $encoded_characters) = (0, 0);
            next;
        }

        my $candidate = $line;
        $candidate =~ s/[ \t]+//g;
        my $length = length $candidate;
        my $base64_alphabet = $candidate =~ /\A[A-Za-z0-9+\/_-]+={0,2}\z/;

        # A single extremely long encoded line is a common way to avoid a
        # line-count heuristic.  Apply a separate decoded-size threshold before
        # the ordinary wrapped-line logic.  Zero disables this special case.
        if ($base64_alphabet && $single_line_minimum > 0) {
            my $unpadded = $candidate;
            $unpadded =~ s/=+\z//;
            my $single_line_decoded = int(length($unpadded) * 3 / 4);
            if ($single_line_decoded >= $single_line_minimum) {
                return _reject(
                    112,
                    base64_lines => 1,
                    estimated_decoded_bytes => $single_line_decoded,
                );
            }
        }

        my $long_enough = $length >= $minimum_line_length;
        my $not_too_long = $maximum_line_length <= 0
            || $length <= $maximum_line_length;

        if ($base64_alphabet && $long_enough && $not_too_long) {
            $run_lines++;
            $candidate =~ s/=+\z//;
            $encoded_characters += length $candidate;
            next;
        }

        # Permit one shorter final Base64 line after a real run.  This mirrors
        # conventional encoders whose last line is shorter than the fixed width.
        if (
            $run_lines > 0
            && $base64_alphabet
            && $length >= 4
            && $not_too_long
        ) {
            $run_lines++;
            $candidate =~ s/=+\z//;
            $encoded_characters += length $candidate;
        }

        my $result = _evaluate_base64_run(
            $run_lines,
            $encoded_characters,
            $minimum_lines,
            $minimum_decoded_bytes,
        );
        return _reject(112, %{$result}) if $result;

        ($run_lines, $encoded_characters) = (0, 0);
    }

    my $result = _evaluate_base64_run(
        $run_lines,
        $encoded_characters,
        $minimum_lines,
        $minimum_decoded_bytes,
    );
    return _reject(112, %{$result}) if $result;

    return;
}

# Function: _evaluate_base64_run
# Purpose: Applies the line-count and decoded-size thresholds to one completed run.
# Parameters: $line_count, $encoded_characters, $minimum_lines, $minimum_decoded_bytes
# Operational notes: Returns a details hash or undef.
sub _evaluate_base64_run {
    my (
        $line_count,
        $encoded_characters,
        $minimum_lines,
        $minimum_decoded_bytes,
    ) = @_;

    return if $line_count < $minimum_lines;

    my $estimated_decoded_bytes = int($encoded_characters * 3 / 4);
    return if $estimated_decoded_bytes < $minimum_decoded_bytes;

    return {
        base64_lines           => $line_count,
        estimated_decoded_bytes => $estimated_decoded_bytes,
    };
}

=head2 _remove_allowed_armoured_blocks($body, $policy)

Removes bounded ASCII-armoured blocks before heuristic analysis.  Only configured
labels are removed, and only when the complete BEGIN/END pair fits within the
configured byte ceiling.

=cut

# Function: _remove_allowed_armoured_blocks
# Purpose: Excludes bounded PGP/GnuPG/certificate armour from Base64 heuristics.
# Parameters: $body, $policy
# Operational notes: Oversized or unterminated armour remains visible to detection.
sub _remove_allowed_armoured_blocks {
    my ($body, $policy) = @_;

    my %allowed = map { uc($_) => 1 }
        @{ $policy->{allowed_armored_block_types} // [] };
    return $body unless %allowed;

    my $maximum_bytes = $policy->{armored_block_max_bytes} // 262_144;
    return $body if $maximum_bytes <= 0;

    # Scan the body exactly once, one physical line at a time.  The previous
    # regular-expression implementation searched from every BEGIN marker to a
    # possible END marker and could revisit the same bytes repeatedly when an
    # attacker supplied many unterminated BEGIN lines.  This state machine keeps
    # at most one bounded candidate block and therefore runs in O(n) time.
    my $result = '';
    my $candidate = '';
    my $candidate_label;
    my $offset = 0;
    my $body_length = length $body;

    while ($offset < $body_length) {
        my $newline = index($body, "\n", $offset);
        my $line_end = $newline >= 0 ? $newline + 1 : $body_length;
        my $line = substr($body, $offset, $line_end - $offset);
        $offset = $line_end;

        if (defined $candidate_label) {
            $candidate .= $line;

            if (_armour_marker_label($line, 'END') eq $candidate_label) {
                if (length($candidate) <= $maximum_bytes) {
                    $result .= "\n";
                }
                else {
                    $result .= $candidate;
                }

                $candidate = '';
                undef $candidate_label;
                next;
            }

            if (length($candidate) > $maximum_bytes) {
                # The block is too large to receive the cryptographic-material
                # exception.  Flush it unchanged and resume normal scanning.
                $result .= $candidate;
                $candidate = '';
                undef $candidate_label;
            }

            next;
        }

        my $begin_label = _armour_marker_label($line, 'BEGIN');
        if (length($begin_label) && $allowed{$begin_label}) {
            $candidate = $line;
            $candidate_label = $begin_label;
            next;
        }

        $result .= $line;
    }

    # An unterminated block is not exempted from Base64 inspection.  Preserve
    # it in the scan copy so the normal heuristic can evaluate its payload.
    $result .= $candidate if defined $candidate_label;

    return $result;
}

=head2 _armour_marker_label($line, $kind)

Returns the upper-case label from one complete ASCII-armour marker line.  The
parser accepts horizontal whitespace after BEGIN/END and ignores CRLF/LF line
endings.  Non-marker lines return an empty string.

=cut

# Function: _armour_marker_label
# Purpose: Parses a single BEGIN or END ASCII-armour marker without body-wide regexes.
# Parameters: $line, $kind
# Operational notes: The operation is bounded by the length of one physical line.
sub _armour_marker_label {
    my ($line, $kind) = @_;

    return '' unless defined $line && defined $kind;

    my $normalised = $line;
    $normalised =~ s/\r?\n\z//;
    $normalised = uc $normalised;

    my $prefix = '-----' . uc($kind) . ' ';
    my $suffix = '-----';
    return '' unless index($normalised, $prefix) == 0;
    return '' unless length($normalised) > length($prefix) + length($suffix);
    return '' unless substr($normalised, -length($suffix)) eq $suffix;

    my $label = substr(
        $normalised,
        length($prefix),
        length($normalised) - length($prefix) - length($suffix),
    );
    $label =~ s/^[ \t]+|[ \t]+$//g;

    return $label;
}

# Function: _malformed_result
# Purpose: Applies the configured fail-open/fail-closed policy for malformed MIME syntax.
# Parameters: $context, $policy, $reason, %details
# Operational notes: Fail-open emits news.err and returns undef.
sub _malformed_result {
    my ($context, $policy, $reason, %details) = @_;

    my $action = $policy->{on_malformed} // 'reject';
    if ($action eq 'accept') {
        $context->{logger}->error(
            'malformed_mime_skipped',
            reason => $reason,
            %details,
        );
        push @{ $context->{notes} }, "malformed_mime=$reason";
        return;
    }

    return _reject(113, reason => $reason, %details);
}

# Function: _pass
# Purpose: Constructs the normal successful result for this check.
# Parameters: $message
# Operational notes: No persistent state is changed.
sub _pass {
    my ($message) = @_;

    return Postfilter::Result->pass(
        code    => 'PF-MIME-000',
        legacy  => 0,
        message => $message,
    );
}

# Function: _reject
# Purpose: Constructs a rejection while retaining the numeric compatibility code.
# Parameters: $numeric_code, %details
# Operational notes: The orchestrator resolves audit/enforce and saving policy.
sub _reject {
    my ($numeric_code, %details) = @_;
    my ($code, $message) = Postfilter::Codes->lookup($numeric_code);

    return Postfilter::Result->reject(
        code    => $code,
        legacy  => $numeric_code,
        message => $message,
        %details,
    );
}

1;
