# Migration from Postfilter 0.9.x

Postfilter-NG reads TOML configuration and does not execute the old Perl
configuration files. Migrate settings into a separate staging tree while the
production filter remains unchanged.

## Migration sequence

1. Copy the shipped `conf/` tree to the staging configuration directory.
2. Transfer site values into the matching TOML sections.
3. Convert whitelist entries into `[[trusted_profile]]` tables.
4. Convert `badwords.conf` entries into `[[badword]]` tables.
5. Convert banlist entries into `[[ban_rule]]` tables with stable IDs.
6. Express network matches as CIDR values.
7. Run `postfilterctl check-config`.
8. Test representative articles with `postfilterctl explain`.
9. Install with `policy.mode = "audit"`.
10. Compare SQLite events, reports and saved diagnostics before enforcement.

`access.log`, `legal.log`, `postlegal.log` and MySQL history are not imported by
the installer. A site-specific importer may load historical records into a
separate archive after schema, retention and privacy requirements are reviewed.

Cancel-Lock and Cancel-Key processing remains under INN.

## Main `%config` keys

| Historical key | New location or replacement | Notes |
|---|---|---|
| `salt` | `headers.pseudonym_key_file` | Unkeyed MD5 salt replaced by a restricted HMAC-SHA-256 key file. |
| `server_status` | `policy.server_status` | `active`, `closed`, `disabled` retained. |
| `server_type` | `access.server_type` | `public`, `auth`, `both` retained. |
| `enable_domain_check` | `access.enable_domain_check` | Retained. |
| `default_action_on_accept` | `policy.action_on_accept` | `accept`, `discard`, `save`, `reject` retained. |
| `default_action_on_reject` | `policy.action_on_reject` | Retained; one final SQLite event avoids contradictory records. |
| `public_user_id` | `access.public_user_pattern` | Same regex is used by every storage path. |
| `reject_on_badwords_error` | `resilience.disable_invalid_individual_rules` plus LKG | Broken individual rules are isolated; a wholly broken source falls back to LKG. |
| `reject_on_banlist_error` | `resilience.disable_invalid_individual_rules` plus LKG | No single malformed rule can close posting. |
| `show_error_code` | `policy.show_error_code` | Retained. |
| `period` | `access.period_seconds` | Retained. |
| `short_period` | `access.short_period_seconds` | Retained. |
| `trash_period` | No automatic expiry | Event history defaults to `forever`. Deletion uses an explicit audited `postfilterctl purge --before ... --confirm` command. |
| `enable_mysql` | `database.enabled` | MySQL implementation removed; functionality moved to SQLite. |
| `check_groups_existence` | `headers.check_groups_existence`, `modules.groups` | Retained with active-file cache. |
| `check_users` | `modules.access` | Retained. |
| `check_tor` | `modules.tor`, `tor.enabled` | Retained. |
| `tor_network` | `tor.action` | `allow`, `mark`, `reject` retained. |
| `check_white-list` | `trusted_profile` tables | Replaced by fully selectable profiles. |
| `check_custom` | `modules.custom` | Retained; default operational config includes a safe passing `custom.pm`. |
| `check_banlist` | `modules.banlist` | Retained. |
| `score_banlist` | `banlist.max_score` | Retained, including named `setmax` overrides. |
| `check_rbl` | `modules.rbl` | Retained. |
| `check_uribl` | `modules.uribl` | Retained. |
| `check_surbl` | `modules.surbl` | Retained. |
| `check_uriblcom` | individual `[[uribl]]` providers | Provider-specific switch replaces hardcoding. |
| `check_badwords` | `modules.badwords` | Retained. |
| `scan_body` | each `[[badword]].targets` | Per-rule selection is more precise. |
| `max_score_on_body` | `badwords.max_body_score` | Retained. |
| `scan_subject` | each `[[badword]].targets` | Per-rule selection is more precise. |
| `max_score_on_subject` | `badwords.max_subject_score` | Retained. |
| `allow_control_cancel` | `headers.allow_control_cancel` | Retained. Cancel-Lock and Cancel-Key remain under INN control. |
| `allow_supersedes` | `headers.allow_supersedes` | Covers Supersedes/Replaces/Cancel policy. |
| `allow_uuencode` | `headers.allow_uuencode` | Retained. |
| `allow_yenc` | `headers.allow_yenc` | Retained. |
| `allow_html` | `headers.allow_html` | Retained with group exceptions. |
| `allow_mail_headers` | `headers.allow_mail_headers` | Retained. |
| `check_distribution` | `headers.check_distribution` | Retained. |
| `max_crosspost` | `limits.max_crosspost` | Retained. |
| `max_followup` | `limits.max_followup` | Retained. |
| `max_fup_no_crsspt` | `limits.max_fup_no_crosspost` | Spelling corrected. |
| `max_groups_difference` | `limits.max_groups_difference` | Retained. |
| `max_hierarchies_post` | `limits.max_hierarchies_post` | Retained. |
| `max_hierarchies_followup` | `limits.max_hierarchies_followup` | Correctly used rather than the post limit. |
| `max_body_size` | `limits.max_body_size` | Retained. |
| `max_head_size` | `limits.max_header_size` | Name clarified. |
| `max_total_size` | `limits.max_total_size` | Retained. |
| `max_header_length` | `limits.max_header_length` | Retained. |
| `max_line_length` | `limits.max_line_length` | Zero still disables the check. |
| `max_quoted_ratio` | `limits.max_quoted_ratio` | Retained. |
| `max_blank_ratio` | `limits.max_blank_ratio` | Retained with corrected line counting. |
| `max_empty_ratio` | `limits.max_empty_ratio` | Retained with corrected line counting. |
| `max_grace_time` | `timeouts.future_grace_seconds` | Retained. |
| `too_old_limit` | `timeouts.too_old_seconds` | Retained. |
| `maximum_multipost` | `limits.maximum_multipost` | Retained. |
| `md5_hash` | `access.article_digest_mode` | `body`, `simple`, `complex`, `all` retained; digest is now SHA-256. |
| `force_default_organization` | `headers.force_default_organization` | Retained. |
| `organization` | `headers.organization` | Retained. |
| `delete_path` | `headers.delete_path` | `false`, `true`, `anon` supported. |
| `delete_sender` | `headers.delete_sender` | Retained with HMAC pseudonymization. |
| `delete_posting_host` | `headers.delete_posting_host` | Retained with HMAC pseudonymization. |
| `delete_posting_date` | `headers.delete_posting_date` | Retained. |
| `delete_header_user-agent` | `headers.delete_user_agent` | Name normalized. |
| `delete_header_x-no-archive` | `headers.delete_x_no_archive` | Name normalized. |
| `delete_header_x-trace` | `headers.delete_x_trace` | Name normalized. |
| `delete_mail_headers` | `headers.delete_mail_headers` | Retained. |
| `delete_custom_headers` | `headers.delete_custom_headers` plus `saved_headers` | Retained. |
| `include_new_headers` | `headers.include_new_headers` plus `[new_headers]` | Retained. |
| `legal_summary` | SQLite `article_events` | Stored in SQLite `article_events`; no separate `postlegal.log` is written. |
| `file_active` | `paths.active_file` | Installer derives it from `innconfval pathdb`. |
| `file_badwords` | `conf.d/50-badwords.toml` | Perl/colon file replaced by typed TOML. |
| `file_banlist` | `conf.d/60-banlist.toml` | Perl/colon file replaced by typed TOML. |
| `file_access` | SQLite plus `conf.d/30-access-profiles.toml` | Physical access log removed. |
| `file_legal` | SQLite | Physical legal log removed. |
| `dir_spool` | `paths.saved_dir` and SQLite | Retained behavior with safer layout. |
| `dir_filter` | installer `--filter-dir` and config directory | Derived through `innconfval` or explicit override. |
| `sendmail` | `paths.sendmail` | Used by banlist `destination_type="mail"`. |
| `version` | `VERSION`, module `$VERSION`, report metadata | No configurable fake version value. |

