# Mixed text and binary reader

This example configures one reader that accepts ordinary text discussion groups
and binary transport groups at the same time.

The important design rule is that classification happens before filtering:

- every group matching `article_types.binary_group_patterns` is binary;
- an article whose groups are all binary uses the binary limits and skip list;
- an article whose groups are all non-binary uses the text limits;
- a crosspost containing at least one group from each world is rejected with
  `PF-GROUP-095`, even while the rest of the filter is in audit mode.

The supplied example keeps text articles strict at 32 KiB, permits 10 MiB yEnc
or uuencode articles in binary groups, skips text-oriented scans for binary
segments, and saves only selected text rejections.  Binary reject saving remains
disabled to avoid filling the spool accidentally.

Files in this directory:

- `example.toml` — complete focused fragment;
- `text-yenc-reject.post` — small yEnc payload in a text group;
- `binary-yenc-accept.post` — the same payload in a binary group;
- `mixed-crosspost-reject.post` — forbidden text/binary crosspost.
