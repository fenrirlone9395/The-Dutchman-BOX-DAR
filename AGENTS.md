# Repository guidance

Public-facing material must follow [docs/PUBLICATION.md](docs/PUBLICATION.md). Keep personal paths, device identifiers, private media and ownership-specific environment details out of documentation, examples, screenshots and commit/PR messages. Generalize hardware descriptions while preserving reproducible technical conditions and measurement limitations.

Before publication, review all changed and untracked files and run `python3 scripts/check-public-docs.py`. This complements manual review; it does not replace image/context inspection. Do not change runtime identifiers or audio behavior as part of documentation cleanup. Do not rewrite remote history without explicit authorization.
