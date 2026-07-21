# Contributing to Postfilter-NG

Contributions may include bug fixes, false-positive corrections, performance
improvements, documentation, examples and tests.

## Before opening an issue

- Check the existing issues and current release notes.
- Reproduce the result with the latest release candidate or stable release.
- Record the symbolic `PF-*` code and numeric compatibility code.
- Remove private addresses, authentication data, keys and unrelated article
  content from logs and fixtures.

## Bug reports

Include:

- Postfilter-NG version;
- Perl and INN versions;
- operating system and package versions;
- `text-only` or `mixed` mode;
- relevant sanitized configuration sections;
- article type, newsgroups and MIME structure;
- exact `PF-*` result code;
- sanitized syslog output;
- expected and observed behaviour.

Security reports must use the private process in [`SECURITY.md`](SECURITY.md).

## Development setup

Install runtime and development dependencies:

```sh
cpanm --installdeps .
cpanm Perl::Tidy Perl::Critic
```

Run the complete test suite:

```sh
./tests/run-tests
```

Compile the principal entry points:

```sh
perl -Ilib -c postfilter
perl -Ilib -c bin/postfilterctl
perl -Ilib -c installer/install-postfilter
```

Check formatting and static analysis:

```sh
perltidy -pro=.perltidyrc -b lib/Postfilter/*.pm lib/Postfilter/Checks/*.pm
perlcritic --profile .perlcriticrc lib postfilter bin/postfilterctl
```

Remove any `.bak` files created by local formatting before committing.

## Code requirements

- Use `strict` and `warnings`.
- Keep per-article state inside `Postfilter::Context`.
- Keep configuration immutable unless a documented per-article overlay is used.
- Bound body scans, DNS work, regular-expression work and persistent writes.
- Preserve symbolic and numeric result-code compatibility.
- Add tests for normal input, malformed input and adversarial input.
- Document new configuration parameters in the canonical TOML file and the
  appropriate operator guide.
- Keep release configuration in `audit` unless the change only affects tests or
  documentation.

## Pull requests

A pull request should contain one coherent change and include:

- a concise description;
- affected modules and configuration keys;
- compatibility impact;
- test results;
- documentation updates;
- performance measurements for hot-path changes.

The GitHub test workflow must pass before merge.
