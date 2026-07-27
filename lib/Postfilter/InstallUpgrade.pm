package Postfilter::InstallUpgrade;

use strict;
use warnings;

=head1 NAME

Postfilter::InstallUpgrade - Non-destructive installer upgrade helpers.

=head1 DESCRIPTION

This module contains the filesystem-only operations used while upgrading an
existing Postfilter-NG configuration.  It migrates only exact historical path
defaults, creates timestamped backups before changing operator files and writes
path-adjusted distribution snapshots for manual comparison.

=cut

use Exporter qw(import);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;

our $VERSION = '2026.07.5-rc6';
our @EXPORT_OK = qw(
    migrate_legacy_path_files
    write_distribution_snapshot
);

# Function: migrate_legacy_path_files
# Purpose: Replaces exact historical default paths in existing TOML files after backing them up.
# Parameters: %arguments containing files, replacements, config_root, backup_root and optional log.
# Operational notes: A path is replaced only when followed by a slash, quote or end of input;
#                    custom paths that merely share a prefix are preserved.
sub migrate_legacy_path_files {
    my (%arguments) = @_;

    my $files = $arguments{files} // [];
    my $replacements = $arguments{replacements} // [];
    my $config_root = $arguments{config_root};
    my $backup_root = $arguments{backup_root};
    my $log = $arguments{log};

    die "config_root is required\n" unless defined $config_root && length $config_root;
    die "backup_root is required\n" unless defined $backup_root && length $backup_root;
    die "files must be an array reference\n" unless ref($files) eq 'ARRAY';
    die "replacements must be an array reference\n" unless ref($replacements) eq 'ARRAY';

    my @changed_files;
    my $replacement_count = 0;

    for my $path (@{$files}) {
        next unless defined $path && -f $path;

        my $text = _read_file($path);
        my $updated = $text;
        my $file_replacements = 0;

        for my $pair (@{$replacements}) {
            die "Each path replacement must contain old and new values\n"
                unless ref($pair) eq 'ARRAY' && @{$pair} == 2;
            my ($old, $new) = @{$pair};
            next unless defined $old && length $old;
            next unless defined $new && length $new;
            next if $old eq $new;

            my $count = ($updated =~ s{\Q$old\E(?=/|["']|\z)}{$new}g);
            $file_replacements += $count;
        }

        next unless $file_replacements;

        my $relative = File::Spec->abs2rel($path, $config_root);
        die "Refusing to back up configuration outside $config_root: $path\n"
            if $relative eq File::Spec->updir
            || $relative =~ m{\A\.\.(?:[\\/]|\z)};

        my $backup = File::Spec->catfile($backup_root, $relative);
        make_path(dirname($backup), { mode => 0750 });
        copy($path, $backup)
            or die "Unable to back up $path to $backup: $!";
        chmod((stat($path))[2] & 07777, $backup)
            or die "Unable to preserve mode on $backup: $!";

        _atomic_write_preserving_mode($path, $updated);
        push @changed_files, $path;
        $replacement_count += $file_replacements;
        $log->($path, $backup, $file_replacements) if $log;
    }

    return {
        backup_root       => @changed_files ? $backup_root : '',
        changed_files     => \@changed_files,
        replacement_count => $replacement_count,
    };
}

# Function: write_distribution_snapshot
# Purpose: Writes one shipped configuration file as a path-adjusted .dist comparison copy.
# Parameters: %arguments containing source, destination and replacements.
# Operational notes: Existing .dist files are replaced; active operator configuration is untouched.
sub write_distribution_snapshot {
    my (%arguments) = @_;

    my $source = $arguments{source};
    my $destination = $arguments{destination};
    my $replacements = $arguments{replacements} // [];

    die "source is required\n" unless defined $source && -f $source;
    die "destination is required\n"
        unless defined $destination && length $destination;
    die "replacements must be an array reference\n"
        unless ref($replacements) eq 'ARRAY';

    my $text = _read_file($source);
    for my $pair (@{$replacements}) {
        die "Each path replacement must contain old and new values\n"
            unless ref($pair) eq 'ARRAY' && @{$pair} == 2;
        my ($old, $new) = @{$pair};
        next unless defined $old && length $old;
        next unless defined $new && length $new;
        next if $old eq $new;
        $text =~ s{\Q$old\E(?=/|["']|\z)}{$new}g;
    }

    make_path(dirname($destination), { mode => 0750 });
    _atomic_write_preserving_mode($destination, $text, 0640);
    return;
}

# Function: _read_file
# Purpose: Reads one file without character decoding.
# Parameters: $path
# Operational notes: Configuration is treated as bytes so comments and formatting are preserved.
sub _read_file {
    my ($path) = @_;
    open my $handle, '<:raw', $path or die "Unable to read $path: $!";
    local $/;
    my $text = <$handle>;
    close $handle or die "Unable to close $path: $!";
    return $text;
}

# Function: _atomic_write_preserving_mode
# Purpose: Atomically replaces one file while retaining or explicitly setting its mode.
# Parameters: $path, $text, optional $mode
# Operational notes: Ownership is normalized by the installer after migration.
sub _atomic_write_preserving_mode {
    my ($path, $text, $mode) = @_;
    $mode //= (-e $path ? ((stat($path))[2] & 07777) : 0640);

    my $temporary = "$path.tmp.$$";
    open my $handle, '>:raw', $temporary
        or die "Unable to create $temporary: $!";
    print {$handle} $text
        or die "Unable to write $temporary: $!";
    close $handle
        or die "Unable to close $temporary: $!";
    chmod $mode, $temporary
        or die "Unable to chmod $temporary: $!";
    rename $temporary, $path
        or die "Unable to activate $path: $!";
    return;
}

1;
