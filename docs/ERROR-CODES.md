# Postfilter-NG error and result code reference

Generated for Postfilter-NG `2026.10.2`.  Do not edit the generated tables by hand; regenerate them with `perl bin/generate-error-codes > docs/ERROR-CODES.md`.

Use `postfilterctl explain-code PF-RATE-084` (or the numeric legacy code) for the same information on an installed release.  File:line references below refer to this exact release.

## Complete code index

| Legacy | Symbolic | Status | Default message | Configuration / policy | Primary source |
|---:|---|---|---|---|---|
| 0 | `PF-INTERNAL-000` | active | Message successfully sent | `n/a` | `lib/Postfilter/NG.pm:687` (`_run_custom_filter`)<br>`lib/Postfilter/Result.pm:68` (`code`)<br>`lib/Postfilter/SavedArticle.pm:77` (`save`) |
| 1 | `PF-HEADER-001` | active | Control messages are forbidden | `style.control` | `lib/Postfilter/Checks/Style.pm:227` (`_check_control_headers`) |
| 2 | `PF-GROUP-002` | active | Forbidden crosspost | `conf.d/10-structural-rules.toml: forbidden_crosspost` | `lib/Postfilter/Checks/Style.pm:267` (`_check_forbidden_crossposts`) |
| 3 | `PF-HEADER-003` | active | You cannot approve messages | `moderation/Approved policy` | `lib/Postfilter/Checks/Style.pm:295` (`_check_approved_header`) |
| 4 | `PF-GROUP-004` | active | Invalid Distribution header | `headers.check_distribution / distributions` | `lib/Postfilter/Checks/Style.pm:321` (`_check_distribution_header`) |
| 5 | `PF-MIME-005` | active | Invalid Content-Type | `content_type_rule / article type checks` | `lib/Postfilter/Checks/Style.pm:367` (`_check_content_type`) |
| 6 | `PF-GROUP-006` | active | Too many groups in Newsgroups | `limits.max_crosspost` | `lib/Postfilter/Checks/Style.pm:96` (`run`) |
| 7 | `PF-GROUP-007` | active | Too many groups in Followup-To | `limits.max_followup` | `lib/Postfilter/Checks/Style.pm:99` (`run`) |
| 8 | `PF-GROUP-008` | active | Missing Followup-To header | `limits.max_fup_no_crosspost` | `lib/Postfilter/Checks/Style.pm:102` (`run`) |
| 9 | `PF-BODY-009` | compatibility/reserved | The body is too large | `limits.max_body_size` | _No direct runtime call-site found_ |
| 10 | `PF-GROUP-010` | active | Difference between crossposts and followups is too large | `limits.max_groups_difference` | `lib/Postfilter/Checks/Style.pm:106` (`run`) |
| 11 | `PF-HEADER-011` | active | Re: without References | `header style policy` | `lib/Postfilter/Checks/Style.pm:122` (`run`) |
| 12 | `PF-BODY-012` | active | Line too long | `limits.max_line_length` | `lib/Postfilter/Checks/Style.pm:131` (`run`) |
| 13 | `PF-BODY-013` | active | Too many quoted lines | `limits.max_quoted_ratio` | `lib/Postfilter/Checks/Style.pm:135` (`run`) |
| 14 | `PF-BODY-014` | active | Too many blank lines | `limits.max_blank_ratio` | `lib/Postfilter/Checks/Style.pm:139` (`run`) |
| 15 | `PF-BODY-015` | active | Too many empty lines | `limits.max_empty_ratio` | `lib/Postfilter/Checks/Style.pm:143` (`run`) |
| 16 | `PF-BODY-016` | active | HTML content is forbidden | `headers.allow_html / html_allowed_groups / html_patterns` | `lib/Postfilter/Checks/Style.pm:394` (`_check_html`) |
| 17 | `PF-GROUP-017` | active | Nonexistent group | `headers.check_groups_existence / paths.active_file` | `lib/Postfilter/Checks/Style.pm:444` (`_check_group_existence`) |
| 18 | `PF-GROUP-018` | active | Nonexistent group in Followup-To | `headers.check_groups_existence / paths.active_file` | `lib/Postfilter/Checks/Style.pm:450` (`_check_group_existence`) |
| 19 | `PF-DATE-019` | active | Date is too far in the future | `date policy` | `lib/Postfilter/Checks/Style.pm:476` (`_check_date`)<br>`lib/Postfilter/Checks/Style.pm:488` (`_check_date`)<br>`lib/Postfilter/Checks/Style.pm:499` (`_check_date`) |
| 20 | `PF-HEADER-020` | active | Invalid Path | `headers.path` | `lib/Postfilter/Checks/Style.pm:596` (`_check_path`) |
| 21 | `PF-HEADER-021` | active | A header is too long | `limits.max_header_length` | `lib/Postfilter/Checks/Style.pm:172` (`run`) |
| 22 | `PF-HEADER-022` | active | Mail headers are forbidden | `headers.allow_mail_headers / headers.delete_mail_headers` | `lib/Postfilter/Checks/Style.pm:181` (`run`) |
| 23 | `PF-HEADER-023` | compatibility/reserved | Headers are too large | `limits.max_header_size` | _No direct runtime call-site found_ |
| 24 | `PF-HEADER-024` | active | Invalid In-Reply-To | `header style policy` | `lib/Postfilter/Checks/Style.pm:186` (`run`) |
| 25 | `PF-GROUP-025` | active | Too many hierarchies | `limits.max_hierarchies_post` | `lib/Postfilter/Checks/Style.pm:155` (`run`) |
| 26 | `PF-GROUP-026` | active | Too many hierarchies in Followup-To | `limits.max_hierarchies_followup` | `lib/Postfilter/Checks/Style.pm:159` (`run`) |
| 27 | `PF-CONFIG-027` | compatibility/reserved | Syntax error in badwords configuration | `conf.d/50-badwords.toml` | _No direct runtime call-site found_ |
| 28 | `PF-RULE-028` | active | Badword in Subject | `badwords.max_subject_score / badword rules` | `lib/Postfilter/Checks/Content.pm:195` (`run_badwords`) |
| 29 | `PF-RULE-029` | active | Badword in body | `badwords.max_body_score / badword rules` | `lib/Postfilter/Checks/Content.pm:198` (`run_badwords`) |
| 30 | `PF-RATE-030` | compatibility/reserved | Multipost | `limits.default_multipost_limit / limits.absolute_multipost_limit / access_profile.limits.multipost` | _No direct runtime call-site found_ |
| 31 | `PF-RATE-031` | active | Your IP has sent too many articles | `access.*_limits.max_articles / access_profile.limits.max_articles` | `lib/Postfilter/Checks/Access.pm:34` (`<file scope>`) |
| 32 | `PF-RATE-032` | active | Your domain has sent too many articles | `access.*_limits.max_articles / access_profile.limits.max_articles` | `lib/Postfilter/Checks/Access.pm:46` (`<file scope>`) |
| 33 | `PF-RATE-033` | active | Your userid has sent too many articles | `access.*_limits.max_articles / access_profile.limits.max_articles` | `lib/Postfilter/Checks/Access.pm:58` (`<file scope>`) |
| 34 | `PF-RULE-034` | compatibility/reserved | Banlist | `conf.d/60-banlist.toml` | _No direct runtime call-site found_ |
| 35 | `PF-CONFIG-035` | compatibility/reserved | Syntax error in banlist configuration | `conf.d/60-banlist.toml` | _No direct runtime call-site found_ |
| 36 | `PF-DB-036` | compatibility/reserved | Database connection error | `database.*` | _No direct runtime call-site found_ |
| 37 | `PF-GROUP-037` | active | Unable to load active file | `paths.active_file` | `lib/Postfilter/Checks/Style.pm:419` (`_check_group_existence`)<br>`lib/Postfilter/Checks/Style.pm:426` (`_check_group_existence`) |
| 38 | `PF-CONFIG-038` | compatibility/reserved | Unable to load badwords configuration | `conf.d/50-badwords.toml` | _No direct runtime call-site found_ |
| 39 | `PF-CONFIG-039` | compatibility/reserved | Unable to load banlist configuration | `conf.d/60-banlist.toml` | _No direct runtime call-site found_ |
| 40 | `PF-DB-040` | active | Unable to open persistent storage | `database.* / policy database failure action` | `lib/Postfilter/Checks/Access.pm:312` (`_database_failure_result`)<br>`lib/Postfilter/NG.pm:368` (`process_article`) |
| 41 | `PF-SAVE-041` | active | Unable to save article | `saved_articles.*` | `lib/Postfilter/NG.pm:291` (`process_article`) |
| 42 | `PF-CONFIG-042` | compatibility/reserved | Unable to run innconfval | `installer --innconfval / PATH` | _No direct runtime call-site found_ |
| 43 | `PF-CONFIG-043` | compatibility/reserved | Unable to load main configuration | `postfilter.toml / conf.d` | _No direct runtime call-site found_ |
| 44 | `PF-DB-044` | compatibility/reserved | Unable to write audit event | `database.*` | _No direct runtime call-site found_ |
| 45 | `PF-DB-045` | compatibility/reserved | Database expiry error | `retention.* / maintenance` | _No direct runtime call-site found_ |
| 46 | `PF-DB-046` | compatibility/reserved | Database spool error | `database.*` | _No direct runtime call-site found_ |
| 47 | `PF-POLICY-047` | compatibility/reserved | Default action set to rejection | `policy.action_on_reject` | _No direct runtime call-site found_ |
| 48 | `PF-POLICY-048` | active | Server closed for posting | `posting policy` | `lib/Postfilter/NG.pm:445` (`_run_pipeline`) |
| 49 | `PF-RULE-049` | compatibility/reserved | Excessive score in banlist | `banlist.max_score` | _No direct runtime call-site found_ |
| 50 | `PF-TOR-050` | active | TOR is forbidden | `tor.action / tor.*` | `lib/Postfilter/Checks/Reputation.pm:82` (`run_tor`)<br>`lib/Postfilter/Checks/Reputation.pm:93` (`run_tor`) |
| 51 | `PF-HEADER-051` | active | Supersedes, Replaces and Cancel are forbidden | `style.control` | `lib/Postfilter/Checks/Style.pm:232` (`_check_control_headers`) |
| 52 | `PF-BODY-052` | active | UUEncoded binaries are forbidden | `article_types.text.content.allow_uuencode` | `lib/Postfilter/Checks/Content.pm:62` (`run_binary`)<br>`lib/Postfilter/Config.pm:1384` (`_apply_defaults`) |
| 53 | `PF-HEADER-053` | compatibility/reserved | Forged system header | `forbidden_header_rule` | _No direct runtime call-site found_ |
| 54 | `PF-GROUP-054` | active | Permanently closed group | `conf.d/10-structural-rules.toml: forbidden_groups` | `lib/Postfilter/Checks/Style.pm:567` (`_check_forbidden_groups`) |
| 55 | `PF-INTERNAL-055` | compatibility/reserved | Unable to load internal module | `runtime module loading` | _No direct runtime call-site found_ |
| 56 | `PF-RBL-056` | compatibility/reserved | Forbidden due to DNSBL listing | `conf.d/40-reputation.toml: dnsbl` | _No direct runtime call-site found_ |
| 57 | `PF-BODY-057` | compatibility/reserved | Message too big | `limits.max_total_size` | _No direct runtime call-site found_ |
| 58 | `PF-DATE-058` | active | Message too old | `date policy` | `lib/Postfilter/Checks/Style.pm:502` (`_check_date`) |
| 59 | `PF-CONFIG-059` | compatibility/reserved | Unable to read public suffix data | `paths.public_suffix_file` | _No direct runtime call-site found_ |
| 60 | `PF-URIBL-060` | compatibility/reserved | Banned domain in body (SURBL) | `conf.d/40-reputation.toml: surbl` | _No direct runtime call-site found_ |
| 61 | `PF-URIBL-061` | compatibility/reserved | Banned domain in body (URIBL) | `conf.d/40-reputation.toml: uribl` | _No direct runtime call-site found_ |
| 62 | `PF-BODY-062` | active | yEnc contents are forbidden | `article_types.text.content.allow_yenc` | `lib/Postfilter/Checks/Content.pm:69` (`run_binary`)<br>`lib/Postfilter/Config.pm:1385` (`_apply_defaults`) |
| 63 | `PF-RULE-063` | active | Message rejected by a custom rule | `custom.* / conf/custom.pm` | `lib/Postfilter/NG.pm:691` (`_run_custom_filter`)<br>`lib/Postfilter/NG.pm:780` (`_custom_error_result`) |
| 64 | `PF-RATE-064` | active | Too many errors for your IP | `access.*_limits.max_total_errors / access_profile.limits.max_total_errors` | `lib/Postfilter/Checks/Access.pm:36` (`<file scope>`) |
| 65 | `PF-RATE-065` | active | Too many errors for your domain | `access.*_limits.max_total_errors / access_profile.limits.max_total_errors` | `lib/Postfilter/Checks/Access.pm:48` (`<file scope>`) |
| 66 | `PF-RATE-066` | active | Too many errors for your userid | `access.*_limits.max_total_errors / access_profile.limits.max_total_errors` | `lib/Postfilter/Checks/Access.pm:60` (`<file scope>`) |
| 67 | `PF-RATE-067` | active | Too many errors for your IP in a short period | `access.*_limits.max_short_errors / access_profile.limits.max_short_errors` | `lib/Postfilter/Checks/Access.pm:37` (`<file scope>`) |
| 68 | `PF-RATE-068` | active | Too many errors for your domain in a short period | `access.*_limits.max_short_errors / access_profile.limits.max_short_errors` | `lib/Postfilter/Checks/Access.pm:49` (`<file scope>`) |
| 69 | `PF-RATE-069` | active | Too many errors for your userid in a short period | `access.*_limits.max_short_errors / access_profile.limits.max_short_errors` | `lib/Postfilter/Checks/Access.pm:61` (`<file scope>`) |
| 70 | `PF-RATE-070` | active | Too many messages for your IP in a short period | `access.*_limits.max_short_articles / access_profile.limits.max_short_articles` | `lib/Postfilter/Checks/Access.pm:35` (`<file scope>`) |
| 71 | `PF-RATE-071` | active | Too many messages for your domain in a short period | `access.*_limits.max_short_articles / access_profile.limits.max_short_articles` | `lib/Postfilter/Checks/Access.pm:47` (`<file scope>`) |
| 72 | `PF-RATE-072` | active | Too many messages for your userid in a short period | `access.*_limits.max_short_articles / access_profile.limits.max_short_articles` | `lib/Postfilter/Checks/Access.pm:59` (`<file scope>`) |
| 73 | `PF-RATE-073` | active | Too many bytes for your IP in a short period | `access.*_limits.max_short_size / access_profile.limits.max_short_size` | `lib/Postfilter/Checks/Access.pm:38` (`<file scope>`) |
| 74 | `PF-RATE-074` | active | Too many bytes for your domain in a short period | `access.*_limits.max_short_size / access_profile.limits.max_short_size` | `lib/Postfilter/Checks/Access.pm:50` (`<file scope>`) |
| 75 | `PF-RATE-075` | active | Too many bytes for your userid in a short period | `access.*_limits.max_short_size / access_profile.limits.max_short_size` | `lib/Postfilter/Checks/Access.pm:62` (`<file scope>`) |
| 76 | `PF-RATE-076` | active | Too many bytes for your IP | `access.*_limits.max_total_size / access_profile.limits.max_total_size` | `lib/Postfilter/Checks/Access.pm:39` (`<file scope>`) |
| 77 | `PF-RATE-077` | active | Too many bytes for your domain | `access.*_limits.max_total_size / access_profile.limits.max_total_size` | `lib/Postfilter/Checks/Access.pm:51` (`<file scope>`) |
| 78 | `PF-RATE-078` | active | Too many bytes for your userid | `access.*_limits.max_total_size / access_profile.limits.max_total_size` | `lib/Postfilter/Checks/Access.pm:63` (`<file scope>`) |
| 79 | `PF-RATE-079` | active | Too many newsgroups for your IP in a short period | `access.*_limits.max_short_groups / access_profile.limits.max_short_groups` | `lib/Postfilter/Checks/Access.pm:40` (`<file scope>`) |
| 80 | `PF-RATE-080` | active | Too many newsgroups for your domain in a short period | `access.*_limits.max_short_groups / access_profile.limits.max_short_groups` | `lib/Postfilter/Checks/Access.pm:52` (`<file scope>`) |
| 81 | `PF-RATE-081` | active | Too many newsgroups for your userid in a short period | `access.*_limits.max_short_groups / access_profile.limits.max_short_groups` | `lib/Postfilter/Checks/Access.pm:64` (`<file scope>`) |
| 82 | `PF-RATE-082` | active | Too many newsgroups for your IP | `access.*_limits.max_total_groups / access_profile.limits.max_total_groups` | `lib/Postfilter/Checks/Access.pm:41` (`<file scope>`) |
| 83 | `PF-RATE-083` | active | Too many newsgroups for your domain | `access.*_limits.max_total_groups / access_profile.limits.max_total_groups` | `lib/Postfilter/Checks/Access.pm:53` (`<file scope>`) |
| 84 | `PF-RATE-084` | active | Too many newsgroups for your userid | `access.*_limits.max_total_groups / access_profile.limits.max_total_groups` | `lib/Postfilter/Checks/Access.pm:65` (`<file scope>`) |
| 85 | `PF-RATE-085` | active | Too many followups for your IP in a short period | `access.*_limits.max_short_followups / access_profile.limits.max_short_followups` | `lib/Postfilter/Checks/Access.pm:42` (`<file scope>`) |
| 86 | `PF-RATE-086` | active | Too many followups for your domain in a short period | `access.*_limits.max_short_followups / access_profile.limits.max_short_followups` | `lib/Postfilter/Checks/Access.pm:54` (`<file scope>`) |
| 87 | `PF-RATE-087` | active | Too many followups for your userid in a short period | `access.*_limits.max_short_followups / access_profile.limits.max_short_followups` | `lib/Postfilter/Checks/Access.pm:66` (`<file scope>`) |
| 88 | `PF-RATE-088` | active | Too many followups for your IP | `access.*_limits.max_total_followups / access_profile.limits.max_total_followups` | `lib/Postfilter/Checks/Access.pm:43` (`<file scope>`) |
| 89 | `PF-RATE-089` | active | Too many followups for your domain | `access.*_limits.max_total_followups / access_profile.limits.max_total_followups` | `lib/Postfilter/Checks/Access.pm:55` (`<file scope>`) |
| 90 | `PF-RATE-090` | active | Too many followups for your userid | `access.*_limits.max_total_followups / access_profile.limits.max_total_followups` | `lib/Postfilter/Checks/Access.pm:67` (`<file scope>`) |
| 91 | `PF-RULE-091` | compatibility/reserved | Article rejected by sender request | `banlist/badword/custom output action` | _No direct runtime call-site found_ |
| 92 | `PF-CONFIG-092` | compatibility/reserved | Syntax error in main configuration | `postfilter.toml` | _No direct runtime call-site found_ |
| 93 | `PF-CONFIG-093` | compatibility/reserved | Syntax error in access configuration | `conf.d/30-access-profiles.toml` | _No direct runtime call-site found_ |
| 94 | `PF-CONFIG-094` | compatibility/reserved | Syntax error in rules configuration | `conf.d rule files` | _No direct runtime call-site found_ |
| 95 | `PF-GROUP-095` | active | Crossposting between text and binary groups is forbidden | `article_types.mixed_crosspost_policy` | `lib/Postfilter/NG.pm:486` (`_run_pipeline`) |
| 96 | `PF-BODY-096` | active | Text article body exceeds the configured text limit | `article_types.text.limits.max_body_size` | `lib/Postfilter/Context.pm:614` (`size_rejection_code`) |
| 97 | `PF-HEADER-097` | active | Text article headers exceed the configured text limit | `article_types.text.limits.max_header_size` | `lib/Postfilter/Context.pm:615` (`size_rejection_code`) |
| 98 | `PF-BODY-098` | active | Text article total size exceeds the configured text limit | `article_types.text.limits.max_total_size` | `lib/Postfilter/Context.pm:616` (`size_rejection_code`) |
| 99 | `PF-BODY-099` | active | Binary article body exceeds the configured binary limit | `article_types.binary.limits.max_body_size` | `lib/Postfilter/Context.pm:619` (`size_rejection_code`) |
| 100 | `PF-HEADER-100` | active | Binary article headers exceed the configured binary limit | `article_types.binary.limits.max_header_size` | `lib/Postfilter/Context.pm:620` (`size_rejection_code`) |
| 101 | `PF-BODY-101` | active | Binary article total size exceeds the configured binary limit | `article_types.binary.limits.max_total_size` | `lib/Postfilter/Context.pm:621` (`size_rejection_code`) |
| 102 | `PF-BODY-102` | active | Binary payload is forbidden by the selected article policy | `article_types.binary.content.allow_yenc / allow_uuencode` | `lib/Postfilter/Checks/Content.pm:61` (`run_binary`)<br>`lib/Postfilter/Checks/Content.pm:68` (`run_binary`) |
| 103 | `PF-POLICY-103` | compatibility/reserved | Unable to determine a valid article type policy | `article_types.*` | _No direct runtime call-site found_ |
| 104 | `PF-HEADER-104` | compatibility/reserved | Forbidden or invalid character in header | `header character validation` | _No direct runtime call-site found_ |
| 105 | `PF-AUTH-105` | active | Unable to load per-group user database | `userdb.*` | `lib/Postfilter/Checks/UserDB.pm:48` (`run`)<br>`lib/Postfilter/Checks/UserDB.pm:58` (`run`) |
| 106 | `PF-AUTH-106` | active | Sender is not authorized for this group | `userdb.*` | `lib/Postfilter/Checks/UserDB.pm:61` (`run`) |
| 107 | `PF-DB-107` | active | Unable to store local Distribution state | `distributions / database.*` | `lib/Postfilter/NG.pm:325` (`process_article`) |
| 108 | `PF-GROUP-108` | compatibility/reserved | Invalid Distribution value | `distributions / headers.check_distribution` | _No direct runtime call-site found_ |
| 109 | `PF-MIME-109` | active | multipart/mixed is forbidden in text groups | `article_types.text.mime` | `lib/Postfilter/Config.pm:1386` (`_apply_defaults`) |
| 110 | `PF-MIME-110` | active | MIME media type is forbidden in text groups | `article_types.text.mime.allowed_media_types / forbidden_media_types` | `lib/Postfilter/Checks/Attachments.pm:158` (`top_level_content_type_is_managed`)<br>`lib/Postfilter/Config.pm:1387` (`_apply_defaults`) |
| 111 | `PF-MIME-111` | active | MIME attachment metadata is forbidden in text groups | `article_types.text.mime` | `lib/Postfilter/Config.pm:1388` (`_apply_defaults`) |
| 112 | `PF-BODY-112` | active | Probable Base64 attachment is forbidden in text groups | `article_types.text.mime Base64 thresholds` | `lib/Postfilter/Checks/Attachments.pm:689` (`_estimated_decoded_bytes`)<br>`lib/Postfilter/Checks/Attachments.pm:714` (`_detect_large_base64_block`)<br>`lib/Postfilter/Checks/Attachments.pm:726` (`_detect_large_base64_block`)<br>`lib/Postfilter/Checks/Attachments.pm:782` (`_detect_large_base64_block`)<br>`lib/Postfilter/Checks/Attachments.pm:793` (`_detect_large_base64_block`)<br>`lib/Postfilter/Config.pm:1389` (`_apply_defaults`) |
| 113 | `PF-MIME-113` | active | Malformed MIME structure in text article | `article_types.text.mime.on_malformed` | `lib/Postfilter/Checks/Attachments.pm:959` (`_malformed_result`)<br>`lib/Postfilter/Config.pm:1390` (`_apply_defaults`) |
| 114 | `PF-MIME-114` | active | Unapproved multipart container is forbidden in text groups | `article_types.text.mime.allowed_multipart_types` | `lib/Postfilter/Config.pm:1391` (`_apply_defaults`) |
| 115 | `PF-GROUP-115` | active | Invalid Newsgroups syntax | `Newsgroups structural preflight` | `lib/Postfilter/NG.pm:459` (`_run_pipeline`) |
| 116 | `PF-GROUP-116` | active | Invalid Followup-To syntax | `Followup-To structural preflight` | `lib/Postfilter/NG.pm:461` (`_run_pipeline`) |
| 117 | `PF-RFC-117` | active | Article violates RFC 5536 syntax | `RFC 5536 invariant preflight` | `lib/Postfilter/HeaderTransform.pm:218` (`_transform_injection_information`)<br>`lib/Postfilter/NG.pm:471` (`_run_pipeline`) |
| 118 | `PF-RFC-118` | active | Header transformation produced invalid RFC 5536 output | `RFC 5536 post-transform invariant` | `lib/Postfilter/HeaderTransform.pm:238` (`_transform_injection_information`)<br>`lib/Postfilter/NG.pm:606` (`_run_pipeline`) |

