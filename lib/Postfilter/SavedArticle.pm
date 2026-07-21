package Postfilter::SavedArticle;

use strict;
use warnings;

=head1 NAME

Postfilter::SavedArticle - Collision-safe storage of rejected or selected posts.

=head1 DESCRIPTION

The approved filename format sorts chronologically and remains human-readable:

  1784488123.483921.PF-MIME-003.a4f982b68d128bc73e71a977.post

Files are created with C<O_EXCL>; a numeric suffix is used only if two processes
somehow produce the same timestamp, reason code and Message-ID hash.  The saved
copy receives diagnostic headers, but the live article hash is restored before
returning to INN.

=cut

use Digest::SHA qw(sha256_hex);
use Fcntl qw(:DEFAULT);
use File::Path qw(make_path);
use File::Spec;
use Time::HiRes qw(gettimeofday);

use Postfilter::Article;

# Function: save
# Purpose: Saves the complete current article with an exclusive chronological name and returns
#          metadata.
# Parameters: $class, $context, $result
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub save {
    my ($class, $context, $result) = @_;

    my $base_directory =
        $context->{config}{paths}{saved_dir}
        // '/var/spool/news/postfilter-ng/rejected';

    my ($seconds, $microseconds) = gettimeofday;
    my $layout =
        $context->{config}{saved_articles}{directory_layout}
        // 'year/month/day';

    # Keep text and binary diagnostics in independent directory trees.
    # The subdirectory is configurable per article type, but is sanitised before
    # being used as a filesystem component.
    my $type_subdirectory = $context->saved_article_subdirectory;
    $type_subdirectory =~ s/[^A-Za-z0-9_.-]+/-/g;

    my $directory = File::Spec->catdir(
        $base_directory,
        $type_subdirectory,
    );
    if ($layout eq 'year/month/day') {
        my @time = gmtime($seconds);
        $directory = File::Spec->catdir(
            $directory,
            sprintf('%04d', $time[5] + 1900),
            sprintf('%02d', $time[4] + 1),
            sprintf('%02d', $time[3]),
        );
    }

    make_path($directory, { mode => 0750 }) unless -d $directory;

    my $message_id_hash = substr(
        sha256_hex($context->{message_id} // ''),
        0,
        24,
    );
    my $timestamp = sprintf('%d.%06d', $seconds, $microseconds);
    my $reason_code = $result->{code} // 'PF-INTERNAL-000';
    $reason_code =~ s/[^A-Za-z0-9-]+/-/g;

    my $base_name = "$timestamp.$reason_code.$message_id_hash";
    my $path = File::Spec->catfile($directory, "$base_name.post");

    my $handle;
    my $collision = 0;
    while (!sysopen($handle, $path, O_WRONLY | O_CREAT | O_EXCL, 0640)) {
        $collision++;
        die "Unable to create a unique saved-article filename: $!"
            if $collision > 100;
        $path = File::Spec->catfile(
            $directory,
            "$base_name.$collision.post",
        );
    }

    binmode $handle;

    my $original_reason = $context->{headers}{'X-Postfilter-Error'};
    my $original_legacy = $context->{headers}{'X-Postfilter-Legacy-Code'};
    my $original_article_type =
        $context->{headers}{'X-Postfilter-Article-Type'};

    $context->{headers}{'X-Postfilter-Error'} = $result->{code};
    $context->{headers}{'X-Postfilter-Legacy-Code'} = $result->{legacy};
    $context->{headers}{'X-Postfilter-Article-Type'} =
        $context->{article_type} // 'text';

    my $article = Postfilter::Article->serialize($context);
    print {$handle} $article
        or die "Unable to write saved article $path: $!";
    close $handle
        or die "Unable to close saved article $path: $!";

    if (defined $original_reason) {
        $context->{headers}{'X-Postfilter-Error'} = $original_reason;
    }
    else {
        $context->{headers}{'X-Postfilter-Error'} = undef;
    }

    if (defined $original_legacy) {
        $context->{headers}{'X-Postfilter-Legacy-Code'} = $original_legacy;
    }
    else {
        $context->{headers}{'X-Postfilter-Legacy-Code'} = undef;
    }

    if (defined $original_article_type) {
        $context->{headers}{'X-Postfilter-Article-Type'} =
            $original_article_type;
    }
    else {
        $context->{headers}{'X-Postfilter-Article-Type'} = undef;
    }

    $context->{saved_path} = $path;

    return {
        article_type => $context->{article_type} // 'text',
        created_at   => $context->{received_at},
        path         => $path,
        sha256     => sha256_hex($article),
        size       => length($article),
    };
}

1;
