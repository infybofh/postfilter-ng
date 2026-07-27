# Function reference

This reference is generated from the explanatory comments and POD immediately
above every production Perl subroutine in the release. It is a navigation aid
for newsmasters and contributors; the source remains authoritative for exact
failure policy, concurrency, security implications and side effects.

## `postfilter`

| Function | Purpose | Parameters |
|---|---|---|
| `_engine` | Lazily constructs one Postfilter-NG engine for the lifetime of the current nnrpd process. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `filter_post` | INN hook entry point that passes one POST to the reusable Postfilter-NG engine. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `filter_end` | INN hook shutdown callback that releases the per-nnrpd engine and database handle. | `No positional parameters, or arguments are read directly by the command wrapper.` |

## `bin/postfilterctl`

| Function | Purpose | Parameters |
|---|---|---|
| `_command_check_config` | Validates and reports the effective source/LKG configuration generation. | `$loader` |
| `_command_show_config` | Prints the fully merged and sanitised configuration as canonical JSON. | `$config` |
| `_command_db_check` | Opens SQLite, runs integrity_check, and reports the schema version. | `$database` |
| `_command_db_migrate` | Applies idempotent SQLite schema migrations. | `$database` |
| `_command_db_vacuum` | Runs an explicit SQLite VACUUM maintenance operation. | `$database` |
| `_command_backup` | Creates a consistent SQLite backup at the requested destination. | `$database, $arguments` |
| `_command_maintenance` | Removes only stale provider-health telemetry. | `$database` |
| `_command_purge` | Performs dry-run counting or confirmed audited event deletion before a selected time. | `$database, $arguments` |
| `_parse_time_argument` | Parses epoch or ISO-like administrative time input into a Unix timestamp. | `$value` |
| `_command_report` | Generates the configured static HTML report. | `$database, $config, $crypto, $logger` |
| `_command_tor_decode` | Decrypts one TOR header token with the dedicated TOR key. | `$config, $crypto, $arguments` |
| `_command_decrypt_report_value` | Decrypts one reversible HTML-report identity token. | `$config, $crypto, $arguments` |
| `_command_decrypt_db_value` | Decrypts one reversible SQLite identity token. | `$config, $crypto, $arguments` |
| `_command_rules` | Lists effective badword and ban rules with enabled state and actions. | `$config` |
| `_command_stats` | Prints aggregate article-result statistics for a requested window. | `$database, $arguments` |
| `_command_query` | Builds a parameterised event-history query from supported filters. | `$database, $arguments` |
| `_command_export` | Exports query results as JSON Lines or RFC-style CSV. | `$database, $arguments` |
| `_reveal_event_identities` | Decodes protected event identities for trusted local administrative output. | `$database, $rows` |
| `_command_saved_list` | Lists saved-article metadata in reverse chronological order. | `$database, $arguments` |
| `_command_saved_show` | Prints one saved article after verifying its database path. | `$database, $arguments` |
| `_command_rule_test` | Evaluates one selected rule against an offline article fixture. | `$config, $crypto, $logger, $arguments` |
| `_command_test_article` | Runs the complete engine against a raw-client or INN-hook fixture. | `$mode, $arguments` |
| `_read_article` | Parses an offline article into unfolded headers and body for testing. | `$file` |
| `_command_migrate_old_config` | Converts supported historical banlist/badwords syntax into commented TOML candidates. | `$arguments` |
| `_convert_old_banlist` | Converts one historical colon-separated ban rule into a reviewable TOML entry. | `$path` |
| `_convert_old_badwords` | Converts one historical badword line into a reviewable TOML entry. | `$path` |
| `_rows_as_jsonl` | Serialises database rows as one canonical JSON object per line. | `$rows` |
| `_rows_as_csv` | Serialises database rows with a deterministic header and escaped fields. | `$rows` |
| `_csv_field` | Quotes one CSV field and doubles embedded quote characters. | `$value` |
| `_toml_literal` | Quotes one generated TOML string without changing its regex backslashes. | `$value` |
| `_slug` | Converts arbitrary text to a conservative identifier used in generated rule IDs. | `$value` |
| `_usage` | Prints command syntax and exits with the supplied status. | `$exit_code` |

## `installer/install-postfilter`