## Reading the table

`active` means at least one runtime call-site was found in this release.  `compatibility/reserved` means the historical code remains stable but no direct emitter was found by the release scanner.  This is not automatically an error: some codes are retained for compatibility or are produced indirectly.

## Index by category

- **AUTH:** `PF-AUTH-105`, `PF-AUTH-106`
- **BODY:** `PF-BODY-009`, `PF-BODY-012`, `PF-BODY-013`, `PF-BODY-014`, `PF-BODY-015`, `PF-BODY-016`, `PF-BODY-052`, `PF-BODY-057`, `PF-BODY-062`, `PF-BODY-096`, `PF-BODY-098`, `PF-BODY-099`, `PF-BODY-101`, `PF-BODY-102`, `PF-BODY-112`
- **CONFIG:** `PF-CONFIG-027`, `PF-CONFIG-035`, `PF-CONFIG-038`, `PF-CONFIG-039`, `PF-CONFIG-042`, `PF-CONFIG-043`, `PF-CONFIG-059`, `PF-CONFIG-092`, `PF-CONFIG-093`, `PF-CONFIG-094`
- **DATE:** `PF-DATE-019`, `PF-DATE-058`
- **DB:** `PF-DB-036`, `PF-DB-040`, `PF-DB-044`, `PF-DB-045`, `PF-DB-046`, `PF-DB-107`
- **GROUP:** `PF-GROUP-002`, `PF-GROUP-004`, `PF-GROUP-006`, `PF-GROUP-007`, `PF-GROUP-008`, `PF-GROUP-010`, `PF-GROUP-017`, `PF-GROUP-018`, `PF-GROUP-025`, `PF-GROUP-026`, `PF-GROUP-037`, `PF-GROUP-054`, `PF-GROUP-095`, `PF-GROUP-108`, `PF-GROUP-115`, `PF-GROUP-116`
- **HEADER:** `PF-HEADER-001`, `PF-HEADER-003`, `PF-HEADER-011`, `PF-HEADER-020`, `PF-HEADER-021`, `PF-HEADER-022`, `PF-HEADER-023`, `PF-HEADER-024`, `PF-HEADER-051`, `PF-HEADER-053`, `PF-HEADER-097`, `PF-HEADER-100`, `PF-HEADER-104`
- **INTERNAL:** `PF-INTERNAL-000`, `PF-INTERNAL-055`
- **MIME:** `PF-MIME-005`, `PF-MIME-109`, `PF-MIME-110`, `PF-MIME-111`, `PF-MIME-113`, `PF-MIME-114`
- **POLICY:** `PF-POLICY-047`, `PF-POLICY-048`, `PF-POLICY-103`
- **RATE:** `PF-RATE-030`, `PF-RATE-031`, `PF-RATE-032`, `PF-RATE-033`, `PF-RATE-064`, `PF-RATE-065`, `PF-RATE-066`, `PF-RATE-067`, `PF-RATE-068`, `PF-RATE-069`, `PF-RATE-070`, `PF-RATE-071`, `PF-RATE-072`, `PF-RATE-073`, `PF-RATE-074`, `PF-RATE-075`, `PF-RATE-076`, `PF-RATE-077`, `PF-RATE-078`, `PF-RATE-079`, `PF-RATE-080`, `PF-RATE-081`, `PF-RATE-082`, `PF-RATE-083`, `PF-RATE-084`, `PF-RATE-085`, `PF-RATE-086`, `PF-RATE-087`, `PF-RATE-088`, `PF-RATE-089`, `PF-RATE-090`
- **RBL:** `PF-RBL-056`
- **RFC:** `PF-RFC-117`, `PF-RFC-118`
- **RULE:** `PF-RULE-028`, `PF-RULE-029`, `PF-RULE-034`, `PF-RULE-049`, `PF-RULE-063`, `PF-RULE-091`
- **SAVE:** `PF-SAVE-041`
- **TOR:** `PF-TOR-050`
- **URIBL:** `PF-URIBL-060`, `PF-URIBL-061`

