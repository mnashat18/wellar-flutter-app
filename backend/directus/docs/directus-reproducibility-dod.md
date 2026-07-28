# Directus Reproducibility Definition Of Done

The Directus setup is documented enough to continue Phase 0 when all items below are true.

## Required

- [ ] `backend/directus/` folder structure exists.
- [ ] Live schema snapshot has been exported.
- [ ] Schema snapshot has been reviewed for secrets and private data.
- [ ] Collections, fields, and relations are represented by the snapshot or documented separately.
- [ ] Roles are exported or documented.
- [ ] Permissions and policies are exported or documented.
- [ ] Flows and operations are exported or documented.
- [ ] Flows and operations are manually checked for embedded secrets.
- [ ] Required environment variables are listed in `.env.example` with placeholders only.
- [ ] Extension deployment notes are documented.
- [ ] Required seed/reference data is identified.
- [ ] Any committed seed/reference data excludes private customer and user data.
- [ ] Unsafe files are ignored by `.gitignore`.
- [ ] No production `.env`, database dump, admin token, private key, customer data, user data, or upload is committed.

## Evidence To Keep

- Sanitized schema snapshot in `backend/directus/schema/`.
- Sanitized roles/permissions/policies in `backend/directus/permissions/`, if exported.
- Sanitized flows/operations in `backend/directus/flows/`, if exported.
- Placeholder env file in `backend/directus/env/.env.example`.
- Live instance notes in `backend/directus/docs/live-instance-notes.md`.
- Extension notes in `backend/directus/extensions/`.

## Not Required In This Step

- Flutter changes.
- Google login implementation.
- Billing fixes.
- Live Directus changes.
- Schema apply.
- Migrations.
- Production secret rotation.

