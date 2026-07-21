# Runtime dependencies for Postfilter-NG.
requires 'perl', '5.038000';
#
# The installer checks every module before activation.  The filter can still
# fall back to a last-known-good JSON snapshot when TOML parsing is temporarily
# unavailable, but a supported installation is expected to provide all modules.
requires 'DBI';
requires 'DBD::SQLite';
requires 'Net::DNS';
requires 'Date::Parse';
requires 'Crypt::Mode::CBC';
requires 'TOML::Tiny';

# Development-only tools.  They are not required by nnrpd at runtime, but they
# are used by maintainers before creating a release archive.
on 'develop' => sub {
    requires 'Perl::Tidy';
    requires 'Perl::Critic';
    requires 'Test::More';
};