## Index by configuration / policy

- `Followup-To structural preflight`: `PF-GROUP-116`
- `Newsgroups structural preflight`: `PF-GROUP-115`
- `RFC 5536 invariant preflight`: `PF-RFC-117`
- `RFC 5536 post-transform invariant`: `PF-RFC-118`
- `access.*_limits.max_articles / access_profile.limits.max_articles`: `PF-RATE-031`, `PF-RATE-032`, `PF-RATE-033`
- `access.*_limits.max_short_articles / access_profile.limits.max_short_articles`: `PF-RATE-070`, `PF-RATE-071`, `PF-RATE-072`
- `access.*_limits.max_short_errors / access_profile.limits.max_short_errors`: `PF-RATE-067`, `PF-RATE-068`, `PF-RATE-069`
- `access.*_limits.max_short_followups / access_profile.limits.max_short_followups`: `PF-RATE-085`, `PF-RATE-086`, `PF-RATE-087`
- `access.*_limits.max_short_groups / access_profile.limits.max_short_groups`: `PF-RATE-079`, `PF-RATE-080`, `PF-RATE-081`
- `access.*_limits.max_short_size / access_profile.limits.max_short_size`: `PF-RATE-073`, `PF-RATE-074`, `PF-RATE-075`
- `access.*_limits.max_total_errors / access_profile.limits.max_total_errors`: `PF-RATE-064`, `PF-RATE-065`, `PF-RATE-066`
- `access.*_limits.max_total_followups / access_profile.limits.max_total_followups`: `PF-RATE-088`, `PF-RATE-089`, `PF-RATE-090`
- `access.*_limits.max_total_groups / access_profile.limits.max_total_groups`: `PF-RATE-082`, `PF-RATE-083`, `PF-RATE-084`
- `access.*_limits.max_total_size / access_profile.limits.max_total_size`: `PF-RATE-076`, `PF-RATE-077`, `PF-RATE-078`
- `article_types.*`: `PF-POLICY-103`
- `article_types.binary.content.allow_yenc / allow_uuencode`: `PF-BODY-102`
- `article_types.binary.limits.max_body_size`: `PF-BODY-099`
- `article_types.binary.limits.max_header_size`: `PF-HEADER-100`
- `article_types.binary.limits.max_total_size`: `PF-BODY-101`
- `article_types.mixed_crosspost_policy`: `PF-GROUP-095`
- `article_types.text.content.allow_uuencode`: `PF-BODY-052`
- `article_types.text.content.allow_yenc`: `PF-BODY-062`
- `article_types.text.limits.max_body_size`: `PF-BODY-096`
- `article_types.text.limits.max_header_size`: `PF-HEADER-097`
- `article_types.text.limits.max_total_size`: `PF-BODY-098`
- `article_types.text.mime`: `PF-MIME-109`, `PF-MIME-111`
- `article_types.text.mime Base64 thresholds`: `PF-BODY-112`
- `article_types.text.mime.allowed_media_types / forbidden_media_types`: `PF-MIME-110`
- `article_types.text.mime.allowed_multipart_types`: `PF-MIME-114`
- `article_types.text.mime.on_malformed`: `PF-MIME-113`
- `badwords.max_body_score / badword rules`: `PF-RULE-029`
- `badwords.max_subject_score / badword rules`: `PF-RULE-028`
- `banlist.max_score`: `PF-RULE-049`
- `banlist/badword/custom output action`: `PF-RULE-091`
- `conf.d rule files`: `PF-CONFIG-094`
- `conf.d/10-structural-rules.toml: forbidden_crosspost`: `PF-GROUP-002`
- `conf.d/10-structural-rules.toml: forbidden_groups`: `PF-GROUP-054`
- `conf.d/30-access-profiles.toml`: `PF-CONFIG-093`
- `conf.d/40-reputation.toml: dnsbl`: `PF-RBL-056`
- `conf.d/40-reputation.toml: surbl`: `PF-URIBL-060`
- `conf.d/40-reputation.toml: uribl`: `PF-URIBL-061`
- `conf.d/50-badwords.toml`: `PF-CONFIG-027`, `PF-CONFIG-038`
- `conf.d/60-banlist.toml`: `PF-RULE-034`, `PF-CONFIG-035`, `PF-CONFIG-039`
- `content_type_rule / article type checks`: `PF-MIME-005`
- `custom.* / conf/custom.pm`: `PF-RULE-063`
- `database.*`: `PF-DB-036`, `PF-DB-044`, `PF-DB-046`
- `database.* / policy database failure action`: `PF-DB-040`
- `date policy`: `PF-DATE-019`, `PF-DATE-058`
- `distributions / database.*`: `PF-DB-107`
- `distributions / headers.check_distribution`: `PF-GROUP-108`
- `forbidden_header_rule`: `PF-HEADER-053`
- `header character validation`: `PF-HEADER-104`
- `header style policy`: `PF-HEADER-011`, `PF-HEADER-024`
- `headers.allow_html / html_allowed_groups / html_patterns`: `PF-BODY-016`
- `headers.allow_mail_headers / headers.delete_mail_headers`: `PF-HEADER-022`
- `headers.check_distribution / distributions`: `PF-GROUP-004`
- `headers.check_groups_existence / paths.active_file`: `PF-GROUP-017`, `PF-GROUP-018`
- `headers.path`: `PF-HEADER-020`
- `installer --innconfval / PATH`: `PF-CONFIG-042`
- `limits.default_multipost_limit / limits.absolute_multipost_limit / access_profile.limits.multipost`: `PF-RATE-030`
- `limits.max_blank_ratio`: `PF-BODY-014`
- `limits.max_body_size`: `PF-BODY-009`
- `limits.max_crosspost`: `PF-GROUP-006`
- `limits.max_empty_ratio`: `PF-BODY-015`
- `limits.max_followup`: `PF-GROUP-007`
- `limits.max_fup_no_crosspost`: `PF-GROUP-008`
- `limits.max_groups_difference`: `PF-GROUP-010`
- `limits.max_header_length`: `PF-HEADER-021`
- `limits.max_header_size`: `PF-HEADER-023`
- `limits.max_hierarchies_followup`: `PF-GROUP-026`
- `limits.max_hierarchies_post`: `PF-GROUP-025`
- `limits.max_line_length`: `PF-BODY-012`
- `limits.max_quoted_ratio`: `PF-BODY-013`
- `limits.max_total_size`: `PF-BODY-057`
- `moderation/Approved policy`: `PF-HEADER-003`
- `n/a`: `PF-INTERNAL-000`
- `paths.active_file`: `PF-GROUP-037`
- `paths.public_suffix_file`: `PF-CONFIG-059`
- `policy.action_on_reject`: `PF-POLICY-047`
- `postfilter.toml`: `PF-CONFIG-092`
- `postfilter.toml / conf.d`: `PF-CONFIG-043`
- `posting policy`: `PF-POLICY-048`
- `retention.* / maintenance`: `PF-DB-045`
- `runtime module loading`: `PF-INTERNAL-055`
- `saved_articles.*`: `PF-SAVE-041`
- `style.control`: `PF-HEADER-001`, `PF-HEADER-051`
- `tor.action / tor.*`: `PF-TOR-050`
- `userdb.*`: `PF-AUTH-105`, `PF-AUTH-106`

