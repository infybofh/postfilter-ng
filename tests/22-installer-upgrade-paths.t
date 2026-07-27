# Test purpose: Verifies non-destructive upgrade migration of historical path defaults,
# path-adjusted distribution snapshots and installer diagnostics for generated runtime paths.

use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

use lib 'lib';

use Postfilter::InstallUpgrade qw(
    migrate_legacy_path_files
    write_distribution_snapshot
);

my $root = tempdir(CLEANUP => 1);
my $config_root = File::Spec->catdir($root, 'usr', 'local', 'news', 'etc', 'postfilter-ng');
my $fragment_root = File::Spec->catdir($config_root, 'conf.d');
make_path($fragment_root);

my $main = File::Spec->catfile($config_root, 'postfilter.toml');
my $fragment = File::Spec->catfile($fragment_root, '90-local.toml');

open my $main_handle, '>', $main or die $!;
print {$main_handle} <<'TOML';
[paths]
state_dir = "/var/lib/news/postfilter-ng"
saved_dir = "/var/spool/news/postfilter-ng/rejected"
active_file = "/var/lib/news/active"
html_output = "/var/www/html/postfilter/index.html"
public_suffix_file = "/etc/news/postfilter-ng/public_suffix_list.dat"
sendmail = "/usr/lib/news/bin/innmail"
custom_similar_prefix = "/etc/news/postfilter-ng-custom/keep-me"

[database]
path = "/var/lib/news/postfilter-ng/postfilter.sqlite3"
TOML
close $main_handle or die $!;

open my $fragment_handle, '>', $fragment or die $!;
print {$fragment_handle} <<'TOML';
[keys]
header_pseudonym = "/etc/news/postfilter-ng/keys/header-pseudonym.key"
custom_key = "/var/lib/news/postfilter-ng-old/key"
TOML
close $fragment_handle or die $!;

my $backup_root = File::Spec->catdir($config_root, 'upgrade-backups', '20260727T120000Z');
my $replacements = [
    ['/var/spool/news/postfilter-ng/rejected', '/usr/local/news/spool/postfilter-ng/rejected'],
    ['/var/lib/news/postfilter-ng', '/usr/local/news/db/postfilter-ng'],
    ['/var/www/html/postfilter', '/usr/local/www/apache24/data/postfilter'],
    ['/var/lib/news/active', '/usr/local/news/db/active'],
    ['/usr/lib/news/bin/innmail', '/usr/local/news/bin/innmail'],
    ['/etc/news/postfilter-ng', '/usr/local/news/etc/postfilter-ng'],
];

my $result = migrate_legacy_path_files(
    files        => [$main, $fragment],
    replacements => $replacements,
    config_root  => $config_root,
    backup_root  => $backup_root,
);

is(scalar @{ $result->{changed_files} }, 2, 'both preserved TOML files are migrated');
cmp_ok($result->{replacement_count}, '>=', 8, 'all historical path occurrences are counted');
ok(-f File::Spec->catfile($backup_root, 'postfilter.toml'), 'main configuration backup exists');
ok(-f File::Spec->catfile($backup_root, 'conf.d', '90-local.toml'), 'fragment backup exists');

my $main_text = _slurp($main);
like($main_text, qr{/usr/local/news/db/postfilter-ng/postfilter\.sqlite3}, 'state and database paths migrate');
like($main_text, qr{/usr/local/news/spool/postfilter-ng/rejected}, 'saved-article path migrates');
like($main_text, qr{/usr/local/www/apache24/data/postfilter/index\.html}, 'HTML output path migrates');
like($main_text, qr{/usr/local/news/etc/postfilter-ng/public_suffix_list\.dat}, 'configuration asset path migrates');
like($main_text, qr{/usr/local/news/bin/innmail}, 'sendmail path migrates');
like($main_text, qr{/etc/news/postfilter-ng-custom/keep-me}, 'similar custom prefix remains unchanged');

my $fragment_text = _slurp($fragment);
like($fragment_text, qr{/usr/local/news/etc/postfilter-ng/keys/header-pseudonym\.key}, 'fragment key path migrates');
like($fragment_text, qr{/var/lib/news/postfilter-ng-old/key}, 'similar state prefix remains unchanged');

my $main_backup = _slurp(File::Spec->catfile($backup_root, 'postfilter.toml'));
like($main_backup, qr{/var/lib/news/postfilter-ng/postfilter\.sqlite3}, 'backup preserves original main content');

my $second_backup = File::Spec->catdir($config_root, 'upgrade-backups', '20260727T120001Z');
my $second = migrate_legacy_path_files(
    files        => [$main, $fragment],
    replacements => $replacements,
    config_root  => $config_root,
    backup_root  => $second_backup,
);
is($second->{replacement_count}, 0, 'repeated upgrade performs no unnecessary migration');
ok(!-e $second_backup, 'no empty backup tree is created when nothing changes');

my $distribution_source = File::Spec->catfile($root, 'postfilter.toml.source');
open my $distribution_handle, '>', $distribution_source or die $!;
print {$distribution_handle} <<'TOML';
[paths]
state_dir = "/var/lib/news/postfilter-ng"
custom = "/etc/news/postfilter-ng-custom/unchanged"
TOML
close $distribution_handle or die $!;

my $distribution_destination = "$main.dist";
write_distribution_snapshot(
    source       => $distribution_source,
    destination  => $distribution_destination,
    replacements => $replacements,
);
my $distribution_text = _slurp($distribution_destination);
like($distribution_text, qr{/usr/local/news/db/postfilter-ng}, '.dist snapshot receives detected paths');
like($distribution_text, qr{/etc/news/postfilter-ng-custom/unchanged}, '.dist snapshot preserves custom-like prefixes');

my $installer = _slurp('installer/install-postfilter');
like($installer, qr/sub _verify_install_paths_module_for_release/, 'installer directly verifies generated path module');
like($installer, qr/InstallPaths module=/, 'installer prints the loaded module path');
like($installer, qr/--config.*postfilter\.toml/s, 'installer performs explicit bootstrap configuration validation');
like($installer, qr/--state-dir/, 'installer performs explicit bootstrap state validation');
like($installer, qr/PERL5LIB PERLLIB PERL5OPT/, 'installer clears inherited Perl path and option variables');
like($installer, qr/\.failed\./, 'installer preserves failed activated trees for diagnosis');
like($installer, qr/_install_distribution_configuration_snapshots/, 'installer writes current .dist references on upgrade');

sub _slurp {
    my ($path) = @_;
    open my $handle, '<:raw', $path or die $!;
    local $/;
    my $text = <$handle>;
    close $handle or die $!;
    return $text;
}

done_testing;
