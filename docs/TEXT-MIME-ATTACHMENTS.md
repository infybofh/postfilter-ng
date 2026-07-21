# Strict MIME and Base64 policy for text groups

## Scope

The text attachment stage detects binary payloads carried through MIME or raw
Base64 in addition to yEnc and uuencode. It covers `multipart/mixed`,
`application/octet-stream`, `Content-Disposition: attachment`, filename
metadata and large unlabelled Base64 blocks.

Article classification remains group-based. MIME and body content do not change
a text article into a binary article.

## Pipeline position

1. `Newsgroups` selects text, binary, or forbidden mixed classification.
2. Structural size/group/header checks run.
3. `Postfilter::Checks::Attachments` inspects MIME and Base64 policy.
4. Historical yEnc and uuencode checks run.
5. Reputation, rules, rate limits and transformations continue normally.

The earlier Content-Type check defers MIME containers and managed media types to
the attachment stage so operators receive precise codes 109–114 rather than the
generic historical Content-Type code 5.

## What is rejected by default in text articles

- `multipart/mixed`;
- unlisted multipart containers such as `multipart/encrypted`;
- `Content-Disposition: attachment`;
- `inline; filename=...` and `Content-Type; name=...` attachment metadata;
- `application/*`, `image/*`, `audio/*`, `video/*`, `font/*`, `model/*` and
  `message/rfc822`, except explicit bounded cryptographic types;
- malformed multipart boundaries/part headers;
- MIME structures exceeding depth or part-count limits;
- long unlabelled Base64 runs meeting both configured thresholds.

## PGP, GnuPG and certificate handling

PGP signatures, keys and certificates contain Base64-looking text. The default
policy applies three independent controls:

1. `multipart/signed` is an allowed container, but every child part is still
   recursively inspected.
2. Common signature/key/certificate media types are explicitly allowed only up
   to `allowed_media_max_decoded_bytes`.
3. Configured complete ASCII-armoured blocks such as `PGP SIGNATURE` and
   `CERTIFICATE` are removed from the heuristic scan copy while the complete
   block remains below `armored_block_max_bytes`.

The armour scanner processes physical lines in one forward pass. Unterminated
blocks and blocks larger than `armored_block_max_bytes` remain in the scan copy
and are evaluated by the Base64 heuristic. The setting controls the maximum
size of the armour exception; it does not set the maximum article size.

A large payload labelled `application/pgp-signature` is also subject to
`allowed_media_max_decoded_bytes`.

## Base64 heuristic

A line is considered Base64-looking when, after removing horizontal spaces, it
contains only the standard or URL-safe Base64 alphabet and optional final
padding.  A run is rejected only when both conditions hold:

- at least `base64_min_contiguous_lines` consecutive qualifying lines;
- estimated decoded data at least `base64_min_decoded_bytes`.

A separate `base64_single_line_min_decoded_bytes` threshold catches one very
long encoded line, which otherwise could evade the contiguous-line requirement.
Set it to zero only when that evasion is acceptable locally.

The line-length bounds reject neither prose nor tiny examples.  A shorter final
line is permitted because conventional encoders wrap fixed-width lines and end
with a shorter remainder.

### Avoiding false positives

- quoted reply lines beginning with `>` are ignored by default;
- short examples remain below the line/byte thresholds;
- authorised armoured cryptographic blocks are removed first;
- indented examples can be ignored, but the default keeps them inspectable
  because an attacker can trivially indent an attachment.

For programming or cryptography groups, raise the decoded-byte threshold before
reducing line count.  Always replay representative historical articles before
enabling enforcement.

## Media-type patterns

`allowed_media_types`, `forbidden_media_types`, and
`allowed_multipart_types` use MIME globs, not regular expressions:

- `application/*` matches every application subtype;
- `application/pgp-signature` matches that exact type;
- `?` matches one character;
- matching is anchored and case-insensitive.

Allowed media are evaluated before forbidden media. A bounded
`application/pgp-signature` can therefore pass while generic `application/*`
remains forbidden.

## Failure policy

`on_malformed = "reject"` is the strict default.  It maps malformed MIME to
`PF-MIME-113`.

`on_malformed = "accept"` logs `news.err`, records a context note, and skips only
the malformed MIME structure.  It does **not** skip size, yEnc, uuencode,
banlist, rate-limit or other checks.

## Binary profile

The same table exists under `[article_types.binary.mime]`, but `enabled = false`
by default.  Binary groups are expected to carry MIME attachments and Base64.
A newsmaster can enable a separate bounded binary policy without weakening the
text profile.

## Diagnostic saving

The supplied text save selector includes codes 109–114 and the historical yEnc
and uuencode codes.  Rejected diagnostic copies therefore go below the text
subdirectory without mixing with large binary-world rejects.  Change the
selector or use `mode = "none"` when storage is limited.