## Detailed active-code reference

### `PF-INTERNAL-000` (legacy 0)

- **Meaning:** Message successfully sent
- **Trigger:** Compatibility/reserved code or internal condition
- **Configuration:** `n/a`
- **Source:**
  - `lib/Postfilter/NG.pm:687` — `_run_custom_filter()`
  - `lib/Postfilter/Result.pm:68` — `code()`
  - `lib/Postfilter/SavedArticle.pm:77` — `save()`

### `PF-HEADER-001` (legacy 1)

- **Meaning:** Control messages are forbidden
- **Trigger:** Control header policy
- **Configuration:** `style.control`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:227` — `_check_control_headers()`

### `PF-GROUP-002` (legacy 2)

- **Meaning:** Forbidden crosspost
- **Trigger:** Forbidden crosspost rule
- **Configuration:** `conf.d/10-structural-rules.toml: forbidden_crosspost`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:267` — `_check_forbidden_crossposts()`

### `PF-HEADER-003` (legacy 3)

- **Meaning:** You cannot approve messages
- **Trigger:** Approved header policy
- **Configuration:** `moderation/Approved policy`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:295` — `_check_approved_header()`

### `PF-GROUP-004` (legacy 4)

- **Meaning:** Invalid Distribution header
- **Trigger:** Distribution header policy
- **Configuration:** `headers.check_distribution / distributions`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:321` — `_check_distribution_header()`

