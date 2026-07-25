#!/usr/bin/env perl
use strict;
use warnings;
use ExtUtils::MakeMaker;

# Makefile.PL provides conventional Perl dependency discovery and distribution
# metadata.  installer/install-postfilter performs the INN-specific deployment,
# path discovery, key creation, SQLite initialization and staged hook creation.
WriteMakefile(
    NAME             => 'Postfilter::NG',
    VERSION          => '2026.007005_004',
    MIN_PERL_VERSION => '5.038000',
    PREREQ_PM        => {
        'Crypt::Mode::CBC' => 0,
        'Date::Parse'      => 0,
        'DBD::SQLite'      => 0,
        'DBI'              => 0,
        'Net::DNS'         => 0,
        'TOML::Tiny'       => 0,
    },
    ABSTRACT => 'Audit-ready nnrpd posting filter for INN',
    AUTHOR   => 'Ivo Gandolfo and Postfilter-NG contributors',
    LICENSE  => 'bsd',
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            homepage => 'https://github.com/infybofh/postfilter-ng',
            repository => {
                type => 'git',
                url  => 'https://github.com/infybofh/postfilter-ng.git',
                web  => 'https://github.com/infybofh/postfilter-ng',
            },
            bugtracker => {
                web => 'https://github.com/infybofh/postfilter-ng/issues',
            },
        },
    },
);
