package Postfilter::CodeReference;

use strict;
use warnings;

use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec;
use Postfilter::Codes;

=head1 NAME

Postfilter::CodeReference - Operator/developer reference metadata for PF-* result codes.

=head1 DESCRIPTION

Provides a single source for C<postfilterctl explain-code> and the generated
C<docs/ERROR-CODES.md>.  Runtime call-sites are discovered from the installed
release tree so file and line references always describe the exact release.

=cut

my %HINT = (
    1   => ['style.control', 'Control header policy'],
    2   => ['conf.d/10-structural-rules.toml: forbidden_crosspost', 'Forbidden crosspost rule'],
    3   => ['moderation/Approved policy', 'Approved header policy'],
    4   => ['headers.check_distribution / distributions', 'Distribution header policy'],
    5   => ['content_type_rule / article type checks', 'Content-Type policy'],
    6   => ['limits.max_crosspost', 'Newsgroups target limit'],
    7   => ['limits.max_followup', 'Followup-To target limit'],
    8   => ['limits.max_fup_no_crosspost', 'Followup-To requirement'],
    9   => ['limits.max_body_size', 'Legacy body-size limit'],
    10  => ['limits.max_groups_difference', 'Crosspost/followup difference limit'],
    11  => ['header style policy', 'References required for Re:'],
    12  => ['limits.max_line_length', 'Maximum body line length'],
    13  => ['limits.max_quoted_ratio', 'Quoted-line ratio'],
    14  => ['limits.max_blank_ratio', 'Blank-line ratio'],
    15  => ['limits.max_empty_ratio', 'Empty-line ratio'],
    16  => ['headers.allow_html / html_allowed_groups / html_patterns', 'HTML policy'],
    17  => ['headers.check_groups_existence / paths.active_file', 'Newsgroups existence'],
    18  => ['headers.check_groups_existence / paths.active_file', 'Followup-To group existence'],
    19  => ['date policy', 'Missing, invalid or future Date'],
    20  => ['headers.path', 'Path syntax/policy'],
    21  => ['limits.max_header_length', 'Individual header length'],
    22  => ['headers.allow_mail_headers / headers.delete_mail_headers', 'Mail-header policy'],
    23  => ['limits.max_header_size', 'Legacy aggregate header size'],
    24  => ['header style policy', 'In-Reply-To syntax'],
    25  => ['limits.max_hierarchies_post', 'Newsgroups hierarchy limit'],
    26  => ['limits.max_hierarchies_followup', 'Followup-To hierarchy limit'],
    27  => ['conf.d/50-badwords.toml', 'Badword configuration'],
    28  => ['badwords.max_subject_score / badword rules', 'Subject badword score'],
    29  => ['badwords.max_body_score / badword rules', 'Body badword score'],
    30  => ['limits.default_multipost_limit / limits.absolute_multipost_limit / access_profile.limits.multipost', 'Multipost limit'],
    34  => ['conf.d/60-banlist.toml', 'Banlist rule'],
    35  => ['conf.d/60-banlist.toml', 'Banlist configuration'],
    36  => ['database.*', 'Database connection'],
    37  => ['paths.active_file', 'INN active file'],
    38  => ['conf.d/50-badwords.toml', 'Badword configuration load'],
    39  => ['conf.d/60-banlist.toml', 'Banlist configuration load'],
    40  => ['database.* / policy database failure action', 'Persistent storage failure'],
    41  => ['saved_articles.*', 'Rejected-article diagnostic saving'],
    42  => ['installer --innconfval / PATH', 'INN path discovery'],
    43  => ['postfilter.toml / conf.d', 'Main configuration load'],
    44  => ['database.*', 'Audit-event write'],
    45  => ['retention.* / maintenance', 'Database expiry/maintenance'],
    46  => ['database.*', 'Database spool operation'],
    47  => ['policy.action_on_reject', 'Default rejection policy'],
    48  => ['posting policy', 'Server closed for posting'],
    49  => ['banlist.max_score', 'Banlist score ceiling'],
    50  => ['tor.action / tor.*', 'TOR policy'],
    51  => ['style.control', 'Supersedes/Replaces/Cancel policy'],
    52  => ['article_types.text.content.allow_uuencode', 'UUEncode text policy'],
    53  => ['forbidden_header_rule', 'Forged/system header protection'],
    54  => ['conf.d/10-structural-rules.toml: forbidden_groups', 'Closed-to-posting group policy'],
    55  => ['runtime module loading', 'Internal module failure'],
    56  => ['conf.d/40-reputation.toml: dnsbl', 'DNSBL policy'],
    57  => ['limits.max_total_size', 'Legacy total article-size limit'],
    58  => ['date policy', 'Maximum article age'],
    59  => ['paths.public_suffix_file', 'Public suffix data'],
    60  => ['conf.d/40-reputation.toml: surbl', 'SURBL policy'],
    61  => ['conf.d/40-reputation.toml: uribl', 'URIBL policy'],
    62  => ['article_types.text.content.allow_yenc', 'yEnc text policy'],
    63  => ['custom.* / conf/custom.pm', 'Custom rule rejection'],
    91  => ['banlist/badword/custom output action', 'Explicit sender/rule rejection'],
    92  => ['postfilter.toml', 'Main configuration syntax'],
    93  => ['conf.d/30-access-profiles.toml', 'Access configuration syntax'],
    94  => ['conf.d rule files', 'Rule configuration syntax'],
    95  => ['article_types.mixed_crosspost_policy', 'Text/binary mixed crosspost invariant'],
    96  => ['article_types.text.limits.max_body_size', 'Text body size'],
    97  => ['article_types.text.limits.max_header_size', 'Text header size'],
    98  => ['article_types.text.limits.max_total_size', 'Text total size'],
    99  => ['article_types.binary.limits.max_body_size', 'Binary body size'],
    100 => ['article_types.binary.limits.max_header_size', 'Binary header size'],
    101 => ['article_types.binary.limits.max_total_size', 'Binary total size'],
    102 => ['article_types.binary.content.allow_yenc / allow_uuencode', 'Binary payload policy'],
    103 => ['article_types.*', 'Invalid article-type policy fallback'],
    104 => ['header character validation', 'Forbidden/invalid header character'],
    105 => ['userdb.*', 'Per-group user database load'],
    106 => ['userdb.*', 'Per-group sender authorization'],
    107 => ['distributions / database.*', 'Local Distribution state'],
    108 => ['distributions / headers.check_distribution', 'Distribution value validation'],
    109 => ['article_types.text.mime', 'multipart/mixed text policy'],
    110 => ['article_types.text.mime.allowed_media_types / forbidden_media_types', 'MIME media policy'],
    111 => ['article_types.text.mime', 'MIME attachment metadata'],
    112 => ['article_types.text.mime Base64 thresholds', 'Probable Base64 attachment'],
    113 => ['article_types.text.mime.on_malformed', 'Malformed MIME policy'],
    114 => ['article_types.text.mime.allowed_multipart_types', 'Multipart container policy'],
    115 => ['Newsgroups structural preflight', 'RFC 5536 Newsgroups syntax'],
    116 => ['Followup-To structural preflight', 'RFC 5536 Followup-To syntax'],
);

