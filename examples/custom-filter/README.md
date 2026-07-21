# Custom local Perl checks

Custom code runs after the built-in checks and receives the article context. A
missing or broken module follows `custom.on_error`. The sample module rejects a
single test subject and accepts all other articles.

## Example fragment

Copy `example.pm` and the matching settings from `example.toml`, then validate
and test the module before activation.