| Function | Purpose | Parameters |
|---|---|---|
| `_resolve_inn_paths` | Uses innconfval to discover filter, configuration, database, spool, binary, and active paths. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `_apply_fallback_paths` | Fills only unresolved installer paths with portable defaults. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `_running_perl_path` | Resolves the interpreter executing the installer to an absolute executable path. | `No positional parameters.` |
| `_find_in_path` | Resolves one command name through PATH without invoking a shell. | `$name` |
| `_find_executable` | Returns the first executable candidate path. | `$binary, $key` |
| `_inn_value` | Runs innconfval without a shell and returns one trimmed setting. | `$binary, $key` |
| `_check_dependencies` | Verifies every required runtime Perl module before modifying the installation. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `_copy_tree` | Recursively copies release files while preserving executable modes and symlinks. | `$source, $destination` |
| `_compile_tree` | Runs perl -c on every installed module and executable in the staging tree. | `$directory` |
| `_rewrite_installed_shebangs` | Replaces portable source-tree shebangs with the absolute active Perl interpreter. | `$directory, $interpreter` |
| `_write_install_paths_module` | Persists installer-detected runtime defaults inside the activated code prefix. | `$path` |
| `_perl_single_quoted` | Quotes one installer path as a safe single-quoted Perl literal. | `$value` |
| `_create_runtime_directories` | Creates documented configuration, key, state, saved-article, userdb, and HTML directories. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `_install_configuration_files` | Installs main/fragments/assets while preserving operator files on upgrade. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `_install_config_file` | Copies one configuration asset only when policy permits replacement. | `$source, $destination` |
| `_replace_default_paths` | Rewrites shipped path defaults to detected or explicitly supplied installation paths. | `$path` |
| `_legacy_path_replacements` | Returns exact historical shipped defaults and their detected site-local replacements. | `None.` |
| `_migrate_existing_configuration_paths` | Migrates only historical shipped path defaults in preserved operator TOML files. | `None.` |
| `_install_distribution_configuration_snapshots` | Installs current path-adjusted TOML examples beside preserved operator files as `.dist`. | `None.` |
| `_configured_key_paths` | Loads main TOML plus fragments and resolves all four effective purpose-specific key paths. | `$configuration_path` |
| `_configured_saved_subdirectories` | Resolves and validates the text and binary diagnostic directory names. | `$configuration_path` |
| `_load_installer_configuration` | Loads main TOML plus sorted fragments for installer path/key decisions. | `$configuration_path` |
| `_merge_configuration_hash` | Recursively merges installer-only configuration tables used to resolve key paths. | `$destination, $source` |
| `_create_random_key` | Creates and verifies one non-overwritten 64-byte key from /dev/urandom. | `$path, $purpose` |
| `_install_command_links` | Creates the review-only INN hook candidate and the postfilterctl command link. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `_verify_install_paths_module` | Proves that a clean new Perl process loads the generated module from the active prefix. | `None.` |
| `_verify_embedded_hook_candidate` | Loads the candidate as nnrpd does and constructs the engine without path overrides. | `No positional parameters.` |
| `_print_activation_notice` | Shows the exact candidate and active hook paths after a successful installation. | `No positional parameters.` |
| `_set_configuration_ownership` | Recursively applies root:news-style ownership and non-writable configuration permissions. | `$directory, $group` |
| `_chown_tree` | Recursively assigns runtime ownership and documented directory/file modes. | `$directory, $user, $group, $directory_mode, $file_mode` |
| `_clear_perl_environment` | Removes inherited Perl library and build variables before installer verification. | `None.` |
| `_system_with_clean_perl_environment` | Executes one command after locally removing inherited Perl path and option variables. | `@command` |
| `_timestamp_compact` | Returns one UTC timestamp safe for backup and failed-install directory names. | `None.` |
| `_run_as_runtime_user` | Executes one installer validation command with the configured INN uid and gid. | `@command` |
| `_execute` | Runs one installer phase and restores the previous code prefix if the phase fails. | `$code` |
| `_uninstall` | Removes code and symlinks while preserving SQLite state and saved articles by default. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `_print_plan` | Displays all resolved installation paths and whether actions will be applied. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `_usage` | Prints command syntax and exits with the supplied status. | `$exit_code` |

## `lib/Postfilter/Article.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `serialize` | Serialises the current article headers and body for exact administrative storage/output. | `$class, $context` |

## `lib/Postfilter/ArticleType.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `classify` | Classifies one Newsgroups set as text, binary or mixed using the configured reader mode and binary-group globs. | `$class, $config, $newsgroups` |
| `_compiled_globs` | Compiles and caches the binary-group glob list for the lifetime of one nnrpd process. | `$patterns` |

## `lib/Postfilter/Checks/Access.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `run` | Applies SQLite-backed multipost and rate limits to the article’s resolved identities. | `$class, $context` |
| `_identities_for_article` | Selects IP/domain or authenticated-user identities according to server type and public- user rules. | `$context` |
| `_profile_for_identity` | Returns the highest-priority matching access profile or the appropriate default limits. | `$context, $identity_type, $identity_value` |
| `_current_article_increment` | Calculates how the pending article contributes to each prospective rate metric. | `$context, $metric` |
| `_database_failure_result` | Translates an access-query SQLite failure into configured fail-open or historical-code rejection. | `$context, $error` |
| `_reject` | Constructs a rejection result while preserving the historical numeric compatibility code. | `$legacy_code, %details` |

