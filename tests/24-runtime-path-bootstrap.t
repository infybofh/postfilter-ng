# Test purpose: Executes the installed-style postfilterctl path diagnostic both
# directly and through a symlink, and verifies that candidate validation never
# falls back to Linux defaults after resolving installer paths.

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

my $root = tempdir(CLEANUP => 1);
my $release = File::Spec->catdir($root, 'prefix', 'releases', '2026.09.1-rc2');
my $bin = File::Spec->catdir($release, 'bin');
my $lib = File::Spec->catdir($release, 'lib', 'Postfilter');
make_path($bin, $lib, File::Spec->catdir($root, 'sbin'));

my $ctl = File::Spec->catfile($bin, 'postfilterctl');
_copy('bin/postfilterctl', $ctl);
chmod 0755, $ctl or die $!;

my $config = File::Spec->catfile($root, 'usr', 'local', 'news', 'etc', 'postfilter-ng', 'postfilter.toml');
my $state = File::Spec->catdir($root, 'usr', 'local', 'news', 'db', 'postfilter-ng');
my $module = File::Spec->catfile($lib, 'InstallPaths.pm');
open my $module_handle, '>:raw', $module or die $!;
print {$module_handle} "package Postfilter::InstallPaths;\nuse strict;\nuse warnings;\n"
    . "use constant CONFIG_FILE => '" . _quote($config) . "';\n"
    . "use constant STATE_DIR => '" . _quote($state) . "';\n"
    . "sub config_file { return \$ENV{POSTFILTER_CONFIG} // CONFIG_FILE }\n"
    . "sub state_dir { return \$ENV{POSTFILTER_STATE_DIR} // STATE_DIR }\n1;\n";
close $module_handle or die $!;

local @ENV{qw(POSTFILTER_CONFIG POSTFILTER_STATE_DIR)};
delete @ENV{qw(POSTFILTER_CONFIG POSTFILTER_STATE_DIR PERL5LIB PERLLIB PERL5OPT)};

my ($direct_status, $direct) = _run($ctl, 'install-paths');
is($direct_status, 0, 'direct release command succeeds without optional runtime modules') or diag $direct;
like($direct, qr/^InstallPaths module=\Q$module\E$/m, 'direct command loads release InstallPaths module');
like($direct, qr/^InstallPaths config=\Q$config\E$/m, 'direct command reports generated config path');
like($direct, qr/^InstallPaths state=\Q$state\E$/m, 'direct command reports generated state path');
unlike($direct, qr{/etc/news/postfilter-ng|/var/lib/news/postfilter-ng}, 'direct command does not fall back to Linux defaults');

my $link = File::Spec->catfile($root, 'sbin', 'postfilterctl');
symlink $ctl, $link or die $!;
my ($link_status, $linked) = _run($link, 'install-paths');
is($link_status, 0, 'symlinked administration command succeeds') or diag $linked;
like($linked, qr/^InstallPaths module=\Q$module\E$/m, 'symlink resolves the target release library through __FILE__');
like($linked, qr/^InstallPaths config=\Q$config\E$/m, 'symlinked command retains generated config path');
like($linked, qr/^InstallPaths state=\Q$state\E$/m, 'symlinked command retains generated state path');

my $installer = _slurp('installer/install-postfilter');
my ($validation) = $installer =~ /(sub _validate_candidate_release \{.*?^\})/ms;
ok(defined $validation, 'candidate validation function is present');
my $config_count = () = ($validation // '') =~ /'--config'/g;
my $state_count = () = ($validation // '') =~ /'--state-dir'/g;
is($config_count, 1, 'candidate validation builds one shared command with explicit config');
is($state_count, 1, 'candidate validation builds one shared command with explicit state directory');
unlike($validation // '', qr/\@base_command/, 'no implicit-path validation command remains');
like($validation // '', qr/_run_as_runtime_user\(\@runtime_command, 'check-config'\).*?_run_as_runtime_user\(\@runtime_command, 'db-check'\)/s,
    'post-generation checks reuse the explicit runtime command');

done_testing;

sub _run {
    my (@command) = @_;
    my $quoted = join ' ', map { _shell_quote($_) } @command;
    my $output = qx{$quoted 2>&1};
    return ($? >> 8, $output);
}

sub _copy {
    my ($source, $destination) = @_;
    open my $in, '<:raw', $source or die $!;
    open my $out, '>:raw', $destination or die $!;
    while (read($in, my $buffer, 65536)) {
        print {$out} $buffer or die $!;
    }
    close $in or die $!;
    close $out or die $!;
}

sub _slurp {
    my ($path) = @_;
    open my $handle, '<:raw', $path or die $!;
    local $/;
    my $text = <$handle>;
    close $handle or die $!;
    return $text;
}

sub _quote {
    my ($value) = @_;
    $value =~ s/\\/\\\\/g;
    $value =~ s/'/\\'/g;
    return $value;
}

sub _shell_quote {
    my ($value) = @_;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}
