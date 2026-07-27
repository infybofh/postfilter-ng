# Test purpose: Verifies portable Perl entry points, installer-persisted runtime paths,
# asynchronous DNS deadlines and single-shot article-timeout reporting.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Scalar::Util qw(refaddr);
use Test::More;
use Time::HiRes qw(time);

use lib 'lib';
use lib 'tests/lib';

use Postfilter::Checks::Reputation;
use Postfilter::InstallPaths;
use Postfilter::NG;
use TestPostfilter qw(base_config build_context test_logger);

for my $path (qw(
    postfilter
    bin/postfilterctl
    installer/install-postfilter
    Makefile.PL
)) {
    open my $handle, '<', $path or die $!;
    my $shebang = <$handle>;
    close $handle;
    is($shebang, "#!/usr/bin/env perl\n", "$path has a portable source shebang");
}

{
    local $ENV{POSTFILTER_CONFIG} = '/temporary/site/postfilter.toml';
    local $ENV{POSTFILTER_STATE_DIR} = '/temporary/site/state';
    is(
        Postfilter::InstallPaths::config_file(),
        '/temporary/site/postfilter.toml',
        'explicit configuration environment override remains available',
    );
    is(
        Postfilter::InstallPaths::state_dir(),
        '/temporary/site/state',
        'explicit state environment override remains available',
    );
}

my %source;
for my $path (qw(
    postfilter
    bin/postfilterctl
    installer/install-postfilter
    lib/Postfilter/Checks/Reputation.pm
)) {
    open my $handle, '<', $path or die $!;
    local $/;
    $source{$path} = <$handle>;
    close $handle;
}

like(
    $source{'postfilter'},
    qr/Postfilter::InstallPaths::config_file/,
    'embedded hook obtains its configuration path from the installed path module',
);
like(
    $source{'bin/postfilterctl'},
    qr/Postfilter::InstallPaths::state_dir/,
    'postfilterctl obtains its state path from the installed path module',
);
like(
    $source{'installer/install-postfilter'},
    qr/sub _write_install_paths_module/,
    'installer generates permanent runtime path defaults',
);
like(
    $source{'installer/install-postfilter'},
    qr/sub _verify_hook_load/,
    'installer verifies embedded hook construction and exact release identity',
);
like(
    $source{'installer/install-postfilter'},
    qr/_rewrite_installed_shebangs\(\$release_stage, \$perl_path\)/,
    'installer pins installed commands to the active Perl interpreter',
);

