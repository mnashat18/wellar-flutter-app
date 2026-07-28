# Directus Secret Rotation Checklist

Last updated: 2026-06-16

This checklist is manual. Do not rotate production secrets from automation
without a separate approved deployment plan.

## Exposed Secret

The fresh raw operations export contained a hardcoded `X-Directus-Secret` header
value in the push notification flow. The value has been redacted in the
commit-safe export, but the live secret must still be rotated manually.

## Manual Rotation Steps

1. In Directus Admin, open Flows.
2. Locate the flow named `Send Push When Scan Request Created`.
3. Open the request operation that sends to the push notification service.
4. Confirm the header name is `X-Directus-Secret`.
5. Do not copy the current value into chat, docs, tickets, or commits.
6. Locate the matching secret in the Cloud Run / push notification service
   configuration.
7. Generate a new high-entropy secret using an approved secret manager or local
   secure generator.
8. Update the Cloud Run / push notification service configuration first.
9. Deploy or restart the push service if required by its platform.
10. Update the Directus flow operation header to the new secret.
11. Trigger a safe test scan-request notification in a non-customer test path.
12. Confirm the push service accepts the request and rejects the old secret.
13. Re-export Directus flows and operations.
14. Regenerate commit-safe exports.
15. Run the secret scan checklist.
16. Confirm the new export contains only redacted placeholders, not the raw
    secret value.

## Rollback Notes

If notification dispatch fails after rotation, revert both sides to the previous
secret only through the approved secret manager or platform console. Do not
write either secret into the repo.

