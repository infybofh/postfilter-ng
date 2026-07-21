package Postfilter::Codes;

use strict;
use warnings;

=head1 NAME

Postfilter::Codes - Stable symbolic and historical numeric rejection codes.

=head1 DESCRIPTION

The numeric values are retained so existing logs, policies and operator habits
remain useful.  New code and reports use a descriptive C<PF-CATEGORY-NNN> value.
A numeric code is never reassigned to a different meaning.

The table is deliberately written one entry per line.  It is longer than a
compressed array, but an operator can review a code without counting commas or
running a helper script.

=cut

my %MESSAGE = (
      0 => 'Message successfully sent',
      1 => 'Control messages are forbidden',
      2 => 'Forbidden crosspost',
      3 => 'You cannot approve messages',
      4 => 'Invalid Distribution header',
      5 => 'Invalid Content-Type',
      6 => 'Too many groups in Newsgroups',
      7 => 'Too many groups in Followup-To',
      8 => 'Missing Followup-To header',
      9 => 'The body is too large',
     10 => 'Difference between crossposts and followups is too large',
     11 => 'Re: without References',
     12 => 'Line too long',
     13 => 'Too many quoted lines',
     14 => 'Too many blank lines',
     15 => 'Too many empty lines',
     16 => 'HTML content is forbidden',
     17 => 'Nonexistent group',
     18 => 'Nonexistent group in Followup-To',
     19 => 'Date is too far in the future',
     20 => 'Invalid Path',
     21 => 'A header is too long',
     22 => 'Mail headers are forbidden',
     23 => 'Headers are too large',
     24 => 'Invalid In-Reply-To',
     25 => 'Too many hierarchies',
     26 => 'Too many hierarchies in Followup-To',
     27 => 'Syntax error in badwords configuration',
     28 => 'Badword in Subject',
     29 => 'Badword in body',
     30 => 'Multipost',
     31 => 'Your IP has sent too many articles',
     32 => 'Your domain has sent too many articles',
     33 => 'Your userid has sent too many articles',
     34 => 'Banlist',
     35 => 'Syntax error in banlist configuration',
     36 => 'Database connection error',
     37 => 'Unable to load active file',
     38 => 'Unable to load badwords configuration',
     39 => 'Unable to load banlist configuration',
     40 => 'Unable to open persistent storage',
     41 => 'Unable to save article',
     42 => 'Unable to run innconfval',
     43 => 'Unable to load main configuration',
     44 => 'Unable to write audit event',
     45 => 'Database expiry error',
     46 => 'Database spool error',
     47 => 'Default action set to rejection',
     48 => 'Server closed for posting',
     49 => 'Excessive score in banlist',
     50 => 'TOR is forbidden',
     51 => 'Supersedes, Replaces and Cancel are forbidden',
     52 => 'UUEncoded binaries are forbidden',
     53 => 'Forged system header',
     54 => 'Permanently closed group',
     55 => 'Unable to load internal module',
     56 => 'Forbidden due to DNSBL listing',
     57 => 'Message too big',
     58 => 'Message too old',
     59 => 'Unable to read public suffix data',
     60 => 'Banned domain in body (SURBL)',
     61 => 'Banned domain in body (URIBL)',
     62 => 'yEnc contents are forbidden',
     63 => 'Message rejected by a custom rule',
     64 => 'Too many errors for your IP',
     65 => 'Too many errors for your domain',
     66 => 'Too many errors for your userid',
     67 => 'Too many errors for your IP in a short period',
     68 => 'Too many errors for your domain in a short period',
     69 => 'Too many errors for your userid in a short period',
     70 => 'Too many messages for your IP in a short period',
     71 => 'Too many messages for your domain in a short period',
     72 => 'Too many messages for your userid in a short period',
     73 => 'Too many bytes for your IP in a short period',
     74 => 'Too many bytes for your domain in a short period',
     75 => 'Too many bytes for your userid in a short period',
     76 => 'Too many bytes for your IP',
     77 => 'Too many bytes for your domain',
     78 => 'Too many bytes for your userid',
     79 => 'Too many newsgroups for your IP in a short period',
     80 => 'Too many newsgroups for your domain in a short period',
     81 => 'Too many newsgroups for your userid in a short period',
     82 => 'Too many newsgroups for your IP',
     83 => 'Too many newsgroups for your domain',
     84 => 'Too many newsgroups for your userid',
     85 => 'Too many followups for your IP in a short period',
     86 => 'Too many followups for your domain in a short period',
     87 => 'Too many followups for your userid in a short period',
     88 => 'Too many followups for your IP',
     89 => 'Too many followups for your domain',
     90 => 'Too many followups for your userid',
     91 => 'Article rejected by sender request',
     92 => 'Syntax error in main configuration',
     93 => 'Syntax error in access configuration',
     94 => 'Syntax error in rules configuration',
     95 => 'Crossposting between text and binary groups is forbidden',
     96 => 'Text article body exceeds the configured text limit',
     97 => 'Text article headers exceed the configured text limit',
     98 => 'Text article total size exceeds the configured text limit',
     99 => 'Binary article body exceeds the configured binary limit',
    100 => 'Binary article headers exceed the configured binary limit',
    101 => 'Binary article total size exceeds the configured binary limit',
    102 => 'Binary payload is forbidden by the selected article policy',
    103 => 'Unable to determine a valid article type policy',
    104 => 'Forbidden or invalid character in header',
    105 => 'Unable to load per-group user database',
    106 => 'Sender is not authorized for this group',
    107 => 'Unable to store local Distribution state',
    108 => 'Invalid Distribution value',
    109 => 'multipart/mixed is forbidden in text groups',
    110 => 'MIME media type is forbidden in text groups',
    111 => 'MIME attachment metadata is forbidden in text groups',
    112 => 'Probable Base64 attachment is forbidden in text groups',
    113 => 'Malformed MIME structure in text article',
    114 => 'Unapproved multipart container is forbidden in text groups',
);

