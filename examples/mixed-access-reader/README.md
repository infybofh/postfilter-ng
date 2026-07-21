# Mixed public and authenticated reader

The mixed profile treats an empty user or an explicitly configured synthetic ID
as public; every other non-empty ID is authenticated.  Public users are measured
by IP/domain and authenticated users by ID.

## Example fragment

Copy and adapt `example.toml`; do not replace the main configuration blindly.
