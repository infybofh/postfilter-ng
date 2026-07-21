# Per-group sender database

When enabled, a file named after a group contains one normalised mailbox per line.
Group names are validated before path construction.  A group without a file has
no additional sender restriction; a present unreadable file is an error.

## Example fragment

Copy and adapt `example.toml`; do not replace the main configuration blindly.