## `lib/Postfilter/Checks/Attachments.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `run` | Applies MIME attachment rules and the bounded Base64 heuristic. | `$class, $context` |
| `top_level_content_type_is_managed` | Defers MIME containers and managed media types to the dedicated attachment check. | `$class, $context` |
| `_inspect_entity` | Recursively validates one MIME entity and collects safe text-like bodies. | `$context, $headers, $body, $policy, $state, $depth, $location` |
| `_add_scan_segment` | Adds a bounded body segment to the Base64 heuristic work queue. | `$state, $body` |
| `_parse_parameterised_header` | Parses a token plus semicolon-separated parameters into lowercase keys. | `$value, $default` |
| `_first_parameter_value` | Finds ordinary or RFC 2231 attachment-name parameters. | `$parameters, $name_pattern` |
| `_split_semicolon_fields` | Splits parameterised header fields without breaking quoted semicolons. | `$value` |
| `_split_multipart_body` | Extracts raw MIME parts and validates opening/closing boundary syntax. | `$body, $boundary` |
| `_parse_mime_part` | Separates and unfolds one MIME part's headers and body. | `$raw_part` |
| `_media_matches_any` | Tests one normalised MIME type against configured shell-style globs. | `$media_type, $patterns` |
| `_estimated_decoded_bytes` | Estimates the decoded size of a permitted cryptographic MIME part. | `$body, $encoding` |
| `_detect_large_base64_block` | Detects unlabelled large Base64 payloads while excluding safe armoured blocks. | `$context, $body, $policy` |
| `_evaluate_base64_run` | Applies the line-count and decoded-size thresholds to one completed run. | `$line_count, $encoded_characters, $minimum_lines, $minimum_decoded_bytes` |
| `_remove_allowed_armoured_blocks` | Excludes bounded PGP/GnuPG/certificate armour from Base64 heuristics. | `$body, $policy` |
| `_armour_marker_label` | Parses a single BEGIN or END ASCII-armour marker without body-wide regexes. | `$line, $kind` |
| `_malformed_result` | Applies the configured fail-open/fail-closed policy for malformed MIME syntax. | `$context, $policy, $reason, %details` |
| `_pass` | Constructs the normal successful result for this check. | `$message` |
| `_reject` | Constructs a rejection while retaining the numeric compatibility code. | `$numeric_code, %details` |

## `lib/Postfilter/Checks/Content.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `run_binary` | Detects forbidden uuencode and yEnc payload markers within the configured scan budget. | `$class, $context` |
| `run_badwords` | Evaluates badword rules against Subject/body and applies score or immediate-reject actions. | `$class, $context` |
| `_build_matcher` | Compiles exact, contains, or regex matching once for a badword rule evaluation. | `$rule, $pattern` |
| `_rule_rejection` | Builds a badword-specific rejection using rule overrides or default code/message. | `$rule, $default_legacy_code` |
| `_reject` | Constructs a rejection result while preserving the historical numeric compatibility code. | `$legacy_code, %details` |

## `lib/Postfilter/Checks/Reputation.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `run_tor` | Determines whether the client is a local or DNS-listed TOR node and applies the configured policy. | `$class, $context` |
| `run_rbl` | Checks the client address against enabled IP DNSBL providers under the shared DNS budget. | `$class, $context` |
| `run_uri_lists` | Extracts registrable domains from article URLs and evaluates enabled SURBL/URIBL providers. | `$class, $context` |
| `_query_ip_list` | Reverses an IPv4/IPv6 address and queries one DNSBL-style provider. | `$context, $ip, $provider, $list_type` |
| `_dns_query` | Performs a cached, budget-aware DNS A query and updates provider health/cooldown state. | `$context, $query_name, $provider, $list_type` |
| `_background_dns_query` | Performs one asynchronous DNS query within the smaller of query, DNS-total and article deadlines. | `$context, $resolver, $query_name` |
| `_resolver` | Lazily constructs and reuses one Net::DNS resolver per nnrpd process. | `$context` |
| `_dns_budget_error` | Detects exhausted per-article DNS time and returns the provider’s configured failure outcome. | `$context` |
| `_failure_result` | Translates provider timeout/refusal/internal failure into accept, skip, or rejection policy. | `$context, $provider, $provider_id, $error, $base_result` |
| `_prune_cache` | Removes expired/oldest DNS cache entries to enforce the process-local bound. | `$context` |
| `_reverse_ip` | Converts IPv4 or IPv6 into DNSBL nibble/reversed-octet query form. | `$ip` |
| `_pass` | Constructs a successful reputation-check result. | `$code, $message` |
| `_reject` | Constructs a rejection result while preserving the historical numeric compatibility code. | `$legacy_code, %details` |

