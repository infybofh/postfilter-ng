# Test purpose: Verifies immutable release wrappers, managed release markers,
# legacy migration safeguards and GitHub-web-compatible installer invocation.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP;
use Test::More;

use lib 'lib';

use Postfilter::ReleaseManager qw(
    parse_hook_wrapper
    read_release_marker
    release_dir_is_managed
    safe_release_directory
    write_hook_wrapper
    write_release_marker
);

my $root = tempdir(CLEANUP => 1);
my $prefix = File::Spec->catdir($root, 'prefix');
my $release = File::Spec->catdir($prefix, 'releases', '2026.08.1-rc1');
my $lib = File::Spec->catdir($release, 'lib');
make_path($lib);

my $entry = File::Spec->catfile($release, 'postfilter');
open my $entry_handle, '>', $entry or die $!;
print {$entry_handle} <<'HOOK';
use strict;
use warnings;
sub filter_post { return ''; }
1;
HOOK
close $entry_handle or die $!;

write_release_marker(
    directory => $release,
    version   => '2026.08.1-rc1',
    legacy    => 0,
);
my $marker = read_release_marker($release);
is($marker->{version}, '2026.08.1-rc1', 'managed release marker records version');
ok(!$marker->{legacy}, 'normal release is not marked legacy');

my $wrapper = File::Spec->catfile($root, 'filter_nnrpd.pl.ng');
write_hook_wrapper(
    path        => $wrapper,
    release_dir => $release,
    version     => '2026.08.1-rc1',
    perl        => abs_path($^X) // $^X,
);
ok(-f $wrapper && !-l $wrapper, 'candidate hook is a regular wrapper, not a symlink');
is((stat($wrapper))[2] & 07777, 0644, 'wrapper is readable and does not depend on execute mode');

my $metadata = parse_hook_wrapper($wrapper);
is($metadata->{version}, '2026.08.1-rc1', 'wrapper metadata identifies release');
is($metadata->{release_dir}, $release, 'wrapper is pinned to immutable release path');

my $output = qx{"$^X" -e 'my \$f=shift; my \$r=do \$f; die \$@ if \$@; die \$! unless defined \$r; die "missing" unless defined &filter_post; print "ok\\n"' "$wrapper" 2>&1};
is($?, 0, 'regular wrapper loads through Perl do without execute permission') or diag $output;
like($output, qr/^ok/m, 'wrapper exposes filter_post');

my ($managed, $managed_marker) = release_dir_is_managed($prefix, $release);
is($managed, abs_path($release), 'managed release remains below releases root');
is($managed_marker->{version}, '2026.08.1-rc1', 'managed release marker is returned');
ok(!safe_release_directory($prefix, File::Spec->catdir($root, 'outside')), 'outside directory is rejected');

my $installer = _slurp('installer/install-postfilter');
like($installer, qr/sub _ensure_legacy_snapshot/, 'installer snapshots all recognised pre-rc6 flat layouts');
like($installer, qr/active hook .* would not be modified/i, 'candidate installation explicitly preserves active hook');
like($installer, qr/sub _activate_candidate/, 'installer has explicit candidate activation');
like($installer, qr/sub _rollback_active_hook/, 'installer has explicit rollback');
like($installer, qr/Cleanup refused: active hook does not use the latest installed release/, 'cleanup requires active latest release');
like($installer, qr/legacy.*could not be validated.*cleanup/s, 'unvalidated legacy rollback disables cleanup');
like($installer, qr/--keep-releases must be at least 2/, 'retention always keeps a rollback release');
like($installer, qr/write_hook_wrapper\(/, 'installer generates regular hook wrappers');
unlike($installer, qr/symlink\s+"\$option\{prefix\}\/postfilter"/, 'installer no longer creates active-prefix hook symlinks');

my $dry_root = File::Spec->catdir($root, 'dry');
my @dry = (
    $^X, 'installer/install-postfilter',
    '--dry-run', '--no-innconfval', '--skip-dependency-check',
    '--prefix', File::Spec->catdir($dry_root, 'prefix'),
    '--filter-dir', File::Spec->catdir($dry_root, 'filter'),
    '--config-dir', File::Spec->catdir($dry_root, 'etc'),
    '--state-dir', File::Spec->catdir($dry_root, 'state'),
    '--saved-dir', File::Spec->catdir($dry_root, 'saved'),
    '--html-dir', File::Spec->catdir($dry_root, 'html'),
    '--active-file', File::Spec->catfile($dry_root, 'active'),
    '--sendmail', '/bin/true',
    '--ctl-bin', File::Spec->catfile($dry_root, 'bin', 'postfilterctl'),
    '--user', scalar(getpwuid($<)),
    '--group', scalar(getgrgid($( + 0)),
);
my $dry_output = qx{@dry 2>&1};
is($?, 0, 'installer runs explicitly through perl even when source execute mode is irrelevant')
    or diag $dry_output;
like($dry_output, qr/would install immutable release/, 'dry-run reports immutable release plan');
like($dry_output, qr/no cleanup would be performed before activation/, 'dry-run reports cleanup gate');

sub _slurp {
    my ($path) = @_;
    open my $handle, '<:raw', $path or die $!;
    local $/;
    my $text = <$handle>;
    close $handle or die $!;
    return $text;
}

done_testing;
