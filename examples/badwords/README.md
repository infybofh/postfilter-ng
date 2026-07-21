# Badword scoring

Badword rules score subject and body independently.  Prefer an exact/contains rule
for literal text; regex is appropriate when variants are intended.  Scores are
compared with the limits in `[badwords]`.

## Example fragment

Copy and adapt `example.toml`; do not replace the main configuration blindly.
