# Test purpose: Verifies stable configuration generations, bounded generation retention,
# delayed processing-budget start, TOR-header observability and irreversible installer privilege drop.
#
# These checks cover behaviour identified from the first full day of live RC2
# logs and from the independent release-candidate review.

use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use Storable qw(dclone);
use Test::More;
use Time::HiRes qw(sleep);

use lib 'lib';
use lib 'tests/lib';

use Postfilter::Config;
use Postfilter::HeaderTransform;
use TestPostfilter qw(base_config build_context test_logger);

my $state_directory = tempdir(CLEANUP => 1);
my $logger = test_logger();
my $loader = Postfilter::Config->new(
    logger    => $logger,
    source    => '/etc/news/postfilter-ng/postfilter.toml',
    state_dir => $state_directory,
);

my $template = base_config();
$template->{paths}{state_dir} = $state_directory;
$template->{retention}{config_generations} = 3;
delete $template->{_meta};

my $first = dclone($template);
my $first_warnings = $loader->validate_and_sanitize($first);
$loader->_assign_generation($first, $first_warnings);
$loader->_save_generation($first, $first_warnings);

my $second = dclone($template);
my $second_warnings = $loader->validate_and_sanitize($second);
$loader->_assign_generation($second, $second_warnings);
is(
    $second->{_meta}{generation},
    $first->{_meta}{generation},
    'identical effective configuration reuses one content-derived generation',
);

my $last_known_good = File::Spec->catfile(
    $state_directory,
    'last-known-good.json',
);
open my $lkg_before_handle, '<', $last_known_good or die $!;
local $/;
my $lkg_before = <$lkg_before_handle>;
close $lkg_before_handle or die $!;

sleep 0.02;
$loader->_save_generation($second, $second_warnings);

my @same_generation_files = glob(File::Spec->catfile(
    $state_directory,
    'config-generations',
    '*.json',
));
is(
    scalar @same_generation_files,
    1,
    'a second nnrpd-style load does not create another generation file',
);

open my $lkg_after_handle, '<', $last_known_good or die $!;
local $/;
my $lkg_after = <$lkg_after_handle>;
close $lkg_after_handle or die $!;
is(
    $lkg_after,
    $lkg_before,
    'unchanged generation does not rewrite last-known-good.json',
);

my $current_generation;
for my $index (1 .. 5) {
    my $changed = dclone($template);
    $changed->{limits}{max_crosspost} += $index;
    my $warnings = $loader->validate_and_sanitize($changed);
    $loader->_assign_generation($changed, $warnings);
    $loader->_save_generation($changed, $warnings);
    $current_generation = $changed->{_meta}{generation};
}

my @retained = glob(File::Spec->catfile(
    $state_directory,
    'config-generations',
    '*.json',
));
is(scalar @retained, 3, 'generation retention keeps the configured maximum');
ok(
    -f File::Spec->catfile(
        $state_directory,
        'config-generations',
        "$current_generation.json",
    ),
    'generation pruning never removes the active configuration',
);

my $deadline_config = base_config();
$deadline_config->{timeouts}{max_processing_ms} = 10;
my $deadline_context = build_context(config => $deadline_config);
sleep 0.02;
ok(
    !$deadline_context->deadline_exceeded,
    'context construction and preliminary delay do not consume the processing budget',
);
$deadline_context->start_processing_budget;
sleep 0.02;
ok(
    $deadline_context->deadline_exceeded,
    'processing budget starts explicitly before bounded checks',
);
ok(
    $deadline_context->pipeline_elapsed_ms >= 10,
    'pipeline elapsed timing starts with the bounded processing budget',
);

my $tor_logger = test_logger();
my $tor_config = base_config();
$tor_config->{tor}{header} = {
    mode => 'none',
    name => 'X-Postfilter-TOR',
};
my $tor_context = build_context(
    config => $tor_config,
    logger => $tor_logger,
);
$tor_context->{tor} = 1;
Postfilter::HeaderTransform->apply($tor_context);

my ($tor_header_event) = grep {
    $_->{message} eq 'header_added'
        && ($_->{fields}{header} // '') eq 'X-Postfilter-TOR'
} @{ $tor_logger->{events} };
ok($tor_header_event, 'TOR marker header addition is visible in verbose logs');
is(
    $tor_header_event->{fields}{mode},
    'marker',
    'TOR header log records the non-sensitive storage mode',
);

my $installer = do {
    open my $handle, '<', 'installer/install-postfilter' or die $!;
    local $/;
    <$handle>;
};
like($installer, qr/POSIX::setgid/, 'installer drops real, effective and saved gid');
like($installer, qr/POSIX::setuid/, 'installer drops real, effective and saved uid');
unlike(
    $installer,
    qr/\$<\s*=\s*\$user_id|\$>\s*=\s*\$user_id/,
    'installer no longer relies on separate Perl uid assignments',
);

my $ng_source = do {
    open my $handle, '<', 'lib/Postfilter/NG.pm' or die $!;
    local $/;
    <$handle>;
};
for my $phase (qw(
    configuration context trusted_profile pipeline headers database_event
    finalization
)) {
    like(
        $ng_source,
        qr/phase\s*=>\s*['"]\Q$phase\E['"]/,
        "verbosity-nine timing includes the $phase phase",
    );
}

like(
    $ng_source,
    qr/finalization_ms\s*=>/,
    'final result exposes finalization timing',
);
like(
    $ng_source,
    qr/pipeline_ms\s*=>/,
    'final result exposes pipeline timing',
);

done_testing;