my %SPECIAL_SYMBOLIC = (
    104 => 'PF-HEADER-104',
    105 => 'PF-AUTH-105',
    106 => 'PF-AUTH-106',
    107 => 'PF-DB-107',
    108 => 'PF-GROUP-108',
    109 => 'PF-MIME-109',
    110 => 'PF-MIME-110',
    111 => 'PF-MIME-111',
    112 => 'PF-BODY-112',
    113 => 'PF-MIME-113',
    114 => 'PF-MIME-114',
);

my %CATEGORY = (
      0 => 'INTERNAL',
      1 => 'HEADER',
      2 => 'GROUP',
      3 => 'HEADER',
      4 => 'GROUP',
      5 => 'MIME',
      6 => 'GROUP',
      7 => 'GROUP',
      8 => 'GROUP',
      9 => 'BODY',
     10 => 'GROUP',
     11 => 'HEADER',
     12 => 'BODY',
     13 => 'BODY',
     14 => 'BODY',
     15 => 'BODY',
     16 => 'BODY',
     17 => 'GROUP',
     18 => 'GROUP',
     19 => 'DATE',
     20 => 'HEADER',
     21 => 'HEADER',
     22 => 'HEADER',
     23 => 'HEADER',
     24 => 'HEADER',
     25 => 'GROUP',
     26 => 'GROUP',
     27 => 'CONFIG',
     28 => 'RULE',
     29 => 'RULE',
     30 => 'RATE',
     31 => 'RATE',
     32 => 'RATE',
     33 => 'RATE',
     34 => 'RULE',
     35 => 'CONFIG',
     36 => 'DB',
     37 => 'GROUP',
     38 => 'CONFIG',
     39 => 'CONFIG',
     40 => 'DB',
     41 => 'SAVE',
     42 => 'CONFIG',
     43 => 'CONFIG',
     44 => 'DB',
     45 => 'DB',
     46 => 'DB',
     47 => 'POLICY',
     48 => 'POLICY',
     49 => 'RULE',
     50 => 'TOR',
     51 => 'HEADER',
     52 => 'BODY',
     53 => 'HEADER',
     54 => 'GROUP',
     55 => 'INTERNAL',
     56 => 'RBL',
     57 => 'BODY',
     58 => 'DATE',
     59 => 'CONFIG',
     60 => 'URIBL',
     61 => 'URIBL',
     62 => 'BODY',
     63 => 'RULE',
     64 => 'RATE',
     65 => 'RATE',
     66 => 'RATE',
     67 => 'RATE',
     68 => 'RATE',
     69 => 'RATE',
     70 => 'RATE',
     71 => 'RATE',
     72 => 'RATE',
     73 => 'RATE',
     74 => 'RATE',
     75 => 'RATE',
     76 => 'RATE',
     77 => 'RATE',
     78 => 'RATE',
     79 => 'RATE',
     80 => 'RATE',
     81 => 'RATE',
     82 => 'RATE',
     83 => 'RATE',
     84 => 'RATE',
     85 => 'RATE',
     86 => 'RATE',
     87 => 'RATE',
     88 => 'RATE',
     89 => 'RATE',
     90 => 'RATE',
     91 => 'RULE',
     92 => 'CONFIG',
     93 => 'CONFIG',
     94 => 'CONFIG',
     95 => 'GROUP',
     96 => 'BODY',
     97 => 'HEADER',
     98 => 'BODY',
     99 => 'BODY',
    100 => 'HEADER',
    101 => 'BODY',
    102 => 'BODY',
    103 => 'POLICY',
    109 => 'MIME',
    110 => 'MIME',
    111 => 'MIME',
    112 => 'BODY',
    113 => 'MIME',
    114 => 'MIME',
);


