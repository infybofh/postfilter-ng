# Legacy and symbolic error codes

| Legacy | Symbolic | Default message |
|---:|---|---|
| 0 | `PF-INTERNAL-000` | Message successfully sent |
| 1 | `PF-HEADER-001` | Control messages are forbidden |
| 2 | `PF-GROUP-002` | Forbidden crosspost |
| 3 | `PF-HEADER-003` | You cannot approve messages |
| 4 | `PF-GROUP-004` | Invalid Distribution header |
| 5 | `PF-MIME-005` | Invalid Content-Type |
| 6 | `PF-GROUP-006` | Too many groups in Newsgroups |
| 7 | `PF-GROUP-007` | Too many groups in Followup-To |
| 8 | `PF-GROUP-008` | Missing Followup-To header |
| 9 | `PF-BODY-009` | The body is too large |
| 10 | `PF-GROUP-010` | Difference between crossposts and followups is too large |
| 11 | `PF-HEADER-011` | Re: without References |
| 12 | `PF-BODY-012` | Line too long |
| 13 | `PF-BODY-013` | Too many quoted lines |
| 14 | `PF-BODY-014` | Too many blank lines |
| 15 | `PF-BODY-015` | Too many empty lines |
| 16 | `PF-BODY-016` | HTML content is forbidden |
| 17 | `PF-GROUP-017` | Nonexistent group |
| 18 | `PF-GROUP-018` | Nonexistent group in Followup-To |
| 19 | `PF-DATE-019` | Date is too far in the future |
| 20 | `PF-HEADER-020` | Invalid Path |
| 21 | `PF-HEADER-021` | A header is too long |
| 22 | `PF-HEADER-022` | Mail headers are forbidden |
| 23 | `PF-HEADER-023` | Headers are too large |
| 24 | `PF-HEADER-024` | Invalid In-Reply-To |
| 25 | `PF-GROUP-025` | Too many hierarchies |
| 26 | `PF-GROUP-026` | Too many hierarchies in Followup-To |
| 27 | `PF-CONFIG-027` | Syntax error in badwords configuration |
| 28 | `PF-RULE-028` | Badword in Subject |
| 29 | `PF-RULE-029` | Badword in body |
| 30 | `PF-RATE-030` | Multipost |
| 31 | `PF-RATE-031` | Your IP has sent too many articles |
| 32 | `PF-RATE-032` | Your domain has sent too many articles |
| 33 | `PF-RATE-033` | Your userid has sent too many articles |
| 34 | `PF-RULE-034` | Banlist |
| 35 | `PF-CONFIG-035` | Syntax error in banlist configuration |
| 36 | `PF-DB-036` | Database connection error |
| 37 | `PF-GROUP-037` | Unable to load active file |
| 38 | `PF-CONFIG-038` | Unable to load badwords configuration |
| 39 | `PF-CONFIG-039` | Unable to load banlist configuration |
| 40 | `PF-DB-040` | Unable to open persistent storage |
| 41 | `PF-SAVE-041` | Unable to save article |
| 42 | `PF-CONFIG-042` | Unable to run innconfval |
| 43 | `PF-CONFIG-043` | Unable to load main configuration |
| 44 | `PF-DB-044` | Unable to write audit event |
| 45 | `PF-DB-045` | Database expiry error |
| 46 | `PF-DB-046` | Database spool error |
| 47 | `PF-POLICY-047` | Default action set to rejection |
| 48 | `PF-POLICY-048` | Server closed for posting |
| 49 | `PF-RULE-049` | Excessive score in banlist |
| 50 | `PF-TOR-050` | TOR is forbidden |
| 51 | `PF-HEADER-051` | Supersedes, Replaces and Cancel are forbidden |
| 52 | `PF-BODY-052` | UUEncoded binaries are forbidden |
| 53 | `PF-HEADER-053` | Forged system header |
| 54 | `PF-GROUP-054` | Permanently closed group |
| 55 | `PF-INTERNAL-055` | Unable to load internal module |
| 56 | `PF-RBL-056` | Forbidden due to DNSBL listing |
| 57 | `PF-BODY-057` | Message too big |
| 58 | `PF-DATE-058` | Message too old |
| 59 | `PF-CONFIG-059` | Unable to read public suffix data |
| 60 | `PF-URIBL-060` | Banned domain in body (SURBL) |
| 61 | `PF-URIBL-061` | Banned domain in body (URIBL) |
| 62 | `PF-BODY-062` | yEnc contents are forbidden |
| 63 | `PF-RULE-063` | Message rejected by a custom rule |
| 64 | `PF-RATE-064` | Too many errors for your IP |
| 65 | `PF-RATE-065` | Too many errors for your domain |
| 66 | `PF-RATE-066` | Too many errors for your userid |
| 67 | `PF-RATE-067` | Too many errors for your IP in a short period |
| 68 | `PF-RATE-068` | Too many errors for your domain in a short period |
| 69 | `PF-RATE-069` | Too many errors for your userid in a short period |
| 70 | `PF-RATE-070` | Too many messages for your IP in a short period |
| 71 | `PF-RATE-071` | Too many messages for your domain in a short period |
| 72 | `PF-RATE-072` | Too many messages for your userid in a short period |
| 73 | `PF-RATE-073` | Too many bytes for your IP in a short period |
| 74 | `PF-RATE-074` | Too many bytes for your domain in a short period |
| 75 | `PF-RATE-075` | Too many bytes for your userid in a short period |
| 76 | `PF-RATE-076` | Too many bytes for your IP |
| 77 | `PF-RATE-077` | Too many bytes for your domain |
| 78 | `PF-RATE-078` | Too many bytes for your userid |
| 79 | `PF-RATE-079` | Too many newsgroups for your IP in a short period |
| 80 | `PF-RATE-080` | Too many newsgroups for your domain in a short period |
| 81 | `PF-RATE-081` | Too many newsgroups for your userid in a short period |
| 82 | `PF-RATE-082` | Too many newsgroups for your IP |
| 83 | `PF-RATE-083` | Too many newsgroups for your domain |
| 84 | `PF-RATE-084` | Too many newsgroups for your userid |
| 85 | `PF-RATE-085` | Too many followups for your IP in a short period |
| 86 | `PF-RATE-086` | Too many followups for your domain in a short period |
| 87 | `PF-RATE-087` | Too many followups for your userid in a short period |
| 88 | `PF-RATE-088` | Too many followups for your IP |
| 89 | `PF-RATE-089` | Too many followups for your domain |
| 90 | `PF-RATE-090` | Too many followups for your userid |
| 91 | `PF-RULE-091` | Article rejected by sender request |
| 92 | `PF-CONFIG-092` | Syntax error in main configuration |
| 93 | `PF-CONFIG-093` | Syntax error in access configuration |
| 94 | `PF-CONFIG-094` | Syntax error in rules configuration |
| 95 | `PF-GROUP-095` | Crosspost between text and binary groups is forbidden |
| 96 | `PF-BODY-096` | Text article body exceeds the configured text limit |
| 97 | `PF-HEADER-097` | Text article headers exceed the configured text limit |
| 98 | `PF-BODY-098` | Text article total size exceeds the configured text limit |
| 99 | `PF-BODY-099` | Binary article body exceeds the configured binary limit |
| 100 | `PF-HEADER-100` | Binary article headers exceed the configured binary limit |
| 101 | `PF-BODY-101` | Binary article total size exceeds the configured binary limit |
| 102 | `PF-BODY-102` | Binary payload is forbidden by the selected article-type policy |
| 103 | `PF-POLICY-103` | Unable to determine a valid article-type policy |
| 104 | `PF-HEADER-104` | Forbidden or invalid character in header |
| 105 | `PF-AUTH-105` | Unable to load per-group user database |
| 106 | `PF-AUTH-106` | Sender is not authorized for this group |
| 107 | `PF-DB-107` | Unable to store local Distribution state |
| 108 | `PF-GROUP-108` | Invalid Distribution value |
| 109 | `PF-MIME-109` | multipart/mixed is forbidden in text groups |
| 110 | `PF-MIME-110` | MIME media type is forbidden in text groups |
| 111 | `PF-MIME-111` | MIME attachment metadata is forbidden in text groups |
| 112 | `PF-BODY-112` | Probable Base64 attachment is forbidden in text groups |
| 113 | `PF-MIME-113` | Malformed MIME structure in text article |
| 114 | `PF-MIME-114` | Unapproved multipart container is forbidden in text groups |
| 115 | `PF-GROUP-115` | Invalid Newsgroups syntax |
| 116 | `PF-GROUP-116` | Invalid Followup-To syntax |

