# Test purpose: Demonstrates concurrent WAL writes using the exact shipped SQL schema.
#
# This supplements, but does not replace, DBI/DBD::SQLite integration testing on
# the target INN server.  It runs with Python's standard sqlite3 module so schema
# and locking regressions remain visible in minimal release environments.

use strict;
use warnings;

use JSON::PP;
use Test::More;

my $python = qx{command -v python3 2>/dev/null};
chomp $python;
plan skip_all => 'python3 is unavailable for the SQLite WAL stress helper'
    unless $python && -x $python;

my $output = qx{$python tests/sqlite-concurrency.py --workers 16 --articles-per-worker 100 2>&1};
my $status = $? >> 8;

is($status, 0, 'concurrent SQLite helper exits successfully')
    or diag($output);

my $summary = eval { JSON::PP->new->decode($output) };
ok(!$@ && ref($summary) eq 'HASH', 'concurrency helper returns JSON')
    or diag($output);

if (ref($summary) eq 'HASH') {
    is($summary->{integrity_check}, 'ok', 'database integrity remains valid');
    is($summary->{row_count}, 1_600, 'all concurrent event inserts are present');
    is_deeply($summary->{failures}, [], 'no unhandled SQLITE_BUSY/locked failures');
    ok(($summary->{type_counts}{text} // 0) > 0, 'text events are present');
    ok(($summary->{type_counts}{binary} // 0) > 0, 'binary events are present');
    is(
        $summary->{saved_type_counts}{text},
        1,
        'text saved-article metadata remains independently typed',
    );
    is(
        $summary->{saved_type_counts}{binary},
        1,
        'binary saved-article metadata remains independently typed',
    );
}

done_testing();
