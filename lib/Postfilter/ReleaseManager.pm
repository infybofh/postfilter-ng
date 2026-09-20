package Postfilter::ReleaseManager;

use strict;
use warnings;

=head1 NAME

Postfilter::ReleaseManager - Managed release markers and generated INN hook wrappers.

=head1 DESCRIPTION

Provides the small, filesystem-focused primitives used by the installer to
identify immutable Postfilter-NG releases and to create regular
C<filter_nnrpd.pl> wrapper files.  All release paths are confined below the
configured C<releases> directory before destructive operations are allowed.

=cut

use Cwd qw(abs_path);
use File::Spec;
use JSON::PP;
use POSIX qw(strftime);

our $VERSION = '2026.09.1-rc3';

use Exporter qw(import);
our @EXPORT_OK = qw(
    parse_hook_wrapper
    read_release_marker
    release_dir_is_managed
    safe_release_directory
    write_hook_wrapper
    write_release_marker
);

=head2 _single_quoted_perl

Build a safe single-quoted Perl literal for generated wrapper source.  Newline
characters are rejected so wrapper metadata cannot inject additional code.

=cut

sub _single_quoted_perl {
    my ($value) = @_;
    die "Undefined wrapper value\n" unless defined $value;
    die "Unsafe newline in wrapper value\n" if $value =~ /[\r\n]/;
    $value =~ s/\\/\\\\/g;
    $value =~ s/'/\\'/g;
    return "'$value'";
}

=head2 safe_release_directory

Resolve a proposed release directory and return it only when it is a child of
the configured immutable-release root.  The root itself is never accepted.

=cut

sub safe_release_directory {
    my ($prefix, $directory) = @_;
    return unless defined $prefix && defined $directory;

    my $release_root = File::Spec->catdir($prefix, 'releases');
    my $root_abs = abs_path($release_root) // File::Spec->rel2abs($release_root);
    my $directory_abs = abs_path($directory) // File::Spec->rel2abs($directory);

    $root_abs =~ s{/+\z}{};
    return if $directory_abs eq $root_abs;
    return unless index($directory_abs, "$root_abs/") == 0;
    return $directory_abs;
}

=head2 write_release_marker

Write the canonical JSON marker that identifies a directory as installer
managed.  The temporary file is renamed into place to avoid partial markers.

=cut

sub write_release_marker {
    my (%argument) = @_;
    my $directory = $argument{directory}
        or die "write_release_marker requires directory\n";
    my $version = $argument{version}
        or die "write_release_marker requires version\n";

    die "Unsafe release version '$version'\n"
        unless $version =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;

    my $path = File::Spec->catfile($directory, '.postfilter-ng-release.json');
    my $temporary = "$path.tmp.$$";
    my $payload = {
        format          => 1,
        version         => $version,
        installed_at    => $argument{installed_at}
            // strftime('%Y-%m-%dT%H:%M:%SZ', gmtime()),
        installed_epoch => $argument{installed_epoch} // time,
        legacy          => $argument{legacy}
            ? JSON::PP::true
            : JSON::PP::false,
    };

    open my $handle, '>:raw', $temporary
        or die "Unable to create $temporary: $!";
    print {$handle} JSON::PP->new->canonical->pretty->encode($payload)
        or die "Unable to write $temporary: $!";
    close $handle or die "Unable to close $temporary: $!";
    chmod 0644, $temporary or die "Unable to chmod $temporary: $!";
    rename $temporary, $path or die "Unable to activate $path: $!";
    return $path;
}

=head2 read_release_marker

Read and minimally validate a managed-release JSON marker.  Invalid or absent
markers return no value and therefore cannot authorize cleanup.

=cut

