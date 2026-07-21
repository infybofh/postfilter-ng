package Postfilter::Crypto;

use strict;
use warnings;

=head1 NAME

Postfilter::Crypto - Purpose-separated HMAC identifiers and reversible tokens.

=head1 SECURITY MODEL

Postfilter-NG uses two different primitives for two different promises:

=over 4

=item * HMAC-SHA-256

Creates a stable pseudonym.  It is not reversible and is suitable for reports
where the administrator only needs to correlate repeated values.

=item * AES-256-CBC plus HMAC-SHA-256 (encrypt-then-MAC)

Creates a reversible token for administrators who need to recover the original
TOR endpoint or another protected value.  The authentication tag covers the
format version, purpose string, IV and ciphertext.  A token is rejected before
decryption when the tag is wrong.

=back

Every feature has its own key file.  The installer always creates all defined
keys from C</dev/urandom>, even when the corresponding feature is disabled.  The
runtime never substitutes a hardcoded emergency key.

=cut

use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256);
use MIME::Base64 qw(decode_base64url encode_base64url);

# Function: new
# Purpose: Constructs the stateless cryptographic helper with an optional logger.
# Parameters: $class, %arguments
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub new {
    my ($class, %arguments) = @_;
    return bless { logger => $arguments{logger} }, $class;
}

=head2 load_key($path, $minimum_bytes)

Reads a key as raw bytes and derives a fixed 256-bit working key with SHA-256.
The derivation allows the installer to generate longer key files while keeping
cryptographic APIs on a fixed key size.  The function throws if the file is
missing, unreadable or shorter than the configured minimum.

=cut

# Function: load_key
# Purpose: Reads a purpose-specific key file, enforces its minimum size, and derives a fixed
#          256-bit key.
# Parameters: $self, $path, $minimum_bytes
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub load_key {
    my ($self, $path, $minimum_bytes) = @_;
    $minimum_bytes //= 32;

    die "No key file was configured\n"
        unless defined $path && length $path;

    open my $handle, '<:raw', $path
        or die "Unable to open key file $path: $!";

    local $/;
    my $key_material = <$handle>;

    close $handle
        or die "Unable to close key file $path: $!";

    die "Key file $path contains fewer than $minimum_bytes bytes\n"
        if length($key_material) < $minimum_bytes;

    return sha256($key_material);
}

=head2 pseudonym($value, $key, $length)

Returns a hexadecimal HMAC-SHA-256 pseudonym.  C<$length> is the number of
hexadecimal characters, not bytes.

=cut

# Function: pseudonym
# Purpose: Creates a stable HMAC-SHA-256 identifier truncated to the requested printable length.
# Parameters: $self, $value, $key, $length
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub pseudonym {
    my ($self, $value, $key, $length) = @_;
    $length //= 32;
    return substr(hmac_sha256_hex($value, $key), 0, $length);
}

=head2 encrypt_token($plaintext, $key, $purpose)

Encrypts and authenticates a value.  The C<$purpose> string is incorporated into
both key derivation and authentication, so a token created for the HTML report
cannot be replayed as a TOR-header token even if an operator accidentally points
both features at the same key file.

Token format:

  v1:<base64url(IV || ciphertext || HMAC)>

The method throws when CryptX is unavailable.  Callers decide whether that error
should disable a feature, fall back to C<yes>, or reject an administrative CLI
operation.

=cut

# Function: encrypt_token
# Purpose: Encrypts a value with a random IV and authenticates the version, purpose, IV, and
#          ciphertext.
# Parameters: $self, $plaintext, $key, $purpose
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub encrypt_token {
    my ($self, $plaintext, $key, $purpose) = @_;
    $purpose //= 'postfilter-ng';

    eval { require Crypt::Mode::CBC; 1 }
        or die "CryptX (Crypt::Mode::CBC) is required for reversible encryption\n";

    my $initialisation_vector = _random_bytes(16);
    my $encryption_key = hmac_sha256("encryption:$purpose", $key);
    my $authentication_key = hmac_sha256("authentication:$purpose", $key);

    my $cipher = Crypt::Mode::CBC->new('AES');
    my $ciphertext = $cipher->encrypt(
        $plaintext,
        $encryption_key,
        $initialisation_vector,
    );

    my $format_version = 'PF1';
    my $tag = hmac_sha256(
        $format_version . $purpose . $initialisation_vector . $ciphertext,
        $authentication_key,
    );

    return 'v1:' . encode_base64url(
        $initialisation_vector . $ciphertext . $tag
    );
}

=head2 decrypt_token($token, $key, $purpose)

Validates and decrypts a token created by C<encrypt_token>.  Authentication uses
a constant-time comparison to avoid leaking which byte of the tag was wrong.

=cut

# Function: decrypt_token
# Purpose: Authenticates and decrypts a versioned token using the same purpose-specific key.
# Parameters: $self, $token, $key, $purpose
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub decrypt_token {
    my ($self, $token, $key, $purpose) = @_;
    $purpose //= 'postfilter-ng';

    die "Unsupported encrypted token format\n"
        unless defined $token && $token =~ /^v1:(.+)$/;

    my $raw = decode_base64url($1);
    die "Encrypted token is too short\n" if length($raw) < 49;

    my $initialisation_vector = substr($raw, 0, 16);
    my $authentication_tag = substr($raw, -32);
    my $ciphertext = substr($raw, 16, length($raw) - 48);

    my $encryption_key = hmac_sha256("encryption:$purpose", $key);
    my $authentication_key = hmac_sha256("authentication:$purpose", $key);
    my $expected_tag = hmac_sha256(
        'PF1' . $purpose . $initialisation_vector . $ciphertext,
        $authentication_key,
    );

    die "Encrypted token authentication failed\n"
        unless _constant_time_equal($authentication_tag, $expected_tag);

    eval { require Crypt::Mode::CBC; 1 }
        or die "CryptX (Crypt::Mode::CBC) is required for reversible encryption\n";

    my $cipher = Crypt::Mode::CBC->new('AES');
    return $cipher->decrypt(
        $ciphertext,
        $encryption_key,
        $initialisation_vector,
    );
}

# Function: _constant_time_equal
# Purpose: Compares authentication tags without returning early on the first differing byte.
# Parameters: $left, $right
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _constant_time_equal {
    my ($left, $right) = @_;
    return 0 unless length($left) == length($right);

    my $difference = 0;
    for my $position (0 .. length($left) - 1) {
        $difference |= ord(substr($left,  $position, 1))
                    ^  ord(substr($right, $position, 1));
    }

    return $difference == 0;
}

# Function: _random_bytes
# Purpose: Reads an exact number of cryptographically secure bytes from /dev/urandom.
# Parameters: $required_bytes
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _random_bytes {
    my ($required_bytes) = @_;

    open my $random, '<:raw', '/dev/urandom'
        or die "A cryptographically secure random source is unavailable: $!";

    my $buffer = '';
    while (length($buffer) < $required_bytes) {
        my $read = read(
            $random,
            my $chunk,
            $required_bytes - length($buffer),
        );

        die "Unable to read /dev/urandom: $!" unless defined $read;
        die "/dev/urandom returned unexpected EOF" if $read == 0;
        $buffer .= $chunk;
    }

    close $random
        or die "Unable to close /dev/urandom: $!";

    return $buffer;
}

1;