for my $code (31 .. 33) { $HINT{$code} = ['access.*_limits.max_articles / access_profile.limits.max_articles', 'Long-window article rate']; }
for my $code (64 .. 66) { $HINT{$code} = ['access.*_limits.max_total_errors / access_profile.limits.max_total_errors', 'Long-window error rate']; }
for my $code (67 .. 69) { $HINT{$code} = ['access.*_limits.max_short_errors / access_profile.limits.max_short_errors', 'Short-window error rate']; }
for my $code (70 .. 72) { $HINT{$code} = ['access.*_limits.max_short_articles / access_profile.limits.max_short_articles', 'Short-window article rate']; }
for my $code (73 .. 75) { $HINT{$code} = ['access.*_limits.max_short_size / access_profile.limits.max_short_size', 'Short-window byte rate']; }
for my $code (76 .. 78) { $HINT{$code} = ['access.*_limits.max_total_size / access_profile.limits.max_total_size', 'Long-window byte rate']; }
for my $code (79 .. 81) { $HINT{$code} = ['access.*_limits.max_short_groups / access_profile.limits.max_short_groups', 'Short-window Newsgroups target rate']; }
for my $code (82 .. 84) { $HINT{$code} = ['access.*_limits.max_total_groups / access_profile.limits.max_total_groups', 'Long-window Newsgroups target rate']; }
for my $code (85 .. 87) { $HINT{$code} = ['access.*_limits.max_short_followups / access_profile.limits.max_short_followups', 'Short-window Followup-To target rate']; }
for my $code (88 .. 90) { $HINT{$code} = ['access.*_limits.max_total_followups / access_profile.limits.max_total_followups', 'Long-window Followup-To target rate']; }