## Article-type codes

Codes 95–103 extend the historical numeric range. Codes 96–101 distinguish
text and binary size failures,
so a newsmaster can select diagnostic saving and statistics independently.
Code 95 is enforced in audit mode and blocks direct text/binary mixed crossposts.
Code 102 is used when the binary profile explicitly disables yEnc or uuencode;
text-world violations retain compatibility codes 62 and 52.  Code 103
is the defensive fallback used when no valid article-type limit table can be
resolved.


## MIME and Base64 codes

Codes 109–114 are profile-aware text-world attachment failures.  They do not
classify an article as binary; classification remains based exclusively on the
configured `Newsgroups` globs.

- **109** is reserved for `multipart/mixed`, the usual email-style attachment
  container.
- **110** covers forbidden leaf media types and an explicitly allowed
  cryptographic part that exceeds its independent decoded-size ceiling.
- **111** covers `Content-Disposition: attachment`, filename-bearing inline
  parts and `Content-Type; name=` attachment metadata.
- **112** is the bounded heuristic for long unlabelled Base64 runs.  It requires
  both configured line and decoded-byte thresholds.
- **113** covers malformed multipart syntax when `on_malformed = "reject"`.
- **114** covers multipart subtypes not listed in `allowed_multipart_types`.

PGP/GnuPG signatures, public keys and certificate blocks are not automatically
accepted merely because they contain Base64.  They are accepted only through
explicit media/armour allow-lists and size ceilings.