## `lib/Postfilter/Checks/Rules.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `apply_trusted_profile` | Selects the highest-priority trusted profile whose configured conditions match the article. | `$class, $context` |
| `run_banlist` | Evaluates ordered ban rules, named scores, output actions, and configured rejection thresholds. | `$class, $context` |
| `_rule_matches` | Matches one ban rule against its normalised target and returns match details. | `$context, $rule` |
| `_match_any_header` | Applies separate header-name and header-value expressions across all article headers. | `$context, $rule` |
| `_execute_output_action` | Executes configured syslog, file, message, maildir, rnews, mbox, or mail side effects. | `$context, $rule, $trigger_action` |
| `_send_article_by_mail` | Invokes the configured mailer with a list-form pipe so recipient data never reaches a shell. | `$context, $rule, $article` |
| `_apply_score_action` | Implements add, clear, verify, and named score-variable operations. | `$rule, $scores, $score_limits, $global_score_limit` |
| `_add_article_metric` | Adds group/followup/line/byte metrics to a named rule score. | `$context, $rule, $scores` |
| `_set_article_config` | Applies a dotted configuration override to the article-local copy-on-write configuration. | `$context, $rule` |
| `_score_limit_result` | Returns a rejection only when a named score exceeds its specific or global ceiling. | `$rule, $score_name, $scores, $limits, $global_limit` |
| `_group_scope_matches` | Applies optional include/exclude group expressions before evaluating a rule. | `$context, $rule` |
| `_profile_is_excluded` | Skips a rule for explicitly excluded trusted-profile IDs. | `$context, $rule` |
| `_has_output_destination` | Reports whether a rule sends output to an external destination rather than standard saving. | `$rule` |
| `_output_failure` | Translates a rule side-effect failure according to banlist.side_effect_failure. | `$context, $rule, $detail` |
| `_append_locked` | Appends a complete record while holding an exclusive advisory file lock. | `$path, $content` |
| `_write_exclusive` | Creates one output file with O_EXCL so concurrent nnrpd processes cannot overwrite it. | `$path, $content` |
| `_expand_template` | Expands documented percent placeholders with current article metadata. | `$context, $template` |
| `_create_rule_rejection` | Builds a rule rejection using explicit rule codes/messages where supplied. | `$rule, $default_legacy_code, %details` |

## `lib/Postfilter/Checks/Style.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `run` | Runs structural header, group, date, size, line, HTML, and path validation for one article. | `$class, $context` |
| `_check_control_headers` | Rejects non-cancel control messages and disallowed cancel/supersedes headers. | `$context` |
| `_check_forbidden_crossposts` | Rejects articles whose group set matches both sides of a forbidden-crosspost rule. | `$context` |
| `_check_approved_header` | Allows Approved only for configured moderated exceptions. | `$context` |
| `_check_distribution_header` | Validates an incoming Distribution value against the configured allow-list. | `$context` |
| `_check_content_type` | Accepts text/plain or a group-scoped explicitly allowed MIME content type. | `$context` |
| `_check_html` | Detects configured HTML patterns outside explicitly allowed groups. | `$context` |
| `_check_group_existence` | Loads/caches active and validates Newsgroups and Followup-To entries. | `$context` |
| `_check_date` | Parses Date and enforces future grace and maximum-age policy when Date::Parse is available. | `$context` |
| `_check_forbidden_headers` | Applies named forbidden-header rules with optional name exceptions. | `$context` |
| `_check_forbidden_groups` | Rejects newsgroup/followup sets matching any configured forbidden-group regex. | `$context` |
| `_check_path` | Accepts an absent raw-client Path but rejects present Path values containing injection characters. | `$context` |
| `_count_hierarchies` | Counts unique top-level hierarchies in a group array. | `$groups` |
| `_reject` | Constructs a rejection result while preserving the historical numeric compatibility code. | `$legacy_code, %details` |

## `lib/Postfilter/Checks/UserDB.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `run` | Checks each posted group’s optional sender-authorisation file. | `$class, $context` |
| `_load_sender_file` | Loads and mtime-caches one per-group allowed-sender mailbox file. | `$path` |
| `_reject` | Constructs a rejection result while preserving the historical numeric compatibility code. | `$legacy_code, %details` |

## `lib/Postfilter/Codes.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `lookup` | Maps a historical numeric code to its stable symbolic code and message. | `$class, $numeric_code` |
| `message` | Returns the default human-readable message for one historical code. | `$class, $numeric_code` |
| `code` | Returns the stable symbolic code for one historical numeric code. | `$class, $numeric_code` |
| `all` | Returns the complete historical-to-symbolic error-code mapping. | `No positional parameters, or arguments are read directly by the command wrapper.` |