### `PF-MIME-005` (legacy 5)

- **Meaning:** Invalid Content-Type
- **Trigger:** Content-Type policy
- **Configuration:** `content_type_rule / article type checks`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:367` — `_check_content_type()`

### `PF-GROUP-006` (legacy 6)

- **Meaning:** Too many groups in Newsgroups
- **Trigger:** Newsgroups target limit
- **Configuration:** `limits.max_crosspost`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:96` — `run()`

### `PF-GROUP-007` (legacy 7)

- **Meaning:** Too many groups in Followup-To
- **Trigger:** Followup-To target limit
- **Configuration:** `limits.max_followup`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:99` — `run()`

### `PF-GROUP-008` (legacy 8)

- **Meaning:** Missing Followup-To header
- **Trigger:** Followup-To requirement
- **Configuration:** `limits.max_fup_no_crosspost`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:102` — `run()`

### `PF-GROUP-010` (legacy 10)

- **Meaning:** Difference between crossposts and followups is too large
- **Trigger:** Crosspost/followup difference limit
- **Configuration:** `limits.max_groups_difference`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:106` — `run()`

### `PF-HEADER-011` (legacy 11)

- **Meaning:** Re: without References
- **Trigger:** References required for Re:
- **Configuration:** `header style policy`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:122` — `run()`