# Function: project_root
# Purpose: Resolves the root directory of the exact installed or source release.
# Parameters: None.
# Operational notes: File and line references are always relative to this release root.
sub project_root {
    my $module = abs_path(__FILE__) // __FILE__;
    return dirname(dirname(dirname($module)));
}

# Function: resolve
# Purpose: Resolves a numeric or symbolic PF-* code into operator/developer reference metadata.
# Parameters: $class, $query
# Operational notes: Unknown or mismatched symbolic codes return undef rather than guessing.
sub resolve {
    my ($class, $query) = @_;
    return unless defined $query;
    my $all = Postfilter::Codes->all;
    my $numeric;
    if ($query =~ /^\d+$/) {
        $numeric = 0 + $query;
    } elsif ($query =~ /^PF-[A-Z]+-(\d{3})$/) {
        $numeric = 0 + $1;
        return unless exists $all->{$numeric} && $all->{$numeric}{code} eq $query;
    } else {
        return;
    }
    return unless exists $all->{$numeric};
    my $entry = { legacy => $numeric, %{ $all->{$numeric} } };
    my ($config, $trigger) = @{ $HINT{$numeric} // ['n/a', 'Compatibility/reserved code or internal condition'] };
    $entry->{configuration} = $config;
    $entry->{trigger} = $trigger;
    $entry->{call_sites} = $class->call_sites($numeric, $entry->{code});
    $entry->{status} = @{ $entry->{call_sites} } ? 'active' : 'compatibility/reserved';
    return $entry;
}

# Function: call_sites
# Purpose: Finds exact runtime source locations that emit or map one result code in this release.
# Parameters: $class, $numeric, $symbolic
# Operational notes: Codes.pm and this module are excluded so definitions are not mistaken for emitters.
sub call_sites {
    my ($class, $numeric, $symbolic) = @_;
    my $root = project_root();
    my @files;
    find(sub {
        return unless -f $_;
        my $relative = File::Spec->abs2rel($File::Find::name, $root);
        return unless $relative eq 'postfilter' || $relative =~ m{^(?:lib/Postfilter|bin|installer)/.*(?:\.pm|postfilterctl|install-postfilter)$};
        return if $relative eq 'lib/Postfilter/Codes.pm' || $relative eq 'lib/Postfilter/CodeReference.pm';
        push @files, [$File::Find::name, $relative];
    }, $root);

    my @sites;
    for my $pair (@files) {
        my ($path, $relative) = @$pair;
        open my $fh, '<', $path or next;
        my ($line_no, $sub) = (0, '<file scope>');
        while (my $line = <$fh>) {
            ++$line_no;
            $sub = $1 if $line =~ /^sub\s+([A-Za-z0-9_]+)/;
            my $match = index($line, $symbolic) >= 0;
            $match ||= $line =~ /(?:_reject|_create_rejection_result)\s*\(\s*\Q$numeric\E\b/;
            $match ||= $line =~ /Postfilter::Result->(?:reject|error)\s*\([^\n]*\blegacy\s*=>\s*\Q$numeric\E\b/;
            next unless $match;
            push @sites, { file => $relative, line => $line_no, function => $sub };
        }
        close $fh;
    }
    my %seen;
    return [ grep { !$seen{join(':', $_->{file}, $_->{line})}++ } @sites ];
}

# Function: all_references
# Purpose: Returns reference metadata for every stable historical code in numeric order.
# Parameters: $class
# Operational notes: Used by both the documentation generator and consistency tests.
sub all_references {
    my ($class) = @_;
    my $all = Postfilter::Codes->all;
    return [ map { $class->resolve($_) } sort { $a <=> $b } keys %$all ];
}

1;
