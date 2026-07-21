# Test purpose: Tests custom-filter fail-open/fail-closed policy and last-known-good custom code retention.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::NG;
use TestPostfilter qw(base_config build_context test_logger temporary_environment);

sub engine_for {
    my ($config) = @_;
    return bless {
        logger => test_logger(),
    }, 'Postfilter::NG';
}

for my $on_error (qw(accept reject)) {
    my $config = base_config();
    $config->{modules}{custom} = 1;
    $config->{custom}{module_file} = '/definitely/missing/custom.pm';
    $config->{custom}{on_error} = $on_error;
    my $ctx = build_context(config => $config);
    my $engine = engine_for($config);
    my $result = $engine->_run_custom_filter($ctx);

    if ($on_error eq 'accept') {
        ok($result->is_pass, 'missing custom file obeys fail-open');
    }
    else {
        ok($result->is_reject, 'missing custom file obeys fail-closed');
        is($result->legacy, 63, 'custom fail-closed uses custom rule code');
    }
}

my $dir = temporary_environment();
my $broken = "$dir/broken.pm";
open my $fh, '>', $broken or die $!;
print {$fh} "package Postfilter::Local; sub custom_rules { die q{boom}; } 1;\n";
close $fh;

my $config = base_config();
$config->{modules}{custom} = 1;
$config->{custom}{module_file} = $broken;
$config->{custom}{on_error} = 'accept';
my $result = engine_for($config)->_run_custom_filter(build_context(config => $config));
ok($result->is_pass, 'custom exception obeys explicit accept policy');

$config->{custom}{on_error} = 'reject';
$result = engine_for($config)->_run_custom_filter(build_context(config => $config));
ok($result->is_reject, 'custom exception obeys explicit reject policy');

# A custom module follows the same last-known-good principle as TOML.  Once a
# valid coderef has loaded, a malformed edit must not remove it from a running
# nnrpd process.
my $stable = "$dir/stable.pm";
open my $stable_fh, '>', $stable or die $!;
print {$stable_fh} <<'CUSTOM';
package Postfilter::Local;
sub custom_rules { return 0; }
1;
CUSTOM
close $stable_fh;

my $stable_config = base_config();
$stable_config->{modules}{custom} = 1;
$stable_config->{custom}{module_file} = $stable;
$stable_config->{custom}{on_error} = 'reject';
my $stable_engine = engine_for($stable_config);
my $stable_context = build_context(config => $stable_config);
ok($stable_engine->_run_custom_filter($stable_context)->is_pass,
   'valid custom module loads and passes');

open $stable_fh, '>', $stable or die $!;
print {$stable_fh} "this is not valid Perl }}}
";
close $stable_fh;
utime(time + 2, time + 2, $stable);

$stable_context = build_context(config => $stable_config);
ok($stable_engine->_run_custom_filter($stable_context)->is_pass,
   'broken custom edit retains previous working coderef');

done_testing;