## `lib/Postfilter/Config.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `new` | Constructs a configuration loader bound to source, state directory, and logger. | `$class, %arguments` |
| `current` | Returns the currently active validated configuration reference. | `$_[0] (the current object or value)` |
| `load` | Loads source TOML, validates it, persists a last-known-good generation, or selects a safe fallback. | `$self` |
| `maybe_reload` | Checks source mtimes at the configured interval and atomically adopts only a valid generation. | `$self` |
| `_load_source` | Parses the main TOML and sorted fragments, merges them, and assigns a generation identifier. | `$self` |
| `_parse_toml_file` | Parses one standards-based TOML file with TOML::Tiny and normalises parser-specific scalars. | `$path` |
| `_normalise_parser_scalars` | Converts TOML parser numeric/boolean wrapper objects into ordinary Perl scalars recursively. | `$value` |
| `_source_mtime` | Returns the newest mtime among the main configuration and all TOML fragments. | `$self` |
| `_save_generation` | Persists canonical generation JSON and replaces last-known-good.json atomically. | `$self, $config, $warnings` |
| `_load_last_known_good` | Loads the most recent valid JSON snapshot for a new nnrpd process after source failure. | `$self` |
| `validate_and_sanitize` | Applies defaults, validates enums and regexes, and disables only malformed optional entries. | `$self, $config` |
| `embedded_minimal` | Builds the small fail-open configuration used only when source and snapshots are unavailable. | `No positional parameters, or arguments are read directly by the command wrapper.` |
| `_apply_defaults` | Populates omitted sections and keys without overwriting explicit operator values. | `$config` |
| `_remove_unknown_configuration_keys` | Warns about and removes misspelled top-level and fixed-table options. | `$config, $warnings` |
| `_validate_numeric_sections` | Validates only quantity-valued limits/timeouts and converts them to plain numeric scalars. | `$config, $warnings` |
| `_validate_article_type_configuration` | Validates binary-group globs, per-type check lists, save selectors, and rule scopes. | `$config, $warnings` |
| `_validate_rule_lists` | Checks rule-list shape, IDs, enabled state, duplicates, and rule-specific regex fields. | `$config, $warnings` |
| `_validate_entry_regexes` | Compiles every regex used by one rule and disables only that rule on failure. | `$list_name, $entry, $warnings` |
| `_disable_entry` | Marks one malformed optional entry disabled and records a precise configuration warning. | `$entry, $warnings, $list_name, $reason` |
| `_validate_provider_failure_policies` | Validates provider-specific failure decisions so timeout/refusal handling can never be driven by an arbitrary misspelt string. | `$config, $warnings` |
| `_validate_retention_policy` | Enforces the intentional no-automatic-deletion policy for legal article history, rule hits, and saved articles. | `$config, $warnings` |
| `_validate_regex_arrays` | Removes invalid standalone regexes while preserving every valid sibling expression. | `$config, $warnings` |
| `_normalise_encryption_mode` | Maps deprecated crypt/sha256 aliases to encrypted and validates allowed privacy modes. | `$hash, $key, $warnings, $default, $allowed` |
| `_valid_regex` | Compiles a candidate expression inside eval and returns whether it is safe to activate. | `$pattern` |
| `_enum` | Validates one scalar against an explicit allow-list and applies a documented fallback. | `$hash, $key, $allowed, $warnings, $default` |
| `_integer` | Validates an integer range used by a bounded operational setting. | `$hash, $key, $minimum, $maximum, $warnings, $default` |
| `_deep_merge` | Recursively merges a configuration fragment and appends designated arrays of tables. | `$destination, $source` |
| `_assign_generation` | Assigns a stable content-derived identifier to one validated effective configuration. | `$self, $config, $warnings` |
| `_save_generation` | Persists a canonical generation once, updates last-known-good only when it changes, and prunes old generation files. | `$self, $config, $warnings` |
| `_snapshot_generation` | Reads a snapshot generation identifier without treating a missing or malformed file as fatal. | `$path` |
| `_prune_generation_files` | Keeps the current generation plus the newest configured number of historical files. | `$self, $directory, $current_generation, $maximum` |

## `lib/Postfilter/Context.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `new` | Builds a fresh isolated context from one INN article, client attributes, and immutable configuration. | `$class, %arguments` |
| `_digest_input` | Builds the configured body/simple/complex/all byte sequence used for multipost hashing. | `$mode, $headers, $body` |
| `body_for_expensive_checks` | Returns the full body or the configured prefix used by cost-bounded scans. | `$self` |
| `analyze_lines` | Computes and caches line, quote, blank, empty, and maximum-length statistics. | `$self` |
| `extract_urls` | Extracts unique HTTP/HTTPS URLs under the configured work limit. | `$self` |
| `extract_domains` | Converts extracted URL hosts to unique registrable domains under the configured limit. | `$self` |
| `make_config_writable` | Creates a private configuration copy only when an article-local rule override is required. | `$self` |
| `start_processing_budget` | Starts the bounded check-and-transformation deadline once per article. | `$self` |
| `deadline_exceeded` | Reports whether the bounded check-and-transformation deadline has expired. | `$self` |
| `remaining_processing_ms` | Returns milliseconds left in the bounded check-and-transformation budget. | `$self` |
| `pipeline_elapsed_ms` | Returns wall-clock milliseconds since the bounded filtering budget began. | `$self` |
| `is_public_user` | Classifies empty and configured synthetic nnrpd identities as public without inverting real users. | `$self` |
| `header` | Returns one article header or an empty string. | `$self, $name` |
| `set_header` | Sets one article header in the current per-article context. | `$self, $name, $value` |
| `delete_header` | Deletes one article header from the current per-article context. | `$self, $name` |
| `skip` | Returns whether a trusted profile skipped a named check. | `$self, $check` |
| `add_hit` | Appends one structured rule-hit record for later SQLite persistence. | `$self, $hit` |
| `elapsed_ms` | Returns total processing time elapsed for the current article. | `$self` |