sub read_release_marker {
    my ($directory) = @_;
    return unless defined $directory;
    my $path = File::Spec->catfile($directory, '.postfilter-ng-release.json');
    return unless -f $path;

    open my $handle, '<:raw', $path or return;
    local $/;
    my $text = <$handle>;
    close $handle;
    my $decoded = eval { JSON::PP->new->decode($text) };
    return unless $decoded && ref($decoded) eq 'HASH';
    return unless ($decoded->{format} // 0) == 1;
    return unless ($decoded->{version} // '')
        =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;
    return $decoded;
}

=head2 release_dir_is_managed

Check both path confinement and the release marker.  Returns the canonical
release path and decoded marker only when both checks succeed.

=cut

sub release_dir_is_managed {
    my ($prefix, $directory) = @_;
    my $safe = safe_release_directory($prefix, $directory) or return;
    my $marker = read_release_marker($safe) or return;
    return ($safe, $marker);
}

=head2 write_hook_wrapper

Generate a regular INN Perl hook wrapper pinned to one immutable release.  The
wrapper loads the release-local modules and verifies that C<filter_post()> was
defined.  Source execute permission is deliberately not required.

=cut

sub write_hook_wrapper {
    my (%argument) = @_;
    my $path = $argument{path} or die "write_hook_wrapper requires path\n";
    my $release_dir = $argument{release_dir}
        or die "write_hook_wrapper requires release_dir\n";
    my $version = $argument{version}
        or die "write_hook_wrapper requires version\n";
    my $perl = $argument{perl} // '/usr/bin/env perl';

    die "Unsafe release version '$version'\n"
        unless $version =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;
    die "Release directory must be absolute\n"
        unless File::Spec->file_name_is_absolute($release_dir);
    die "Perl interpreter must be absolute or /usr/bin/env perl\n"
        unless File::Spec->file_name_is_absolute($perl)
            || $perl eq '/usr/bin/env perl';

    my $quoted_release = _single_quoted_perl($release_dir);
    my $quoted_lib = _single_quoted_perl(
        File::Spec->catdir($release_dir, 'lib'),
    );
    my $quoted_entry = _single_quoted_perl(
        File::Spec->catfile($release_dir, 'postfilter'),
    );
    my $shebang = $perl eq '/usr/bin/env perl'
        ? '#!/usr/bin/env perl'
        : "#!$perl";

    my $contents = <<"WRAPPER";
$shebang
# Generated by Postfilter-NG. Do not edit this file in place.
# POSTFILTER_NG_WRAPPER_FORMAT=1
# POSTFILTER_NG_RELEASE_VERSION=$version
# POSTFILTER_NG_RELEASE_DIR=$release_dir

use strict;
use warnings;

BEGIN {
    unshift \@INC, $quoted_lib;
}

my \$postfilter_ng_release_dir = $quoted_release;
my \$postfilter_ng_entry_point = $quoted_entry;
my \$postfilter_ng_loaded = do \$postfilter_ng_entry_point;

die "Perl load error in \$postfilter_ng_entry_point: \$\@" if \$\@;
die "Operating-system error loading \$postfilter_ng_entry_point: \$!"
    unless defined \$postfilter_ng_loaded;
die "Postfilter-NG entry point returned false: \$postfilter_ng_entry_point\n"
    unless \$postfilter_ng_loaded;
die "Postfilter-NG entry point did not define filter_post()\n"
    unless defined &filter_post;

1;
WRAPPER

    my $temporary = "$path.tmp.$$";
    open my $handle, '>:raw', $temporary
        or die "Unable to create $temporary: $!";
    print {$handle} $contents or die "Unable to write $temporary: $!";
    close $handle or die "Unable to close $temporary: $!";
    chmod 0644, $temporary or die "Unable to chmod $temporary: $!";
    rename $temporary, $path
        or die "Unable to activate hook wrapper $path: $!";
    return $path;
}

=head2 parse_hook_wrapper

Read metadata comments from a generated regular hook wrapper.  Symlinks and
unrecognized files are intentionally rejected so cleanup cannot trust them.

=cut

sub parse_hook_wrapper {
    my ($path) = @_;
    return unless defined $path && -f $path && !-l $path;

    open my $handle, '<:raw', $path or return;
    my %metadata;
    while (my $line = <$handle>) {
        last if $. > 20;
        if ($line =~ /^# POSTFILTER_NG_WRAPPER_FORMAT=(\d+)\s*$/) {
            $metadata{format} = 0 + $1;
        }
        elsif ($line =~ /^# POSTFILTER_NG_RELEASE_VERSION=([^\r\n]+)\s*$/) {
            $metadata{version} = $1;
        }
        elsif ($line =~ /^# POSTFILTER_NG_RELEASE_DIR=([^\r\n]+)\s*$/) {
            $metadata{release_dir} = $1;
        }
    }
    close $handle;

    return unless ($metadata{format} // 0) == 1;
    return unless ($metadata{version} // '')
        =~ /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/;
    return unless defined $metadata{release_dir}
        && File::Spec->file_name_is_absolute($metadata{release_dir});
    return \%metadata;
}

1;
