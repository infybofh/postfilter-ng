# Audit rollout

This fragment records ordinary rejections as `would_reject` while returning
success to the poster. `policy.server_status = "closed"` continues to close
posting.

## Example fragment

Copy the required settings from `example.toml` into a late `conf.d/` file and
validate the complete configuration.
