# Test purpose: Verifies legal-history tables, indefinite retention and explicit audited purge controls.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;

my $sql = '';
for my $path (sort glob('migrations/*.sql')) {
    open my $fh, '<', $path or die $!;
    local $/;
    $sql .= <$fh>;
}

for my $table (qw(
    article_events rule_hits saved_articles local_distribution provider_health
    configuration_generations administrative_actions schema_migrations
)) {
    like($sql, qr/CREATE TABLE(?: IF NOT EXISTS)?\s+\Q$table\E\b/i,
         "schema defines $table");
}
unlike($sql, qr/CREATE\s+TRIGGER.*DELETE/is, 'schema has no automatic deletion trigger');
unlike($sql, qr/expires_at.*article_events/is, 'article events have no implicit expiry');
like(
    $sql,
    qr/identity_storage_mode\s+TEXT\s+NOT\s+NULL/i,
    'each event records the privacy mode that stored its identities',
);
like(
    $sql,
    qr/client_ip_lookup.*auth_user_lookup/is,
    'schema provides stable hidden identity lookup columns',
);
like(
    $sql,
    qr/article_type\s+TEXT\s+NOT\s+NULL/i,
    'each event records text or binary article type',
);
like(
    $sql,
    qr/article_events_type_time_idx/i,
    'schema indexes long-term queries by article type and time',
);
like(
    $sql,
    qr/ALTER TABLE saved_articles.*article_type/is,
    'migration 004 adds article type to saved diagnostic metadata',
);
like(
    $sql,
    qr/saved_articles_type_time_idx/i,
    'saved diagnostic metadata is indexed by article type and time',
);

my $config = do {
    open my $fh, '<', 'conf/postfilter.toml' or die $!;
    local $/;
    <$fh>;
};
like($config, qr/events\s*=\s*"forever"/, 'event retention defaults to forever');
like($config, qr/rule_hits\s*=\s*"forever"/, 'rule-hit retention defaults to forever');
like($config, qr/saved_articles\s*=\s*"forever"/, 'saved article retention defaults to forever');

my $ctl = do {
    open my $fh, '<', 'bin/postfilterctl' or die $!;
    local $/;
    <$fh>;
};
like($ctl, qr/--confirm/, 'purge requires explicit confirmation option');
like($ctl, qr/dry.run/i, 'purge supports or documents dry-run behaviour');
like(
    $ctl,
    qr/client_ip_lookup\s*=\s*\?/,
    'postfilterctl IP queries use the stable lookup column',
);
like(
    $ctl,
    qr/auth_user_lookup\s*=\s*\?/,
    'postfilterctl user queries use the stable lookup column',
);
like(
    $ctl,
    qr/reveal-identities/,
    'exports require an explicit option before decrypting protected identities',
);
like(
    $ctl,
    qr/article-type/,
    'postfilterctl can query text and binary history separately',
);
like(
    $ctl,
    qr/saved_articles\.article_type\s*=\s*\?/,
    'saved-list can filter diagnostic metadata by article type',
);

done_testing;
