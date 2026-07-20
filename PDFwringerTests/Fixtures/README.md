# External PDF Test Corpus

The slow integration lane uses a curated set of 36 real-world PDFs covering annotations, forms, unusual fonts and colors, scans, permission restrictions, and malformed inputs.

The PDFs are intentionally gitignored. Their original source and redistribution-license records are incomplete, so they must not be committed or published until that provenance is established. Keep sensitive or private documents out of this directory.

## Setup and validation

Restore the maintainer-controlled corpus into the category paths recorded in `SHA256SUMS`, then validate it before testing:

```bash
make verify-fixtures
make test-corpus
```

`make verify-fixtures` requires exactly the recorded 36 PDFs and verifies every byte against `SHA256SUMS`. Both `make test` and `make test-corpus` run this check first and fail when the corpus is absent, incomplete, changed, or has extra PDFs. `make test-fast` is fully generated and does not need the corpus.

## Updating the corpus

Do not drop arbitrary PDFs into this directory. A corpus change must update all three records together:

1. Document the upstream source and redistribution license.
2. Add the expected properties to `FixtureManifest.swift`.
3. Regenerate `SHA256SUMS` and run `make test-corpus`.

Malformed and fuzz-regression files may be hostile. The Make test runner is not sandboxed, so run this lane only in an isolated development environment.
