# Postfilter-NG configuration tree

The installer copies `postfilter.toml` and every `conf.d/*.toml` file into the
configured INN administration directory, normally `/etc/news/postfilter-ng`.
Existing files remain unchanged during an upgrade unless `--force-config` is
specified.

`postfilter.toml` contains global behaviour, paths, failure policy and the
`text-only`/`mixed` article profiles. Numbered fragments contain rule and profile
lists. Files are loaded in lexicographic order. Arrays of tables such as
`[[ban_rule]]`, `[[badword]]` and `[[trusted_profile]]` are appended across
fragments. Scalar and ordinary table values in a later fragment replace earlier
values.

The shipped files include detailed comments, valid values, units and examples.
Validate the complete tree before activation:

```sh
postfilterctl check-config --config /etc/news/postfilter-ng/postfilter.toml
```

A malformed TOML generation is ignored. The filter continues with the previous
in-memory configuration or the persistent last-known-good JSON snapshot.
