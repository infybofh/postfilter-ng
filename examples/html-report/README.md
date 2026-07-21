# Static HTML report

The report is generated out of band by postfilterctl, never in the posting path.
`encrypted` protects published identities with a separate key.  Atomic rename
keeps the previous report visible if generation fails.

## Example fragment

Copy and adapt `example.toml`; do not replace the main configuration blindly.
