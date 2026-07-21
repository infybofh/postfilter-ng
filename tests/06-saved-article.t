# Test purpose: Checks collision-safe, chronologically sortable names and saved-article metadata.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::Result;
use Postfilter::SavedArticle;
use TestPostfilter qw(base_config build_context temporary_environment);

my $dir = temporary_environment();
my $config = base_config();
$config->{paths}{saved_dir} = $dir;
$config->{saved_articles}{directory_layout} = 'flat';

my $ctx = build_context(config => $config);
$ctx->{message_id_hash} = 'a4f982b68d128bc73e71a977';
my $result = Postfilter::Result->reject(
    code    => 'PF-MIME-003',
    legacy  => 5,
    message => 'MIME test rejection',
);
my $saved = Postfilter::SavedArticle->save($ctx, $result);

like(
    $saved->{path},
    qr{/\d+\.\d{6}\.PF-MIME-003\.[a-f0-9]{24}\.post$},
    'saved filename is timestamp.code.message-id-hash.post',
);
ok(-f $saved->{path}, 'saved article exists');
ok($saved->{size} > 0, 'saved article size recorded');
is($saved->{article_type}, 'text', 'saved metadata records article type');
like($saved->{sha256}, qr/^[a-f0-9]{64}$/, 'saved article SHA-256 recorded');

open my $fh, '<', $saved->{path} or die $!;
local $/;
my $data = <$fh>;
close $fh;
like($data, qr/^X-Postfilter-Error: PF-MIME-003$/m, 'symbolic code stored in article');
like($data, qr/^X-Postfilter-Legacy-Code: 5$/m, 'numeric historical code stored');
like(
    $data,
    qr/^X-Postfilter-Article-Type: text$/m,
    'saved diagnostic copy records its article type',
);
ok(
    !defined $ctx->{headers}{'X-Postfilter-Article-Type'},
    'diagnostic article-type header is removed from the live article',
);

done_testing;
