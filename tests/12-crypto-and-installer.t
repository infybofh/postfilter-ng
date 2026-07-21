# Test purpose: Checks key provisioning requirements, HMAC output and optional reversible encryption.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use File::Temp qw(tempdir);
use lib 'lib';
use Postfilter::Crypto;
use Postfilter::Database;

my $installer = do {
    open my $fh, '<', 'installer/install-postfilter' or die $!;
    local $/;
    <$fh>;
};

for my $key_name (qw(
    tor-header-encryption.key
    header-pseudonym.key
    html-report-privacy.key
    database-privacy.key
)) {
    like($installer, qr/\Q$key_name\E/, "installer creates $key_name");
}
like($installer, qr{/dev/urandom}, 'installer uses /dev/urandom');
like($installer, qr/O_EXCL|O_CREAT\s*\|\s*O_EXCL/, 'installer creates keys exclusively');
like(
    $installer,
    qr/filter_nnrpd\.pl\.ng/,
    'installer creates a staged INN hook candidate',
);
like(
    $installer,
    qr/does not modify.*filter_nnrpd\.pl/is,
    'installer warns that the active INN hook remains untouched',
);
unlike($installer, qr/emergency-salt|default-secret|hardcoded-key/i,
       'installer contains no known fallback secret');
like(
    $installer,
    qr/_configured_saved_subdirectories/,
    'installer resolves configured text and binary diagnostic trees',
);
like(
    $installer,
    qr/article_type.*saved_subdirectories/s,
    'installer creates each resolved article-type diagnostic directory',
);

my $dir = tempdir(CLEANUP => 1);
my $path = "$dir/key";
open my $fh, '>:raw', $path or die $!;
print {$fh} 'A' x 64;
close $fh;
my $crypto = Postfilter::Crypto->new();
my $key = $crypto->load_key($path);
is(length($key), 32, 'loaded key is reduced to a 256-bit derived key');
like(
    $crypto->pseudonym('192.0.2.1', $key, 32),
    qr/^[a-f0-9]{32}$/,
    'HMAC pseudonym has requested length',
);

my $database_config = {
    database => {
        enabled => 0,
        privacy => {
            identity_mode => 'plain',
            key_file      => $path,
        },
    },
};
my $database = Postfilter::Database->new(
    config => $database_config,
    crypto => $crypto,
);
my $plain_lookup = $database->identity_lookup('client_ip', '192.0.2.1');
$database_config->{database}{privacy}{identity_mode} = 'encrypted';
my $encrypted_lookup = $database->identity_lookup('client_ip', '192.0.2.1');
is(
    $encrypted_lookup,
    $plain_lookup,
    'hidden identity lookup remains stable when storage privacy mode changes',
);
is(
    $database->reveal_identity('client_ip', '192.0.2.1', 'plain'),
    '192.0.2.1',
    'plain database identity is returned unchanged to administrative tools',
);

SKIP: {
    skip 'CryptX not installed in build environment', 3
        unless eval { require Crypt::Mode::CBC; 1 };
    my $token = $crypto->encrypt_token('192.0.2.1', $key, 'test-purpose');
    like($token, qr/^v1:/, 'encrypted token is versioned');
    is(
        $crypto->decrypt_token($token, $key, 'test-purpose'),
        '192.0.2.1',
        'encrypted token is reversible with the key',
    );
    my $database_token = $crypto->encrypt_token(
        '192.0.2.1',
        $key,
        'database-client_ip',
    );
    is(
        $database->reveal_identity(
            'client_ip',
            $database_token,
            'encrypted',
        ),
        '192.0.2.1',
        'administrative database output can reveal an authenticated token',
    );
}

done_testing;