### `PF-BODY-012` (legacy 12)

- **Meaning:** Line too long
- **Trigger:** Maximum body line length
- **Configuration:** `limits.max_line_length`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:131` — `run()`

### `PF-BODY-013` (legacy 13)

- **Meaning:** Too many quoted lines
- **Trigger:** Quoted-line ratio
- **Configuration:** `limits.max_quoted_ratio`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:135` — `run()`

### `PF-BODY-014` (legacy 14)

- **Meaning:** Too many blank lines
- **Trigger:** Blank-line ratio
- **Configuration:** `limits.max_blank_ratio`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:139` — `run()`

### `PF-BODY-015` (legacy 15)

- **Meaning:** Too many empty lines
- **Trigger:** Empty-line ratio
- **Configuration:** `limits.max_empty_ratio`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:143` — `run()`

### `PF-BODY-016` (legacy 16)

- **Meaning:** HTML content is forbidden
- **Trigger:** HTML policy
- **Configuration:** `headers.allow_html / html_allowed_groups / html_patterns`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:394` — `_check_html()`

### `PF-GROUP-017` (legacy 17)

- **Meaning:** Nonexistent group
- **Trigger:** Newsgroups existence
- **Configuration:** `headers.check_groups_existence / paths.active_file`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:444` — `_check_group_existence()`

### `PF-GROUP-018` (legacy 18)

- **Meaning:** Nonexistent group in Followup-To
- **Trigger:** Followup-To group existence
- **Configuration:** `headers.check_groups_existence / paths.active_file`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:450` — `_check_group_existence()`

### `PF-DATE-019` (legacy 19)

- **Meaning:** Date is too far in the future
- **Trigger:** Missing, invalid or future Date
- **Configuration:** `date policy`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:476` — `_check_date()`
  - `lib/Postfilter/Checks/Style.pm:488` — `_check_date()`
  - `lib/Postfilter/Checks/Style.pm:499` — `_check_date()`

### `PF-HEADER-020` (legacy 20)

- **Meaning:** Invalid Path
- **Trigger:** Path syntax/policy
- **Configuration:** `headers.path`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:596` — `_check_path()`

### `PF-HEADER-021` (legacy 21)

- **Meaning:** A header is too long
- **Trigger:** Individual header length
- **Configuration:** `limits.max_header_length`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:172` — `run()`

### `PF-HEADER-022` (legacy 22)

- **Meaning:** Mail headers are forbidden
- **Trigger:** Mail-header policy
- **Configuration:** `headers.allow_mail_headers / headers.delete_mail_headers`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:181` — `run()`

### `PF-HEADER-024` (legacy 24)

- **Meaning:** Invalid In-Reply-To
- **Trigger:** In-Reply-To syntax
- **Configuration:** `header style policy`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:186` — `run()`

### `PF-GROUP-025` (legacy 25)

- **Meaning:** Too many hierarchies
- **Trigger:** Newsgroups hierarchy limit
- **Configuration:** `limits.max_hierarchies_post`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:155` — `run()`

### `PF-GROUP-026` (legacy 26)

- **Meaning:** Too many hierarchies in Followup-To
- **Trigger:** Followup-To hierarchy limit
- **Configuration:** `limits.max_hierarchies_followup`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:159` — `run()`

### `PF-RULE-028` (legacy 28)

- **Meaning:** Badword in Subject
- **Trigger:** Subject badword score
- **Configuration:** `badwords.max_subject_score / badword rules`
- **Source:**
  - `lib/Postfilter/Checks/Content.pm:195` — `run_badwords()`

### `PF-RULE-029` (legacy 29)

- **Meaning:** Badword in body
- **Trigger:** Body badword score
- **Configuration:** `badwords.max_body_score / badword rules`
- **Source:**
  - `lib/Postfilter/Checks/Content.pm:198` — `run_badwords()`

### `PF-RATE-031` (legacy 31)

- **Meaning:** Your IP has sent too many articles
- **Trigger:** Long-window article rate
- **Configuration:** `access.*_limits.max_articles / access_profile.limits.max_articles`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:34` — `<file scope>()`

### `PF-RATE-032` (legacy 32)

- **Meaning:** Your domain has sent too many articles
- **Trigger:** Long-window article rate
- **Configuration:** `access.*_limits.max_articles / access_profile.limits.max_articles`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:46` — `<file scope>()`

### `PF-RATE-033` (legacy 33)

- **Meaning:** Your userid has sent too many articles
- **Trigger:** Long-window article rate
- **Configuration:** `access.*_limits.max_articles / access_profile.limits.max_articles`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:58` — `<file scope>()`

### `PF-GROUP-037` (legacy 37)

- **Meaning:** Unable to load active file
- **Trigger:** INN active file
- **Configuration:** `paths.active_file`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:419` — `_check_group_existence()`
  - `lib/Postfilter/Checks/Style.pm:426` — `_check_group_existence()`

### `PF-DB-040` (legacy 40)

- **Meaning:** Unable to open persistent storage
- **Trigger:** Persistent storage failure
- **Configuration:** `database.* / policy database failure action`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:312` — `_database_failure_result()`
  - `lib/Postfilter/NG.pm:368` — `process_article()`

### `PF-SAVE-041` (legacy 41)

- **Meaning:** Unable to save article
- **Trigger:** Rejected-article diagnostic saving
- **Configuration:** `saved_articles.*`
- **Source:**
  - `lib/Postfilter/NG.pm:291` — `process_article()`

### `PF-POLICY-048` (legacy 48)

- **Meaning:** Server closed for posting
- **Trigger:** Server closed for posting
- **Configuration:** `posting policy`
- **Source:**
  - `lib/Postfilter/NG.pm:445` — `_run_pipeline()`

### `PF-TOR-050` (legacy 50)

- **Meaning:** TOR is forbidden
- **Trigger:** TOR policy
- **Configuration:** `tor.action / tor.*`
- **Source:**
  - `lib/Postfilter/Checks/Reputation.pm:82` — `run_tor()`
  - `lib/Postfilter/Checks/Reputation.pm:93` — `run_tor()`

### `PF-HEADER-051` (legacy 51)

- **Meaning:** Supersedes, Replaces and Cancel are forbidden
- **Trigger:** Supersedes/Replaces/Cancel policy
- **Configuration:** `style.control`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:232` — `_check_control_headers()`

### `PF-BODY-052` (legacy 52)

- **Meaning:** UUEncoded binaries are forbidden
- **Trigger:** UUEncode text policy
- **Configuration:** `article_types.text.content.allow_uuencode`
- **Source:**
  - `lib/Postfilter/Checks/Content.pm:62` — `run_binary()`
  - `lib/Postfilter/Config.pm:1384` — `_apply_defaults()`

### `PF-GROUP-054` (legacy 54)

