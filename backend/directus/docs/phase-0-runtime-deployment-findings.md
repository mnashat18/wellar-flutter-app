# Phase 0 Runtime Deployment Findings

## Scope

This document summarizes read-only Phase 0 findings for runtime configuration, environment separation, deployment documentation, mobile platform configuration, CI/CD readiness, release readiness, and logging/privacy posture.

This is audit evidence, not proof of Enterprise SaaS readiness. It does not certify production security, reproducibility, tenant isolation, compliance, platform release readiness, or operational maturity.

Flutter/app findings were inspected from the current dirty working tree. Revalidate these findings after the Flutter/app changes are finalized, reviewed, and either committed or discarded.

No live Directus instance was contacted for this step. No Flutter, Android, iOS, pubspec, runtime configuration, schema, permissions, flows, operations, tests, formatters, commits, or pushes are part of this documentation step.

## Evidence Reviewed

Read-only inspection covered configuration and deployment-related files and paths, including:

- `lib/config/app_config.dart`
- `lib/services/directus_client.dart`
- `lib/services/scan_service.dart`
- `lib/services/report_service.dart`
- `backend/directus/`
- `backend/directus/env/.env.example`
- `backend/directus/docs/`
- `.gitignore`
- `pubspec.yaml`
- Android build and manifest configuration
- iOS project, plist, and xcconfig configuration
- Firebase mobile configuration file presence
- CI/CD and release pipeline file presence

Real URLs, API keys, tokens, client IDs, Firebase values, and private configuration values are intentionally omitted from this document.

## Runtime Configuration Findings

- The Flutter app's Directus/base API URL is defined in `lib/config/app_config.dart`.
- Runtime configuration uses `String.fromEnvironment` values intended to be supplied through `--dart-define`.
- Runtime configuration keys observed include:
  - `DIRECTUS_URL`
  - `DIRECTUS_FALLBACK_URL`
  - `INVITE_BASE_URL`
  - `GOOGLE_MOBILE_EXCHANGE_BASE_URL`
  - `GOOGLE_MOBILE_CLIENT_ID`
  - `ENABLE_PUSH_SUBSCRIPTION_WRITES`
- `lib/services/directus_client.dart` builds Directus base URL behavior from `AppConfig.directusBaseUrl` and `AppConfig.directusFallbackUrl`.
- `lib/services/scan_service.dart` contains a hard-coded AI server process endpoint.
- `lib/services/report_service.dart` appends an access token to report/file URLs.

Runtime configuration is partly parameterized, but some defaults and service endpoints still need review before production-grade environment separation can be claimed.

## Environment Separation Findings

- Partial environment separation exists through `--dart-define` and `String.fromEnvironment`.
- No clear committed dev/staging/prod Flutter flavor structure was found.
- Android `productFlavors` were not found.
- Separate iOS staging/prod schemes were not found.
- Default app configuration values appear to point at real or live-looking endpoints.
- No Flutter `.env.example` equivalent was found for app runtime `--dart-define` values.

The current evidence does not show a complete environment matrix for local development, staging, production, app store release, or emergency rollback scenarios.

## Directus Deployment Documentation Findings

- `backend/directus/env/.env.example` exists.
- The Directus environment example appears safe for commit because it uses placeholders only.
- Directus documentation exists under `backend/directus/`.
- Existing Directus documentation covers:
  - Easypanel deployment context.
  - Export and snapshot workflow.
  - Placeholder environment expectations.
  - Extension notes.
  - Commit safety guidance.
- Live instance notes are still incomplete for operational details such as:
  - Easypanel service name.
  - Directus container image or version source.
  - Database engine version.
  - Storage adapter.
  - Mail provider.
  - Auth providers.
  - CORS origins.
  - Backup location.
  - Export operator.
  - Extension deployment path.

The Directus documentation is useful audit scaffolding, but it is not yet a full deployment runbook or reproducibility guide.

## Firebase / Mobile Platform Configuration Findings

- `android/app/google-services.json` exists.
- `ios/Runner/GoogleService-Info.plist` exists.
- These files contain Firebase/Google mobile configuration keys.
- Firebase mobile API keys are usually not private secrets by themselves, but they still require:
  - Environment and project separation.
  - Platform restrictions.
  - API restrictions where applicable.
  - Release governance.
  - Clear ownership of Firebase projects per environment.

No real Firebase values are reproduced in this document.

## CI/CD Findings

- No `.github` workflow directory was found.
- No `.gitlab` pipeline directory was found.
- No `fastlane` directory was found.
- No Codemagic, Bitrise, AppCenter, Azure Pipelines, Jenkins, or similar pipeline file was found during inspection.