## `lib/Postfilter/Crypto.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `new` | Constructs the stateless cryptographic helper with an optional logger. | `$class, %arguments` |
| `load_key` | Reads a purpose-specific key file, enforces its minimum size, and derives a fixed 256-bit key. | `$self, $path, $minimum_bytes` |
| `pseudonym` | Creates a stable HMAC-SHA-256 identifier truncated to the requested printable length. | `$self, $value, $key, $length` |
| `encrypt_token` | Encrypts a value with a random IV and authenticates the version, purpose, IV, and ciphertext. | `$self, $plaintext, $key, $purpose` |
| `decrypt_token` | Authenticates and decrypts a versioned token using the same purpose-specific key. | `$self, $token, $key, $purpose` |
| `_constant_time_equal` | Compares authentication tags without returning early on the first differing byte. | `$left, $right` |
| `_random_bytes` | Reads an exact number of cryptographically secure bytes from /dev/urandom. | `$required_bytes` |

## `lib/Postfilter/Database.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `new` | Constructs the SQLite component without opening a connection until required. | `$class, %arguments` |
| `available` | Reports whether SQLite is enabled and not disabled after a configured failure. | `$self` |
| `update_config` | Replaces the database component’s validated configuration after a generation reload. | `$self, $config` |
| `connect` | Opens/reuses SQLite, applies WAL and durability pragmas, and runs idempotent migrations. | `$self` |
| `require_connection` | Returns a live SQLite handle or raises a clear command-oriented diagnostic. | `$self, $operation` |
| `migrate` | Creates or upgrades the SQLite schema transactionally and records applied versions. | `$self` |
| `_add_column_if_missing` | Adds one upgrade column only after PRAGMA table_info confirms it is absent. | `$database, $table, $column, $definition` |
| `handle_failure` | Logs an SQLite failure and translates database.on_failure into accept, reject, or disable. | `$self, $error` |
| `rate_snapshot` | Queries long/short accepted, rejected, byte, group, and followup counters for one identity. | `$self, $context, $identity_type, $identity_value` |
| `multipost_count` | Counts previously accepted events with the same article digest inside the configured period. | `$self, $context` |
| `local_distribution_add` | Records a local-distribution Message-ID for reply inheritance. | `$self, $message_id, $time` |
| `local_distribution_remove` | Removes a local-distribution marker when a later mandatory persistence failure rejects the article before nnrpd receives its final response. | `$self, $message_id` |
| `local_distribution_exists` | Tests whether a referenced Message-ID was recorded with local distribution. | `$self, $message_id` |
| `record_event` | Writes the single final article event and all rule hits in one short SQLite transaction. | `$self, $context, $result, $final` |
| `saved_article_add` | Links a saved article file, digest, size, and timestamp to its event record. | `$self, %article` |
| `purge_events_before` | Counts or explicitly deletes old events and records every confirmed destructive operation. | `$self, %arguments` |
| `maintenance_provider_health` | Deletes only stale provider-health telemetry, never legal article history. | `$self` |
| `backup_to_file` | Creates a consistent SQLite backup through the database backup API. | `$self, $destination` |
| `_record_administrative_action` | Writes an immutable audit row describing an explicit maintenance or purge command. | `$self, %arguments` |
| `_protect_identity` | Stores an identity as plain text, stable HMAC, or reversible authenticated ciphertext. | `$self, $purpose, $value` |
| `identity_lookup` | Exposes the stable indexed identity token to trusted administrative callers. | `$self, $purpose, $value` |
| `reveal_identity` | Converts a stored identity into the most readable form permitted by its storage mode. | `$self, $purpose, $stored_value, $storage_mode` |
| `_identity_lookup` | Creates the stable hidden HMAC lookup key used by rate limits in every privacy mode. | `$self, $purpose, $value` |
| `_database_privacy_key` | Loads and caches the dedicated database privacy key without using any fallback secret. | `$self` |
| `disconnect` | Closes the process-local SQLite handle and clears it for safe reuse. | `$self` |

