# Flutter Current Snapshot GitHub Backup Report

**Final status: VERIFIED BACKUP**

## Repository and baseline

- Verified `origin`: `https://github.com/mnashat18/wellar-flutter-app.git`.
- Before publication, local `HEAD`, local `main`, and remote `main` were `a13c161c586f9348619fa679922c5d5a5f8baaca`.
- Final GitHub check shows `origin/main` is still `a13c161c586f9348619fa679922c5d5a5f8baaca`.
- The GitHub target branch was absent immediately before publication.

## Independent filesystem preservation

- Copy location: `C:\Users\ABDULR~1\AppData\Local\Temp\wellar-flutter-snapshot-20261015-224414`.
- The copy includes `.git` metadata and a SHA-256 CSV manifest.
- The manifest covers 485 selected source, configuration, documentation, and other non-media files. Each copied file was hashed against its source during copy. A later comparison against the active repository found **0 mismatches**.
- Manifest SHA-256: `03e87c47ebe2c200e4216e5652d4f2f299080b18b1fa2c239eda571591aeffe0`.
- Excluded from this copy: reproducible build/cache directories (`build`, `.dart_tool`, `.idea`, `.gradle`), image/audio/video and compiled binary extensions, and files matching `.env`, private-key, credential, or secrets naming patterns. `.git` metadata is present in the copy but is not included in the 485-file source manifest.

## Published snapshot

- Branch: `backup/flutter-current-snapshot`.
- Commit: `337273d08daa55c998bc8f3e102b93d772163ba3`.
- GitHub push succeeded. Final `git ls-remote` confirmed the branch points to that commit.
- The commit is based on the existing main commit and contains 151 changed files: the 100 modified tracked files plus relevant untracked source, tests, configuration, backups, and audit documentation.
- Excluded from the candidate: `.claude` screenshots/device artifacts, build outputs/caches, common media and compiled binary extensions, private-key/`.env`-named files, and the earlier incomplete recovery report. An anchored scan for common private-key and API-token forms returned no matching files; this is a targeted scan, not a guarantee against every possible secret format.

## Verification and caveats

- The active source-file SHA-256 comparison against the independent copy reported **485 files checked, 0 mismatches**.
- The active checkout remains on `main`; its source files were not edited by reconstruction or publication. The requested report is a new documentation file in the active repository.
- During execution, an initial push from the isolated clone used its automatically configured local-path `origin`. It created a local branch ref in the active repository at the same snapshot commit. It did not change `main` or active source files. The isolated clone's `origin` was then corrected to the verified GitHub URL, and the branch was pushed and verified there. The extra local ref is `backup/flutter-current-snapshot`.
- This is a **current-state snapshot**. It intentionally mixes pre-existing work with Wellar AI V2 Stage 5.1 changes; their individual provenance remains unresolved. It must not be represented as the original pre-V2 state.
