# Strict MIME attachments in text groups

Copy the TOML fragment to a late `conf.d/` file, run
`postfilterctl check-config`, and replay representative articles before enabling
enforcement.

Files:

- `example.toml` — complete commented policy fragment;
- `accepted-pgp-signature.post` — inline ASCII-armoured signature;
- `accepted-pgp-mime.post` — accepted `multipart/signed` article;
- `rejected-multipart-mixed.post` — email-style attachment returning
  `PF-MIME-109`;
- `rejected-base64.post` — unlabelled Base64 returning `PF-BODY-112`.

Suggested checks:

```sh
postfilterctl test-article accepted-pgp-signature.post
postfilterctl test-article accepted-pgp-mime.post
postfilterctl test-article rejected-multipart-mixed.post
postfilterctl test-article rejected-base64.post
```

The Base64 fixture contains synthetic test data.