The repository does not currently show committed CI/CD automation for repeatable builds, tests, signing, artifact generation, deployment, or release promotion.

## Android / iOS Release Readiness Findings

- Android release configuration appears to use debug signing.
- Android `applicationId` appears example-style and should be reviewed before release.
- iOS bundle identifiers appear example-style and should be reviewed before release.
- iOS uses automatic signing.
- No Android flavor separation was found.
- No iOS staging/prod scheme separation was found.

The current mobile platform configuration is not enough evidence for production release readiness.

## Logging / Privacy Findings

- Several services log request, session, workspace, role, and operational details.
- Production logging/privacy review is needed before Enterprise SaaS readiness can be claimed.
- Logging review should confirm:
  - No access tokens or refresh tokens are logged.
  - No personally sensitive fields are logged unnecessarily.
  - No health, scan, billing, auth, or tenant-sensitive payloads are logged in production.
  - Debug logs are gated, reduced, or disabled in release builds.
  - Error reporting and observability tools redact sensitive values.

No log values or private payloads are reproduced in this document.

## Enterprise SaaS Gaps

- Environment separation is incomplete or undocumented across Flutter, Android, iOS, Firebase, Directus, and external services.
- Secret management is not fully documented for runtime injection, rotation, emergency replacement, ownership, and audit trails.
- Reproducible deployment is incomplete without a complete Directus runbook, image/version pinning, extension build/deploy workflow, backup/restore verification, and migration policy.
- CI/CD readiness is incomplete because no committed pipeline automation was found.
- Production/staging parity is not documented.
- Android and iOS release configuration needs app identity, signing, scheme/flavor, Firebase project, and release governance review.
- Hard-coded or default real-looking endpoints need replacement with explicit environment-controlled configuration.
- Report/file URL token handling needs a security review for token exposure in logs, browser history, sharing, crash reports, and network traces.
- AI server endpoint configuration needs environment separation and service authentication review.
- Production logging/privacy controls are not yet proven.

## What This Proves

- The app has a centralized Flutter runtime configuration file for Directus and related runtime values.
- The Directus client reads base URL behavior from app configuration.
- Directus environment placeholders exist and are separated from real production secrets.
- Directus deployment documentation has started and includes export, placeholder, extension, and commit-safety guidance.
- Firebase mobile configuration files are present for Android and iOS.
- The current repository state does not show committed flavor, scheme, or pipeline automation evidence.

## What This Does Not Prove

- It does not prove Enterprise SaaS readiness.
- It does not prove secure production secret management.
- It does not prove production/staging/dev isolation.
- It does not prove reproducible deployment or disaster recovery readiness.
- It does not prove Android or iOS app store release readiness.
- It does not prove Firebase project separation, API restrictions, or key governance.
- It does not prove CI/CD reliability or release promotion controls.
- It does not prove runtime logs are safe for production.
- It does not prove the current dirty Flutter working tree reflects final intended behavior.

## Required Follow-Up Work

- Revalidate Flutter/app runtime configuration after the dirty working tree is finalized.
- Create an explicit environment matrix for local, development, staging, and production.
- Add a Flutter runtime configuration example for required `--dart-define` values using placeholders only.
- Remove real-looking defaults from production-sensitive app config, or require explicit environment values for release builds.
- Move hard-coded external service endpoints to environment-controlled configuration.
- Review report/file URL token handling and avoid exposing access tokens where safer alternatives exist.
- Document Directus production secret injection, rotation, ownership, and emergency replacement procedures.
- Complete Directus live instance notes for service, database, storage, mail, auth, CORS, backup, export, and extension details.
- Document Firebase project separation, platform restrictions, and API restrictions for each environment.
- Add Android flavors and iOS schemes if separate environment builds are required.
- Replace debug Android release signing with production signing configuration managed outside git.
- Review Android application ID and iOS bundle identifiers before release.
- Add CI/CD automation for checks, builds, signing, artifact handling, deployment, and release promotion.
- Perform a production logging/privacy review and define redaction rules.

## Commit Safety Notes

- Commit documentation only for this step.
- Do not commit production `.env` files.
- Do not commit real Directus secrets, admin tokens, OAuth secrets, SMTP secrets, storage credentials, private keys, database dumps, uploaded files, customer data, user data, auth data, billing data, or health data.
- Do not print or commit real URLs, API keys, tokens, client IDs, Firebase values, or private runtime configuration values in findings documents.
- Do not stage Flutter, Android, iOS, `pubspec.yaml`, or runtime configuration changes as part of this documentation step.
- Treat this document as audit evidence and planning input, not as deployment approval.
