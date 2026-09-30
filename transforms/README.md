
# Transforms

The four transforms behind the Acme HR identity profile, as JSON. This tenant has
no UI for creating transforms, so these were created through the REST API:

```
POST /v3/transforms
Content-Type: application/json
```

Keeping them here means the identity profile can be rebuilt from definition
rather than from memory — which mattered, because the source had to be rebuilt
once and every transform referencing it had to be deleted first.

| File | Identity attribute | What it does |
|---|---|---|
| `Karima_Acme_Username.json` | SailPoint User Name | Prefixes the employee ID → `karima.E1001` |
| `Karima_Acme_Email.json` | Email | `first.last@acme.example`, lowercased, accents folded, non-letters stripped |
| `Karima_Acme_Display_Name.json` | Display Name | Preferred name if present, otherwise first name, plus last name |
| `Karima_Acme_Lifecycle_State.json` | Lifecycle State | Maps the HR `status` column to an ISC lifecycle state |

## Notes on each

**Username** is prefixed deliberately. Identity usernames must be unique across
the whole tenant, not just within an identity profile. In a shared training
tenant another profile had already claimed the plain employee IDs, and 70 of 94
identities failed to process with "Non-unique username" until the prefix was
added. See `docs/02-hr-source-and-correlation.md`.

**Email** chains four transforms: `lower` → `concat` → `replace` →
`decomposeDiacriticalMarks`. The last two matter for real name data —
`José García` becomes `jose.garcia@acme.example`, and `Mary-Jane Watson-Lee`
loses the hyphens rather than producing an invalid address.

**Display Name** uses `firstValid` so someone with a preferred name gets it and
everyone else falls back to their legal first name. `Elizabeth Van Der Berg`
displays as `Liz Van Der Berg` while her email still uses her legal name.

**Lifecycle State** is a lookup with an explicit default of `inactive`. An
unrecognised status fails closed — someone with a status nobody anticipated ends
up deactivated rather than active. Verified against the source data: 84 active,
4 inactive, 3 prehire, 3 loa, totalling all 94 identities.

## Rebuilding them

Each file is the exact request body. `sourceName` must match the source's display
name character for character; if the source is renamed, every transform silently
returns null rather than erroring.
