# Test purpose: Tests audit/enforce policy resolution, INN DROP semantics and processing deadlines.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::NG;
use Postfilter::Result;
use TestPostfilter qw(base_config build_context test_logger);

my $engine = bless { logger => test_logger() }, 'Postfilter::NG';
my $ctx = build_context(config => base_config());

my $drop_result = Postfilter::Result->reject(
    code             => 'PF-RULE-300',
    legacy           => 34,
    message          => 'Drop requested',
    requested_action => 'discard',
);
my $final = $engine->_resolve_policy($ctx, $drop_result);
is($final->{nntp_result}, 'discarded', 'rule drop resolves to discarded');
is($engine->_inn_response($ctx, $drop_result, $final), 'DROP',
   'discard uses INN documented DROP response');

$ctx->{config}{policy}{mode} = 'audit';
$final = $engine->_resolve_policy($ctx, $drop_result);
is($final->{nntp_result}, 'accepted', 'audit accepts a would-drop article');
ok($final->{would_reject}, 'audit records technical negative verdict');

$ctx->{config}{policy}{action_on_reject} = 'save';
$final = $engine->_resolve_policy($ctx, $drop_result);
ok($final->{save}, 'audit preserves diagnostic save-on-reject policy');

my $timeout_cfg = base_config();
$timeout_cfg->{timeouts}{on_processing_timeout} = 'accept';
my $timeout_ctx = build_context(config => $timeout_cfg);
ok($engine->_processing_timeout_result($timeout_ctx, 'rbl')->is_pass,
   'processing timeout may fail open');
$timeout_cfg->{timeouts}{on_processing_timeout} = 'reject';
$timeout_ctx = build_context(config => $timeout_cfg);
ok($engine->_processing_timeout_result($timeout_ctx, 'rbl')->is_reject,
   'processing timeout may fail closed');

done_testing;
