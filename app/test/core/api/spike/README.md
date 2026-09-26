# Wire-rule spike

`test/core/api/wire_rules_test.dart` checks what the generated client actually puts on the wire
(contract section 12, ADR 0003). The M4 API has no list or enum query parameters and no dates, so the
spike uses a tiny FastAPI app with the shapes later milestones need:

- `GET /api/v1/spike/items?from=&status=&kinds=&due_before=&changed_after=&sort=&include_subcategories=`:
  a required `date`, repeated enum query parameters, an optional `date`, an `AwareDatetime`, a single
  enum and a bool with defaults (like `list_activities`' `sort` and `include_subcategories`);
- `PUT /api/v1/spike/items/{item_id}` with `SpikeWrite`: nullable `date`, instant and string fields
  and an enum with a default.

| File | What it is |
|---|---|
| `spike_api.py` | The FastAPI source. It uses the backend's `RequestModel` and `install_openapi`, so the schema has the same shape as `backend/openapi.json` (problem+json errors, no `HTTPValidationError`). |
| `spike_openapi.json` | Its OpenAPI schema. |
| `swagger_parser.yaml` | The same generator settings as `app/swagger_parser.yaml`, pointed at the spike schema. |
| `generated/` | swagger_parser output (committed, like `lib/core/api/generated/`). |

The real `MeUpdate` from `lib/core/api/generated/` is tested too, so rule 5 (explicit nulls) is
checked against the production client and not only the spike.

## Regenerating

```sh
# from backend/
PYTHONPATH=. uv run python ../app/test/core/api/spike/spike_api.py

# from app/
dart run swagger_parser -f test/core/api/spike/swagger_parser.yaml
dart format test/core/api/spike/generated
dart run build_runner build -d
```

Unlike `lib/core/api/generated/`, the spike output **is** passed through `dart format`: it lives
under `test/`, which the CI format check covers. Nothing checks the spike for drift; regenerate it
only when the generator settings change.
