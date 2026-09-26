# Docs

- [adr/0001-stack-and-monorepo.md](adr/0001-stack-and-monorepo.md): the monorepo layout, the Flutter and FastAPI stack, delivery to the Pi, and pinned versions.
- [adr/0002-domain-and-api-conventions.md](adr/0002-domain-and-api-conventions.md): API conventions and the reasons for them (UUIDv7, UTC, problem+json, invite-only sign-up, custom fields, group_log).
- [adr/0003-client-codegen.md](adr/0003-client-codegen.md): client codegen (swagger_parser + retrofit + freezed, committed client), the auth/network layer, and the M4 wire-rule spike results.
- [api/contract.md](api/contract.md): **the API v1 contract**, and the single source of truth for implementers. It covers entities, auth, recurrence, custom fields, authorization, endpoints, schemas and the wheel.
- [api/rrule_cases.json](api/rrule_cases.json): shared recurrence fixtures, used by both pytest and `flutter test`.
- `../backend/openapi.json`: the generated OpenAPI snapshot. CI checks that it matches the code, and the Dart client is generated from it.
- `../deploy/README.md`: the Raspberry Pi runbook (setup, updates, backups, restore drill).

If code and `api/contract.md` disagree, fix one of them in the same PR, then re-export `openapi.json` and regenerate the client.