- **Meaning:** Permanently closed group
- **Trigger:** Closed-to-posting group policy
- **Configuration:** `conf.d/10-structural-rules.toml: forbidden_groups`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:567` — `_check_forbidden_groups()`

### `PF-DATE-058` (legacy 58)

- **Meaning:** Message too old
- **Trigger:** Maximum article age
- **Configuration:** `date policy`
- **Source:**
  - `lib/Postfilter/Checks/Style.pm:502` — `_check_date()`

### `PF-BODY-062` (legacy 62)

- **Meaning:** yEnc contents are forbidden
- **Trigger:** yEnc text policy
- **Configuration:** `article_types.text.content.allow_yenc`
- **Source:**
  - `lib/Postfilter/Checks/Content.pm:69` — `run_binary()`
  - `lib/Postfilter/Config.pm:1385` — `_apply_defaults()`

### `PF-RULE-063` (legacy 63)

- **Meaning:** Message rejected by a custom rule
- **Trigger:** Custom rule rejection
- **Configuration:** `custom.* / conf/custom.pm`
- **Source:**
  - `lib/Postfilter/NG.pm:691` — `_run_custom_filter()`
  - `lib/Postfilter/NG.pm:780` — `_custom_error_result()`

### `PF-RATE-064` (legacy 64)

- **Meaning:** Too many errors for your IP
- **Trigger:** Long-window error rate
- **Configuration:** `access.*_limits.max_total_errors / access_profile.limits.max_total_errors`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:36` — `<file scope>()`

### `PF-RATE-065` (legacy 65)

- **Meaning:** Too many errors for your domain
- **Trigger:** Long-window error rate
- **Configuration:** `access.*_limits.max_total_errors / access_profile.limits.max_total_errors`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:48` — `<file scope>()`

### `PF-RATE-066` (legacy 66)

- **Meaning:** Too many errors for your userid
- **Trigger:** Long-window error rate
- **Configuration:** `access.*_limits.max_total_errors / access_profile.limits.max_total_errors`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:60` — `<file scope>()`

### `PF-RATE-067` (legacy 67)

- **Meaning:** Too many errors for your IP in a short period
- **Trigger:** Short-window error rate
- **Configuration:** `access.*_limits.max_short_errors / access_profile.limits.max_short_errors`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:37` — `<file scope>()`

### `PF-RATE-068` (legacy 68)

- **Meaning:** Too many errors for your domain in a short period
- **Trigger:** Short-window error rate
- **Configuration:** `access.*_limits.max_short_errors / access_profile.limits.max_short_errors`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:49` — `<file scope>()`

### `PF-RATE-069` (legacy 69)

- **Meaning:** Too many errors for your userid in a short period
- **Trigger:** Short-window error rate
- **Configuration:** `access.*_limits.max_short_errors / access_profile.limits.max_short_errors`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:61` — `<file scope>()`

### `PF-RATE-070` (legacy 70)

- **Meaning:** Too many messages for your IP in a short period
- **Trigger:** Short-window article rate
- **Configuration:** `access.*_limits.max_short_articles / access_profile.limits.max_short_articles`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:35` — `<file scope>()`

### `PF-RATE-071` (legacy 71)

- **Meaning:** Too many messages for your domain in a short period
- **Trigger:** Short-window article rate
- **Configuration:** `access.*_limits.max_short_articles / access_profile.limits.max_short_articles`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:47` — `<file scope>()`

### `PF-RATE-072` (legacy 72)

- **Meaning:** Too many messages for your userid in a short period
- **Trigger:** Short-window article rate
- **Configuration:** `access.*_limits.max_short_articles / access_profile.limits.max_short_articles`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:59` — `<file scope>()`

### `PF-RATE-073` (legacy 73)

- **Meaning:** Too many bytes for your IP in a short period
- **Trigger:** Short-window byte rate
- **Configuration:** `access.*_limits.max_short_size / access_profile.limits.max_short_size`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:38` — `<file scope>()`

### `PF-RATE-074` (legacy 74)

- **Meaning:** Too many bytes for your domain in a short period
- **Trigger:** Short-window byte rate
- **Configuration:** `access.*_limits.max_short_size / access_profile.limits.max_short_size`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:50` — `<file scope>()`

### `PF-RATE-075` (legacy 75)

- **Meaning:** Too many bytes for your userid in a short period
- **Trigger:** Short-window byte rate
- **Configuration:** `access.*_limits.max_short_size / access_profile.limits.max_short_size`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:62` — `<file scope>()`

### `PF-RATE-076` (legacy 76)

- **Meaning:** Too many bytes for your IP
- **Trigger:** Long-window byte rate
- **Configuration:** `access.*_limits.max_total_size / access_profile.limits.max_total_size`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:39` — `<file scope>()`

### `PF-RATE-077` (legacy 77)

- **Meaning:** Too many bytes for your domain
- **Trigger:** Long-window byte rate
- **Configuration:** `access.*_limits.max_total_size / access_profile.limits.max_total_size`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:51` — `<file scope>()`

### `PF-RATE-078` (legacy 78)

- **Meaning:** Too many bytes for your userid
- **Trigger:** Long-window byte rate
- **Configuration:** `access.*_limits.max_total_size / access_profile.limits.max_total_size`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:63` — `<file scope>()`

### `PF-RATE-079` (legacy 79)

- **Meaning:** Too many newsgroups for your IP in a short period
- **Trigger:** Short-window Newsgroups target rate
- **Configuration:** `access.*_limits.max_short_groups / access_profile.limits.max_short_groups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:40` — `<file scope>()`

### `PF-RATE-080` (legacy 80)

- **Meaning:** Too many newsgroups for your domain in a short period
- **Trigger:** Short-window Newsgroups target rate
- **Configuration:** `access.*_limits.max_short_groups / access_profile.limits.max_short_groups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:52` — `<file scope>()`

### `PF-RATE-081` (legacy 81)

- **Meaning:** Too many newsgroups for your userid in a short period
- **Trigger:** Short-window Newsgroups target rate
- **Configuration:** `access.*_limits.max_short_groups / access_profile.limits.max_short_groups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:64` — `<file scope>()`

### `PF-RATE-082` (legacy 82)

- **Meaning:** Too many newsgroups for your IP
- **Trigger:** Long-window Newsgroups target rate
- **Configuration:** `access.*_limits.max_total_groups / access_profile.limits.max_total_groups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:41` — `<file scope>()`

### `PF-RATE-083` (legacy 83)

- **Meaning:** Too many newsgroups for your domain
- **Trigger:** Long-window Newsgroups target rate
- **Configuration:** `access.*_limits.max_total_groups / access_profile.limits.max_total_groups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:53` — `<file scope>()`

### `PF-RATE-084` (legacy 84)

- **Meaning:** Too many newsgroups for your userid
- **Trigger:** Long-window Newsgroups target rate
- **Configuration:** `access.*_limits.max_total_groups / access_profile.limits.max_total_groups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:65` — `<file scope>()`

### `PF-RATE-085` (legacy 85)

- **Meaning:** Too many followups for your IP in a short period
- **Trigger:** Short-window Followup-To target rate
- **Configuration:** `access.*_limits.max_short_followups / access_profile.limits.max_short_followups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:42` — `<file scope>()`

### `PF-RATE-086` (legacy 86)

- **Meaning:** Too many followups for your domain in a short period
- **Trigger:** Short-window Followup-To target rate
- **Configuration:** `access.*_limits.max_short_followups / access_profile.limits.max_short_followups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:54` — `<file scope>()`

### `PF-RATE-087` (legacy 87)

- **Meaning:** Too many followups for your userid in a short period
- **Trigger:** Short-window Followup-To target rate
- **Configuration:** `access.*_limits.max_short_followups / access_profile.limits.max_short_followups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:66` — `<file scope>()`

### `PF-RATE-088` (legacy 88)

- **Meaning:** Too many followups for your IP
- **Trigger:** Long-window Followup-To target rate
- **Configuration:** `access.*_limits.max_total_followups / access_profile.limits.max_total_followups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:43` — `<file scope>()`

### `PF-RATE-089` (legacy 89)

- **Meaning:** Too many followups for your domain
- **Trigger:** Long-window Followup-To target rate
- **Configuration:** `access.*_limits.max_total_followups / access_profile.limits.max_total_followups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:55` — `<file scope>()`

### `PF-RATE-090` (legacy 90)