## `lib/Postfilter/Dependencies.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `apply_runtime_capabilities` | Checks runtime module availability and disables only features whose configured failure policy allows degradation. | `$class, $config, $logger` |
| `_can_load` | Tests whether a Perl module can be required without terminating the filter. | `$module` |
| `_log_missing` | Writes a clear dependency diagnostic including affected feature and chosen degradation. | `$logger, %fields` |

## `lib/Postfilter/HeaderTransform.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `apply` | Applies all explicitly enabled header transformations in a deterministic order. | `$class, $context` |
| `_transform_sender` | Preserves, deletes, replaces, or pseudonymises Sender only when explicitly configured. | `$context` |
| `_transform_injection_information` | Parses Injection-Info and applies independent posting-host/account policies. | `$context` |
| `_apply_injection_field_mode` | Applies preserve/delete/replace/pseudonymize to one parsed Injection-Info field. | `$context, $items, $field_name, $settings, $fallback_value` |
| `_transform_path` | Ensures Path remains storable while applying the configured replacement or HMAC marker. | `$context` |
| `_transform_distribution` | Validates Distribution, marks accepted local Message-IDs for deferred storage, and removes the usenet marker. | `$context` |
| `_add_tor_header` | Writes yes, plaintext IP, or reversible encrypted TOR metadata according to policy. | `$context` |
| `_keep_only_configured_headers` | Deletes headers not present in saved_headers when strict allow-list mode is enabled. | `$context` |
| `_repair_mime_headers` | Normalises MIME-related header values without rewriting valid user content unnecessarily. | `$context` |
| `_delete_named_headers` | Deletes an explicit list of header names and records each transformation. | `$context, @names` |
| `_remove_header` | Marks a header for deletion using the representation required by INN's nnrpd Perl hook. | `$headers, $name` |
| `_load_pseudonym_key` | Loads the dedicated header pseudonym key; on failure it logs and preserves original data. | `$context, $header_name` |
| `_reject` | Constructs a rejection result while preserving the historical numeric compatibility code. | `$legacy_code, %details` |

## `lib/Postfilter/Logger.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `new` | Constructs a logger with prefix, verbosity, and optional stderr fallback. | `$class, %arguments` |
| `verbosity` | Returns the current cumulative logging verbosity. | `$self, $verbosity` |
| `set_verbosity` | Changes the process-local logging verbosity after a validated configuration reload. | `$self, $verbosity` |
| `set_options` | Applies validated logging presentation flags after a configuration load or reload without replacing the process-local logger object. | `$self, $logging_config` |
| `event` | Formats one structured log line, sanitises untrusted fields, and writes through INN syslog or stderr. | `$self, $severity, $required_verbosity, $message, %fields` |
| `fatal` | Writes an unconditional critical-severity event. | `$s, $m, %f` |
| `error` | Creates an internal-error result for callers that need to distinguish failure from policy rejection. | `$s, $m, %f` |
| `warning` | Writes an unconditional warning-severity event. | `$s, $m, %f` |
| `result` | Implements the module-specific result operation. | `$s, $m, %f` |
| `identity` | Writes level-2 posting identity information. | `$s, $m, %f` |
| `pipeline` | Writes level-3 pipeline and trusted-profile decisions. | `$s, $m, %f` |
| `structural` | Writes level-4 structural-check diagnostics. | `$s, $m, %f` |
| `headers` | Writes level-5 header-transformation diagnostics. | `$s, $m, %f` |
| `database` | Writes level-6 SQLite and rate-limit diagnostics. | `$s, $m, %f` |
| `reputation` | Writes level-7 DNS reputation diagnostics. | `$s, $m, %f` |
| `rules` | Writes level-8 rule and scoring diagnostics. | `$s, $m, %f` |
| `trace` | Writes level-9 detailed execution timing and trace data. | `$s, $m, %f` |

## `lib/Postfilter/InstallUpgrade.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `migrate_legacy_path_files` | Replaces exact historical default paths in existing TOML files after backing them up. | `%arguments` |
| `write_distribution_snapshot` | Writes one shipped configuration file as a path-adjusted `.dist` comparison copy. | `%arguments` |
| `_read_file` | Reads one file without character decoding. | `$path` |
| `_atomic_write_preserving_mode` | Atomically replaces one file while retaining or explicitly setting its mode. | `$path, $text, optional $mode` |

## `lib/Postfilter/InstallPaths.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `config_file` | Returns the runtime configuration file, with an explicit environment override. | `No positional parameters.` |
| `state_dir` | Returns the runtime state directory, with an explicit environment override. | `No positional parameters.` |

