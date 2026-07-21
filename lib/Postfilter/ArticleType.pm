package Postfilter::ArticleType;

use strict;
use warnings;

=head1 NAME

Postfilter::ArticleType - Early text/binary article classification for mixed readers.

=head1 DESCRIPTION

Postfilter-NG supports two server modes:

=over 4

=item * C<text-only>

Every article uses the text policy.  yEnc and uuencode remain forbidden unless the
newsmaster explicitly changes the text content policy.  Binary-looking group names
are not special in this mode.

=item * C<mixed>

Each newsgroup is matched against the configurable binary-group glob list.  If all
newsgroups match, the article uses the binary policy.  If none match, it uses the
text policy.  If text and binary groups are mixed in one C<Newsgroups> header, the
article is classified C<mixed> and must be rejected before ordinary filtering.

=back

Classification deliberately uses group names rather than body markers.  A plain
text discussion article posted to C<alt.binaries.*> is still a binary-world article,
while a yEnc payload posted to a text group remains a text-world article and is
rejected by the text content policy.

The configured patterns use shell-style globs, not Perl regular expressions:
C<*> matches zero or more characters and C<?> matches exactly one character.  All
other regex metacharacters are escaped and matching is case-insensitive.

=cut

my %COMPILED_PATTERN_CACHE;

=head2 classify($config, $newsgroups)

Returns a hash containing C<article_type>, C<text_groups>, C<binary_groups>, and
C<mixed>.  The method does not reject the article itself; the orchestrator maps a
mixed classification to compatibility code 95.

=cut

sub classify {
    my ($class, $config, $newsgroups) = @_;

    $newsgroups ||= [];
    my $settings = $config->{article_types} || {};
    my $mode = $settings->{mode} // 'text-only';

    if ($mode eq 'text-only') {
        return {
            article_type => 'text',
            binary_groups => [],
            mixed => 0,
            text_groups => [@{$newsgroups}],
        };
    }

    my $pattern_syntax = $settings->{pattern_syntax} // 'glob';
    my $patterns = $settings->{binary_group_patterns} || [];

    # Configuration validation currently permits only shell-style globs.  Keep
    # this explicit guard here as a defence in depth for last-known-good or
    # manually constructed configurations that bypass the normal validator.
    if ($pattern_syntax ne 'glob') {
        return {
            article_type => 'text',
            binary_groups => [],
            mixed => 0,
            text_groups => [@{$newsgroups}],
        };
    }

    my $matchers = _compiled_globs($patterns);
    my (@binary_groups, @text_groups);

    GROUP:
    for my $group (@{$newsgroups}) {
        for my $matcher (@{$matchers}) {
            if ($group =~ $matcher) {
                push @binary_groups, $group;
                next GROUP;
            }
        }
        push @text_groups, $group;
    }

    my $mixed = @binary_groups && @text_groups ? 1 : 0;
    my $article_type = $mixed
        ? 'mixed'
        : @binary_groups
            ? 'binary'
            : 'text';

    return {
        article_type => $article_type,
        binary_groups => \@binary_groups,
        mixed => $mixed,
        text_groups => \@text_groups,
    };
}

=head2 _compiled_globs($patterns)

Compiles and caches the binary-group glob list for the lifetime of one nnrpd
process.  The cache key includes every pattern in order, so a configuration reload
with changed patterns produces a new matcher set without disturbing in-flight
articles.

=cut

sub _compiled_globs {
    my ($patterns) = @_;

    my $cache_key = join "\x1e", @{$patterns};
    return $COMPILED_PATTERN_CACHE{$cache_key}
        if exists $COMPILED_PATTERN_CACHE{$cache_key};

    my @matchers;
    for my $glob (@{$patterns}) {
        next unless defined $glob && length $glob;

        my $regex = quotemeta($glob);
        $regex =~ s/\\\*/.*/g;
        $regex =~ s/\\\?/./g;
        push @matchers, qr/\A$regex\z/i;
    }

    $COMPILED_PATTERN_CACHE{$cache_key} = \@matchers;
    return $COMPILED_PATTERN_CACHE{$cache_key};
}

1;
