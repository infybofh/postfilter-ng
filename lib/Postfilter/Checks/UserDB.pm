package Postfilter::Checks::UserDB;

use strict;
use warnings;

=head1 NAME

Postfilter::Checks::UserDB - Per-newsgroup sender authorisation files.

=head1 FILE FORMAT

When enabled, the module looks for C<GROUP.dat> inside C<userdb.directory>.
Each non-empty, non-comment line contains one normalised email address allowed
to post to that group.  A missing file means that the group has no additional
restriction.  An existing unreadable file is an administrative error and returns
legacy code 105.

Group names are validated before being used in a path, preventing traversal via
malformed Newsgroups values.  Files are cached by path and modification time for
the lifetime of the nnrpd process.

=cut

use File::Spec;

use Postfilter::Codes;
use Postfilter::Result;

my %CACHE;

# Function: run
# Purpose: Checks each posted group’s optional sender-authorisation file.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub run {
    my ($class, $context) = @_;

    unless ($context->{config}{modules}{userdb}) {
        return Postfilter::Result->pass(
            code    => 'PF-AUTH-000',
            legacy  => 0,
            message => 'Per-group user database disabled',
        );
    }

    my $directory = $context->{config}{userdb}{directory} // '';
    return _reject(105)
        unless $directory && -d $directory;

    for my $group (@{ $context->{newsgroups} }) {
        next unless $group =~ /\A[a-z0-9][a-z0-9.+_-]*\z/i;

        my $path = File::Spec->catfile($directory, "$group.dat");
        next unless -e $path;

        my $allowed_senders = _load_sender_file($path);
        return _reject(105, file => $path) unless $allowed_senders;

        my $sender = lc($context->{from_address} // '');
        return _reject(106, group => $group)
            unless $allowed_senders->{$sender};
    }

    return Postfilter::Result->pass(
        code    => 'PF-AUTH-000',
        legacy  => 0,
        message => 'Per-group sender authorisation passed',
    );
}

# Function: _load_sender_file
# Purpose: Loads and mtime-caches one per-group allowed-sender mailbox file.
# Parameters: $path
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _load_sender_file {
    my ($path) = @_;

    my $mtime = (stat($path))[9] // 0;
    if ($CACHE{$path} && $CACHE{$path}{mtime} == $mtime) {
        return $CACHE{$path}{senders};
    }

    open my $handle, '<', $path or return;

    my %senders;
    while (my $line = <$handle>) {
        chomp $line;
        $line =~ s/#.*$//;
        $line =~ s/^\s+|\s+$//g;
        next unless length $line;
        $senders{ lc $line } = 1;
    }

    close $handle;

    $CACHE{$path} = {
        mtime   => $mtime,
        senders => \%senders,
    };

    return \%senders;
}

# Function: _reject
# Purpose: Constructs a rejection result while preserving the historical numeric compatibility
#          code.
# Parameters: $legacy_code, %details
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _reject {
    my ($legacy_code, %details) = @_;
    my ($code, $message) = Postfilter::Codes->lookup($legacy_code);

    return Postfilter::Result->reject(
        code    => $code,
        legacy  => $legacy_code,
        message => $message,
        %details,
    );
}

1;