## Historical arrays and hashes

| Historical structure | New structure | Migration status |
|---|---|---|
| `%whitelist` | `[[trusted_profile]]` | All operational host, Sender and From patterns migrated. |
| `%public_rights_ip` | `access.public_limits` | Operational values migrated exactly. |
| `%public_rights_domain` | `access.domain_limits` | Operational values migrated exactly. |
| `%auth_rights` | `access.authenticated_limits` | Operational values migrated exactly. |
| `%mysql` | SQLite `[database]` | Technology removed; behavior retained. |
| `@localip` | `tor.local_tor_networks` plus client source IP | Port-based probing removed; local endpoint networks are explicit CIDRs. |
| `%headlist` | `[new_headers]` | Migrated. |
| `@distributions` | root `distributions` | `local`, `trash`, `usenet` migrated. |
| `%forbidden_crosspost` | `[[forbidden_crosspost]]` | All eight operational policies migrated and single-group bug corrected. |
| `@quickref` | `Postfilter::Codes` and `docs/ERROR-CODES.md` | Codes 0–94 and local 104–108 retained. |
| `@saved_headers` | root `saved_headers` | Migrated and supplemented with modern Injection headers. |
| `@nomoderation` | `moderated_exceptions` | Migrated. |
| `@htmlallowed` | `html_allowed_groups` | Migrated. |
| `@htmltags` | `html_patterns` | Migrated with more robust regexes. |
| `%extracontent` | `[[content_type_rule]]` | Migrated. |
| `%forbidden_headers` | `[[forbidden_header_rule]]` | Migrated. |
| `@forbidden_groups` | `forbidden_groups` | Migrated. |
| `%dnsbl` | `[[dnsbl]]` | SORBS response codes migrated. |
| `badwords.conf` | `[[badword]]` | Every active supplied rule migrated. |
| `banlist.conf` | `[[ban_rule]]` | Every active supplied rule migrated, plus normalized Steve Carroll variants. |

## Historical banlist action vocabulary

All historical action forms are represented:

- `log` to syslog or a locked file;
- `drop`/reject, including syslog or file side effects;
- `save` to central rejected storage, `file`, `message`, `maildir`, `rnews`,
  `mbox` or `mail`;
- `score` add, `score clear`, and `score verify`;
- `setmax` for a named score;
- `sum` of groups, followups, lines, header/body/total size;
- `config` per-article override.

Disabled and extensively commented examples are included at the end of
`conf/conf.d/60-banlist.toml`.