=head2 lookup($numeric_code)

Returns C<($symbolic_code, $message)>.  Unknown codes remain visible as
C<PF-INTERNAL-NNN> instead of causing an exception inside the error path.

=cut

# Function: lookup
# Purpose: Maps a historical numeric code to its stable symbolic code and message.
# Parameters: $class, $numeric_code
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub lookup {
    my ($class, $numeric_code) = @_;

    my $message = exists $MESSAGE{$numeric_code}
        ? $MESSAGE{$numeric_code}
        : "Unknown historical error $numeric_code";

    my $symbolic = $SPECIAL_SYMBOLIC{$numeric_code};
    if (!defined $symbolic) {
        my $category = $CATEGORY{$numeric_code} // 'INTERNAL';
        $symbolic = sprintf('PF-%s-%03d', $category, $numeric_code);
    }

    return ($symbolic, $message);
}

# Function: message
# Purpose: Returns the default human-readable message for one historical code.
# Parameters: $class, $numeric_code
# Operational notes: No persistent external state is changed.
sub message {
    my ($class, $numeric_code) = @_;
    my (undef, $message) = $class->lookup($numeric_code);
    return $message;
}

# Function: code
# Purpose: Returns the stable symbolic code for one historical numeric code.
# Parameters: $class, $numeric_code
# Operational notes: No persistent external state is changed.
sub code {
    my ($class, $numeric_code) = @_;
    my ($code) = $class->lookup($numeric_code);
    return $code;
}

# Function: all
# Purpose: Returns the complete historical-to-symbolic error-code mapping.
# Parameters: No positional parameters, or arguments are read directly by the command wrapper.
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub all {
    my %all;
    for my $numeric_code (sort { $a <=> $b } keys %MESSAGE) {
        my ($code, $message) = __PACKAGE__->lookup($numeric_code);
        $all{$numeric_code} = {
            code    => $code,
            message => $message,
        };
    }
    return \%all;
}

1;