{
    my $project_root = abs_path('.');
    my $installed_root = tempdir(CLEANUP => 1);
    my $installed_postfilter = File::Spec->catfile(
        $installed_root,
        'postfilter',
    );
    copy('postfilter', $installed_postfilter) or die $!;

    my $installed_module_root = File::Spec->catdir(
        $installed_root,
        'lib',
        'Postfilter',
    );
    make_path($installed_module_root);

    for my $source_module (glob('lib/Postfilter/*.pm')) {
        next if $source_module =~ m{/InstallPaths\.pm\z};
        my ($name) = $source_module =~ m{/([^/]+)\z};
        symlink(
            File::Spec->catfile($project_root, $source_module),
            File::Spec->catfile($installed_module_root, $name),
        ) or die "Unable to link $source_module: $!";
    }
    symlink(
        File::Spec->catdir($project_root, 'lib', 'Postfilter', 'Checks'),
        File::Spec->catdir($installed_module_root, 'Checks'),
    ) or die "Unable to link installed Checks directory: $!";

    my $custom_config = File::Spec->catfile(
        $installed_root,
        'etc',
        'postfilter.toml',
    );
    my $custom_state = File::Spec->catdir($installed_root, 'state');
    make_path($custom_state);

    my $installed_paths = File::Spec->catfile(
        $installed_module_root,
        'InstallPaths.pm',
    );
    open my $paths_handle, '>', $installed_paths or die $!;
    print {$paths_handle} "package Postfilter::InstallPaths;\n";
    print {$paths_handle} "use strict; use warnings;\n";
    print {$paths_handle} "use constant CONFIG_FILE => '$custom_config';\n";
    print {$paths_handle} "use constant STATE_DIR => '$custom_state';\n";
    print {$paths_handle} 'sub config_file { return $ENV{POSTFILTER_CONFIG} // CONFIG_FILE }' . "\n";
    print {$paths_handle} 'sub state_dir { return $ENV{POSTFILTER_STATE_DIR} // STATE_DIR }' . "\n1;\n";
    close $paths_handle or die $!;

    my $hook = File::Spec->catfile($installed_root, 'filter_nnrpd.pl');
    symlink $installed_postfilter, $hook or die $!;
    my $loader = File::Spec->catfile($installed_root, 'embedded-path-test.pl');
    open my $loader_handle, '>', $loader or die $!;
    print {$loader_handle} <<'LOADER';
use strict;
use warnings;
delete $ENV{POSTFILTER_CONFIG};
delete $ENV{POSTFILTER_STATE_DIR};
local $0 = '/usr/local/news/bin/nnrpd';
my $loaded = do shift;
die "load error: $@" if $@;
die "operating-system error: $!" unless defined $loaded;
my $engine = main::_engine();
print "$engine->{source}\n$engine->{state_dir}\n";
$engine->shutdown;
LOADER
    close $loader_handle or die $!;

    my $output = qx{"$^X" "$loader" "$hook" 2>&1};
    is($?, 0, 'embedded engine constructs with generated non-Linux paths')
        or diag $output;
    like(
        $output,
        qr/^\Q$custom_config\E\n\Q$custom_state\E\n/m,
        'generated configuration and state paths survive after installer environment ends',
    );
}
unlike(
    $source{'lib/Postfilter/Checks/Reputation.pm'},
    qr/->query\s*\(/,
    'DNS reputation code no longer uses the synchronous query API',
);
like(
    $source{'lib/Postfilter/Checks/Reputation.pm'},
    qr/->bgsend\s*\(/,
    'DNS reputation code uses the asynchronous Net::DNS API',
);
like(
    $source{'lib/Postfilter/Checks/Reputation.pm'},
    qr/->retry\(1\)/,
    'resolver retries are explicitly limited to one attempt',
);

{
    package Local::AlwaysBusyResolver;

    sub new {
        return bless { error => 'simulated resolver timeout' }, shift;
    }

    sub bgsend {
        return bless {}, 'Local::OpaqueDNSHandle';
    }

    sub bgbusy {
        return 1;
    }

    sub bgread {
        die "bgread must not be reached after a local deadline\n";
    }

    sub errorstring {
        return $_[0]{error};
    }
}

my $dns_config = base_config();
$dns_config->{timeouts}{dns_query_seconds} = 0.04;
$dns_config->{timeouts}{dns_total_seconds} = 1;
$dns_config->{timeouts}{max_processing_ms} = 2_700;
my $dns_context = build_context(config => $dns_config);
$dns_context->start_processing_budget;

my $dns_started = time;
my ($packet, $dns_error) =
    Postfilter::Checks::Reputation::_background_dns_query(
        $dns_context,
        Local::AlwaysBusyResolver->new,
        'unresponsive.example.invalid',
    );
my $dns_elapsed = time - $dns_started;

ok(!defined $packet, 'deadline-limited DNS query returns no packet');
is($dns_error, 'dns-query-timeout', 'per-query DNS deadline is reported explicitly');
cmp_ok($dns_elapsed, '<', 0.5, 'unresponsive provider cannot block for resolver retry defaults');

my $total_config = base_config();
$total_config->{timeouts}{dns_query_seconds} = 1;
$total_config->{timeouts}{dns_total_seconds} = 0.04;
$total_config->{timeouts}{max_processing_ms} = 2_700;
my $total_context = build_context(config => $total_config);
$total_context->start_processing_budget;

my (undef, $total_error) =
    Postfilter::Checks::Reputation::_background_dns_query(
        $total_context,
        Local::AlwaysBusyResolver->new,
        'second-unresponsive.example.invalid',
    );
is(
    $total_error,
    'dns-total-budget-exceeded',
    'whole-article DNS budget is shared across providers',
);

my $timeout_logger = test_logger();
my $timeout_config = base_config();
$timeout_config->{timeouts}{on_processing_timeout} = 'reject';
my $timeout_context = build_context(
    config => $timeout_config,
    logger => $timeout_logger,
);
my $engine = bless { logger => $timeout_logger }, 'Postfilter::NG';

my $first_timeout = $engine->_processing_timeout_result(
    $timeout_context,
    'banlist',
);
my $second_timeout = $engine->_processing_timeout_result(
    $timeout_context,
    'headers',
);

is(
    refaddr($second_timeout),
    refaddr($first_timeout),
    'repeated timeout checks reuse the first technical result',
);
my @timeout_events = grep {
    $_->{message} eq 'article_processing_budget_exceeded'
} @{ $timeout_logger->{events} };
is(scalar @timeout_events, 1, 'one article emits one processing-budget warning');
is(
    $timeout_events[0]{fields}{next_check},
    'banlist',
    'timeout log preserves the first stage that could not run',
);

{
    package Local::ExpiredContext;
    our @ISA = ('Postfilter::Context');
    sub start_processing_budget { return }
    sub deadline_exceeded { return 1 }
}

my $pipeline_logger = test_logger();
my $pipeline_config = base_config();
$pipeline_config->{policy}{mode} = 'audit';
$pipeline_config->{timeouts}{on_processing_timeout} = 'reject';
$pipeline_config->{headers}{force_default_organization} = 1;
$pipeline_config->{headers}{organization} = 'Replacement organization';
my $pipeline_context = build_context(
    config => $pipeline_config,
    headers => {
        Date         => TestPostfilter::current_rfc_date(),
        From         => 'Tester <tester@example.invalid>',
        'Message-ID' => '<timeout-header-skip@example.invalid>',
        Newsgroups   => 'local.test',
        Organization => 'Original organization',
        Path         => 'not-for-mail',
        Subject      => 'Timeout header skip regression',
    },
    logger => $pipeline_logger,
);
bless $pipeline_context, 'Local::ExpiredContext';
my $pipeline_engine = bless { logger => $pipeline_logger }, 'Postfilter::NG';
my $pipeline_result = $pipeline_engine->_run_pipeline($pipeline_context);
is(
    $pipeline_result->{code},
    'PF-INTERNAL-097',
    'expired audit pipeline retains the technical timeout rejection',
);
is(
    $pipeline_context->{headers}{Organization},
    'Original organization',
    'header transformations do not run after the article budget expires',
);
my @header_timeout_skips = grep {
    $_->{message} eq 'check_skipped'
        && ($_->{fields}{check} // '') eq 'headers'
        && ($_->{fields}{profile} // '') eq 'processing-timeout'
} @{ $pipeline_logger->{events} };
is(
    scalar @header_timeout_skips,
    1,
    'timeout audit path records one explicit header-stage skip',
);

done_testing;