## `lib/Postfilter/NG.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `new` | Constructs one reusable per-nnrpd engine, loads configuration, dependencies, SQLite, and suffix data. | `$class, %arguments` |
| `process_article` | Coordinates configuration reload, filtering, policy resolution, persistence, logging, and the INN reply. | `$self, %arguments` |
| `_run_pipeline` | Runs ordered checks, honours trusted skips/audit/deadlines, and returns the first technical failure. | `$self, $context` |
| `_run_custom_filter` | Executes the last successfully loaded local custom rule function and normalises its return value. | `$self, $context` |
| `_load_custom_filter` | Reloads a changed custom module only after success and retains the previous working coderef on error. | `$self, $context, $file` |
| `_custom_error_result` | Applies custom.on_error to a missing module or custom-rule exception. | `$self, $context, $error` |
| `_processing_timeout_result` | Translates an exhausted whole-article deadline into configured fail-open or rejection behaviour. | `$self, $context, $next_check` |
| `_resolve_policy` | Combines technical verdict, audit mode, rule request, and global action into one final outcome. | `$self, $context, $result` |
| `_inn_response` | Converts the resolved outcome to INN’s empty, DROP, or rejection-string hook response. | `$self, $context, $result, $final` |
| `shutdown` | Closes process-local resources; repeated calls are safe. | `$self` |
| `_generation_changed` | Compares explicit generation IDs rather than relying on reference numeric comparison. | `$current, $candidate` |
| `_create_rejection_result` | Builds a rejection result from the historical numeric-code compatibility table. | `$legacy_code` |

## `lib/Postfilter/PublicSuffix.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `load` | Loads, normalises, and mtime-caches public-suffix entries from the configured file. | `$class, $path, $logger` |

## `lib/Postfilter/Report.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `generate` | Builds and atomically publishes a privacy-aware static HTML report from SQLite. | `$class, %arguments` |
| `_protect_report_value` | Transforms a report identity according to plain, redacted, HMAC, or encrypted policy. | `$value, $mode, $key, $crypto, $purpose` |
| `_load_stylesheet` | Loads operator CSS for embedding and falls back to a safe built-in stylesheet. | `$config, $logger` |
| `_html_header` | Builds the escaped HTML document prologue and embeds the selected stylesheet. | `$title, $stylesheet` |
| `_card` | Builds one escaped summary-card fragment. | `$label, $value` |
| `_table` | Builds one escaped HTML table from headings and rows. | `$headings, $rows` |
| `_escape_html` | Escapes HTML metacharacters in every database/configuration value before publication. | `$value` |

## `lib/Postfilter/Result.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `pass` | Creates a successful check result without selecting the final administrative action. | `$class, %arguments` |
| `reject` | Creates a technical rejection result while retaining symbolic and historical codes. | `$class, %arguments` |
| `error` | Creates an internal-error result for callers that need to distinguish failure from policy rejection. | `$class, %arguments` |
| `is_pass` | Returns true only when the technical verdict is pass. | `$_[0] (the current object or value)` |
| `is_reject` | Returns true only when the technical verdict is reject. | `$_[0] (the current object or value)` |
| `code` | Returns the symbolic Postfilter-NG reason code. | `$_[0] (the current object or value)` |
| `legacy` | Returns the historical numeric code retained for migration and reporting. | `$_[0] (the current object or value)` |
| `message` | Returns the human-readable result explanation. | `$_[0] (the current object or value)` |
| `requested_action` | Returns an optional action requested by a matching rule, such as discard or save. | `$_[0] (the current object or value)` |
| `as_hash` | Returns a shallow hash copy suitable for JSON, tests, or diagnostic output. | `$_[0] (the current object or value)` |

## `lib/Postfilter/SavedArticle.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `save` | Saves the complete current article with an exclusive chronological name and returns metadata. | `$class, $context, $result` |

## `lib/Postfilter/Util.pm`

| Function | Purpose | Parameters |
|---|---|---|
| `bool` | Normalises Perl truth into numeric zero or one. | `$_[0] (the current object or value)` |
| `split_groups` | Splits a Newsgroups-style value into trimmed non-empty group names. | `$value` |
| `header_value` | Returns a header value while tolerating canonical or lowercase keys. | `$headers, $name` |
| `normalize_email` | Extracts and lowercases the mailbox portion of a From or Sender value. | `$value` |
| `ip_in_cidr` | Tests an IPv4 or IPv6 address against a validated CIDR prefix using packed network bytes. | `$ip, $cidr` |
| `registered_domain` | Reduces a host to its registrable domain using the loaded public-suffix data. | `$host, $suffixes` |
| `atomic_write` | Writes a complete temporary file and atomically renames it over the destination. | `$path, $content, $mode` |
| `slurp` | Reads an entire file in raw mode and reports open/close failures. | `$path` |
| `sha256_hexstr` | Returns the SHA-256 hexadecimal digest of a scalar value. | `$_[0] (the current object or value)` |
| `hmac_id` | Returns a truncated hexadecimal HMAC identifier for a value and key. | `$value, $key, $length` |
| `now_iso` | Formats the current UTC time as an ISO-8601 string. | `No positional parameters, or arguments are read directly by the command wrapper.` |

**Documented production functions:** 292
