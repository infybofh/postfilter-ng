# Test purpose: Covers failures found during the first live rc1 deployment on an INN reader.
#
# The entry point must load through embedded Perl, header deletion must follow
# INN's documented undef convention, administrative database commands must not
# dereference an absent handle, and the installer must initialize runtime files
# as the configured news account.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';
use lib 'tests/lib';

use Postfilter::Article;
use Postfilter::Database;
use Postfilter::HeaderTransform;
use TestPostfilter qw(base_config build_context);

my $root = abs_path('.');
my $temporary = tempdir(CLEANUP => 1);
my $hook = File::Spec->catfile($temporary, 'filter_nnrpd.pl');
symlink File::Spec->catfile($root, 'postfilter'), $hook
    or die "Unable to create embedded-load test symlink: $!";

my $loader = File::Spec->catfile($temporary, 'embedded-load.pl');
open my $loader_handle, '>', $loader or die $!;
print {$loader_handle} <<'LOADER';
use strict;
use warnings;
local $0 = '/usr/lib/news/bin/nnrpd';
my $loaded = do shift;
die "load error: $@" if $@;
die "operating-system error: $!" unless defined $loaded;
die "false return from hook" unless $loaded;
die "filter_post missing" unless defined &filter_post;
print "Postfilter-NG hook load OK\n";
LOADER
close $loader_handle or die $!;

my $embedded_output = qx{"$^X" "$loader" "$hook" 2>&1};
is($?, 0, 'entry point loads through a symlink with nnrpd-style embedded Perl')
    or diag $embedded_output;
like(
    $embedded_output,
    qr/Postfilter-NG hook load OK/,
    'embedded load exposes filter_post without relying on FindBin or $0',
);

my $config = base_config();
$config->{headers}{sender}{mode} = 'delete';
my $context = build_context(
    config => $config,
    headers => {
        Path         => 'not-for-mail',
        From         => 'Author <author@example.invalid>',
        Sender       => 'Agent <agent@example.invalid>',
        Newsgroups   => 'local.test',
        Subject      => 'INN header deletion regression',
        Date         => TestPostfilter::current_rfc_date(),
        'Message-ID' => '<header-delete-live@test.invalid>',
    },
);
Postfilter::HeaderTransform->apply($context);
ok(
    exists $context->{headers}{Sender} && !defined $context->{headers}{Sender},
    'header deletion uses undef as required by the nnrpd Perl hook',
);
unlike(
    Postfilter::Article->serialize($context),
    qr/^Sender:/m,
    'offline serialization omits headers marked for INN deletion',
);

my $database = Postfilter::Database->new(
    config => {
        database => {
            enabled => 0,
            privacy => { identity_mode => 'plain' },
        },
    },
);
my $database_error = eval {
    $database->require_connection('db-check');
    '';
};
$database_error = $@ if $@;
like(
    $database_error,
    qr/SQLite is disabled.*db-check cannot continue/i,
    'disabled SQLite produces an explicit db-check diagnostic instead of an undef method call',
);

my $installer = do {
    open my $handle, '<', 'installer/install-postfilter' or die $!;
    local $/;
    <$handle>;
};
like(
    $installer,
    qr/_run_as_runtime_user\(\@runtime_command, 'check-config'\)/,
    'installer validates configuration as the runtime INN account',
);
like(
    $installer,
    qr/_run_as_runtime_user\(\@runtime_command, 'db-migrate'\)/,
    'installer initializes SQLite as the runtime INN account',
);
unlike(
    $installer,
    qr/system\(\@(?:base|runtime)_command,\s*'(?:check-config|db-migrate)'\)/,
    'installer no longer creates runtime state through root-run postfilterctl commands',
);
like(
    $installer,
    qr/POSIX::setgid.*POSIX::setuid/s,
    'installer drops saved IDs through POSIX before exec',
);
like(
    $installer,
    qr/_chown_tree\(.*state_dir.*_chown_tree\(.*saved_dir/s,
    'installer performs final recursive ownership and mode normalization',
);

done_testing;
