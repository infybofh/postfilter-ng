# RFC conformance guardrails

Postfilter-NG 2026.10.2 treats Netnews syntax as an injection invariant rather
than a site policy.  Local audit mode, trusted profiles and individual check
skips cannot authorize syntactically invalid article data.

The primary standards are RFC 5536 (Netnews Article Format) and RFC 5537
(Netnews Architecture and Protocols), with the RFC 5322 and MIME syntax they
normatively reference.

## Two-stage invariant

The posting pipeline validates syntax twice:

1. **Pre-transform (`PF-RFC-117`)** — after the article context is built but
   before trusted-profile bypasses and ordinary site policy.  Malformed input
   is rejected independently of audit mode.
2. **Post-transform (`PF-RFC-118`)** — after custom/header transformations and
   before an article can be accepted.  This is a defensive assertion that
   Postfilter itself did not manufacture malformed output from otherwise valid
   input or from an unsafe local configuration value.

The established `PF-GROUP-115` and `PF-GROUP-116` Newsgroups/Followup-To
syntax codes remain more specific and are evaluated before the generic RFC
preflight.

## Syntax covered directly

The validator checks the RFC 5536 forms visible to the nnrpd Perl hook,
including:

- general header field names, US-ASCII restriction, folding, control characters,
  non-empty physical header lines and the RFC 5322 998-character line limit;
- `Date`, `Expires` and `Injection-Date` date-time syntax (including the RFC
  5536 requirement to accept `GMT`);
- `From`, `Approved` and `Sender` mailbox syntax used by the posting path;
- RFC 5536-restricted `Message-ID` syntax and 250-octet limit;
- `Newsgroups` and `Followup-To`;
- `Path`, including common RFC 5536 path diagnostics;
- `Archive`, `Control`, `Distribution`, `References`, `Supersedes`,
  `User-Agent`, `Xref` and obsolete `Lines` syntax;
- `Injection-Info`, including MIME/RFC 2231-style parameter boundaries,
  uniqueness of standard parameters and the `x-` requirement for private
  attributes;
- `MIME-Version`, `Content-Type`, `Content-Transfer-Encoding`,
  `Content-Disposition` and `Content-Language` syntax;
- body NUL/bare-CR handling and the RFC 5322 998-character hard line limit,
  independently of optional site line-length policy.

The validator checks syntax, not registry membership or local policy.  For
example, whether a syntactically valid newsgroup exists remains a site/INN
policy decision.

## RFC 5537 transformation rules

Postfilter does not alter the article body and does not assign or rewrite
`Message-ID`.  A pre-existing `Injection-Date` is now always preserved.
`headers.delete_posting_date` refers only to the deprecated
`NNTP-Posting-Date` compatibility field.

The RFC 5537 recommendation not to alter other poster-supplied fields is a
SHOULD rather than a MUST.  Explicit Postfilter header transformation options
remain operator policy, but their result must still pass the post-transform RFC
invariant.

## Injection-Info regression

The 2026.10.1 serializer incorrectly generated:

```text
Injection-Info: news.example; logging-data="123";
```

The final semicolon begins a parameter and therefore cannot appear without a
following parameter.  2026.10.2 parses and serializes the field structurally;
valid values now round-trip without adding a trailing delimiter, including
quoted values containing semicolons or equals signs.

## Hook-level limitations

The nnrpd Perl filter API exposes the article headers as a hash.  By the time
Postfilter sees that structure, original field ordering and multiple instances
of an identically named field are not representable.  Therefore Postfilter
cannot independently prove RFC rules that require counting duplicate physical
header fields; INN's parser remains responsible for those invariants.

Likewise, the hook may see trace information that INN has already generated as
part of injection.  Postfilter validates such fields when present rather than
assuming the hash is the untouched proto-article described at the posting-agent
boundary in RFC 5537.

`policy.server_status = "disabled"` is an explicit administrator bypass of the
filter and therefore also bypasses these Postfilter checks.  Active filtering
modes enforce the invariants described above.

## Regression testing

`tests/30-rfc5536-compliance.t` contains both a broad valid article fixture and
negative cases.  It also runs a complex article through the real
`Postfilter::NG::_run_pipeline` path, then validates the transformed result.
Unsafe configured replacements (for example a malformed `Path`, `Sender`, or
custom header) must fail with `PF-RFC-118` rather than leave Postfilter.