- **Meaning:** Too many followups for your userid
- **Trigger:** Long-window Followup-To target rate
- **Configuration:** `access.*_limits.max_total_followups / access_profile.limits.max_total_followups`
- **Source:**
  - `lib/Postfilter/Checks/Access.pm:67` — `<file scope>()`

### `PF-GROUP-095` (legacy 95)

- **Meaning:** Crossposting between text and binary groups is forbidden
- **Trigger:** Text/binary mixed crosspost invariant
- **Configuration:** `article_types.mixed_crosspost_policy`
- **Source:**
  - `lib/Postfilter/NG.pm:486` — `_run_pipeline()`

### `PF-BODY-096` (legacy 96)

- **Meaning:** Text article body exceeds the configured text limit
- **Trigger:** Text body size
- **Configuration:** `article_types.text.limits.max_body_size`
- **Source:**
  - `lib/Postfilter/Context.pm:614` — `size_rejection_code()`

### `PF-HEADER-097` (legacy 97)

- **Meaning:** Text article headers exceed the configured text limit
- **Trigger:** Text header size
- **Configuration:** `article_types.text.limits.max_header_size`
- **Source:**
  - `lib/Postfilter/Context.pm:615` — `size_rejection_code()`

### `PF-BODY-098` (legacy 98)

- **Meaning:** Text article total size exceeds the configured text limit
- **Trigger:** Text total size
- **Configuration:** `article_types.text.limits.max_total_size`
- **Source:**
  - `lib/Postfilter/Context.pm:616` — `size_rejection_code()`

### `PF-BODY-099` (legacy 99)

- **Meaning:** Binary article body exceeds the configured binary limit
- **Trigger:** Binary body size
- **Configuration:** `article_types.binary.limits.max_body_size`
- **Source:**
  - `lib/Postfilter/Context.pm:619` — `size_rejection_code()`

### `PF-HEADER-100` (legacy 100)

- **Meaning:** Binary article headers exceed the configured binary limit
- **Trigger:** Binary header size
- **Configuration:** `article_types.binary.limits.max_header_size`
- **Source:**
  - `lib/Postfilter/Context.pm:620` — `size_rejection_code()`

### `PF-BODY-101` (legacy 101)

- **Meaning:** Binary article total size exceeds the configured binary limit
- **Trigger:** Binary total size
- **Configuration:** `article_types.binary.limits.max_total_size`
- **Source:**
  - `lib/Postfilter/Context.pm:621` — `size_rejection_code()`

### `PF-BODY-102` (legacy 102)

- **Meaning:** Binary payload is forbidden by the selected article policy
- **Trigger:** Binary payload policy
- **Configuration:** `article_types.binary.content.allow_yenc / allow_uuencode`
- **Source:**
  - `lib/Postfilter/Checks/Content.pm:61` — `run_binary()`
  - `lib/Postfilter/Checks/Content.pm:68` — `run_binary()`

### `PF-AUTH-105` (legacy 105)

- **Meaning:** Unable to load per-group user database
- **Trigger:** Per-group user database load
- **Configuration:** `userdb.*`
- **Source:**
  - `lib/Postfilter/Checks/UserDB.pm:48` — `run()`
  - `lib/Postfilter/Checks/UserDB.pm:58` — `run()`

### `PF-AUTH-106` (legacy 106)

- **Meaning:** Sender is not authorized for this group
- **Trigger:** Per-group sender authorization
- **Configuration:** `userdb.*`
- **Source:**
  - `lib/Postfilter/Checks/UserDB.pm:61` — `run()`

### `PF-DB-107` (legacy 107)

- **Meaning:** Unable to store local Distribution state
- **Trigger:** Local Distribution state
- **Configuration:** `distributions / database.*`
- **Source:**
  - `lib/Postfilter/NG.pm:325` — `process_article()`

### `PF-MIME-109` (legacy 109)

- **Meaning:** multipart/mixed is forbidden in text groups
- **Trigger:** multipart/mixed text policy
- **Configuration:** `article_types.text.mime`
- **Source:**
  - `lib/Postfilter/Config.pm:1386` — `_apply_defaults()`

### `PF-MIME-110` (legacy 110)

- **Meaning:** MIME media type is forbidden in text groups
- **Trigger:** MIME media policy
- **Configuration:** `article_types.text.mime.allowed_media_types / forbidden_media_types`
- **Source:**
  - `lib/Postfilter/Checks/Attachments.pm:158` — `top_level_content_type_is_managed()`
  - `lib/Postfilter/Config.pm:1387` — `_apply_defaults()`

### `PF-MIME-111` (legacy 111)

- **Meaning:** MIME attachment metadata is forbidden in text groups
- **Trigger:** MIME attachment metadata
- **Configuration:** `article_types.text.mime`
- **Source:**
  - `lib/Postfilter/Config.pm:1388` — `_apply_defaults()`

### `PF-BODY-112` (legacy 112)

- **Meaning:** Probable Base64 attachment is forbidden in text groups
- **Trigger:** Probable Base64 attachment
- **Configuration:** `article_types.text.mime Base64 thresholds`
- **Source:**
  - `lib/Postfilter/Checks/Attachments.pm:689` — `_estimated_decoded_bytes()`
  - `lib/Postfilter/Checks/Attachments.pm:714` — `_detect_large_base64_block()`
  - `lib/Postfilter/Checks/Attachments.pm:726` — `_detect_large_base64_block()`
  - `lib/Postfilter/Checks/Attachments.pm:782` — `_detect_large_base64_block()`
  - `lib/Postfilter/Checks/Attachments.pm:793` — `_detect_large_base64_block()`
  - `lib/Postfilter/Config.pm:1389` — `_apply_defaults()`

### `PF-MIME-113` (legacy 113)

- **Meaning:** Malformed MIME structure in text article
- **Trigger:** Malformed MIME policy
- **Configuration:** `article_types.text.mime.on_malformed`
- **Source:**
  - `lib/Postfilter/Checks/Attachments.pm:959` — `_malformed_result()`
  - `lib/Postfilter/Config.pm:1390` — `_apply_defaults()`

### `PF-MIME-114` (legacy 114)

- **Meaning:** Unapproved multipart container is forbidden in text groups
- **Trigger:** Multipart container policy
- **Configuration:** `article_types.text.mime.allowed_multipart_types`
- **Source:**
  - `lib/Postfilter/Config.pm:1391` — `_apply_defaults()`

### `PF-GROUP-115` (legacy 115)

- **Meaning:** Invalid Newsgroups syntax
- **Trigger:** RFC 5536 Newsgroups syntax
- **Configuration:** `Newsgroups structural preflight`
- **Source:**
  - `lib/Postfilter/NG.pm:459` — `_run_pipeline()`

### `PF-GROUP-116` (legacy 116)

- **Meaning:** Invalid Followup-To syntax
- **Trigger:** RFC 5536 Followup-To syntax
- **Configuration:** `Followup-To structural preflight`
- **Source:**
  - `lib/Postfilter/NG.pm:461` — `_run_pipeline()`

### `PF-RFC-117` (legacy 117)

- **Meaning:** Article violates RFC 5536 syntax
- **Trigger:** RFC 5536 article/header syntax
- **Configuration:** `RFC 5536 invariant preflight`
- **Source:**
  - `lib/Postfilter/HeaderTransform.pm:218` — `_transform_injection_information()`
  - `lib/Postfilter/NG.pm:471` — `_run_pipeline()`

### `PF-RFC-118` (legacy 118)

- **Meaning:** Header transformation produced invalid RFC 5536 output
- **Trigger:** RFC 5536 transformation safety
- **Configuration:** `RFC 5536 post-transform invariant`
- **Source:**
  - `lib/Postfilter/HeaderTransform.pm:238` — `_transform_injection_information()`
  - `lib/Postfilter/NG.pm:606` — `_run_pipeline()`

