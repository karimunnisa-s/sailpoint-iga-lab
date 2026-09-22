# SailPoint IGA Lab

A hands-on identity governance lab built on **SailPoint Human Fabric** (formerly Identity
Security Cloud / IdentityNow) for a fictional company, **Acme Corp**. Everything here is
built from synthetic data: no real people, customers or tenant details appear in this repo.

The goal is to practise the full lifecycle an IAM engineer owns — from an authoritative HR
feed through roles, certifications and automation — and to document the decisions and the
failures, not just the happy path.

> **Status:** in progress · started 22 September 2026 · by Karimunnisa-s

## The scenario

Acme Corp: 94 employees across 9 departments, with contractors, pre-hires, people on leave
and terminations. A flat-file HR extract is the authoritative source; a Finance application
is the first target system, complete with the messiness a real one has — accounts missing an
employee ID, a service account, an orphaned contractor account, and two people holding a
toxic combination of entitlements.

```
acme_hr_baseline.csv ──► Acme HR (authoritative source)
                              │
                              ▼
                      Identity profile ──► identities, lifecycle states
                              │
              ┌───────────────┼────────────────┐
              ▼               ▼                ▼
      birthright roles   job roles      access requests
              │               │                │
              └───────────────┴────────────────┘
                              ▼
                   Acme Finance (target source)
                              ▲
                  virtual appliance (GCP) for on-prem style sources
```

## What's here

| Folder | Contents |
|---|---|
| `docs/` | One write-up per milestone: goal, build, problems and fixes, lessons |
| `data/` | The synthetic Acme data sets (HR baseline, a week of JML changes, app accounts) |
| `transforms/` | Exported transform JSON (email, display name, lifecycle state) |
| `workflows/` | Exported workflow definitions (mover notification, leaver automation) |
| `scripts/` | Python against the SailPoint REST API |
| `screenshots/` | Sanitized screenshots |

Folders appear as each stage is completed, so the repo grows alongside the lab.

## Write-ups

1. [Deploying a virtual appliance on Google Cloud](docs/01-va-deployment-gcp(1).md) — why an
   ARM MacBook can't host it, and the pairing failure that took the longest to diagnose.
   *(Completed: appliance paired and Connected.)*

<!-- Add each write-up here as you finish it:
2. [Onboarding the authoritative HR source](docs/02-authoritative-hr-source.md)
3. [Transforms: email, display name and lifecycle state](docs/03-transforms.md)
4. [Correlation and the orphaned account hunt](docs/04-correlation-orphans.md)
5. [Role model: birthright and job-based access](docs/05-role-model.md)
6. [Testing joiner-mover-leaver end to end](docs/06-jml-test.md)
7. [Certification campaigns and separation of duties](docs/07-governance.md)
8. [Automating with workflows and the REST API](docs/08-automation.md)
-->

## The data

`data/acme_hr_baseline.csv` is deliberately awkward, because real HR data is:

- Two employees named John Smith — username generation has to handle collisions
- `O'Brien`, `José García`, `Van Der Berg`, `Mary-Jane Watson-Lee` — apostrophes, accents,
  spaces and hyphens all have to survive email generation
- A preferred name that should win over the legal first name
- Contractors, pre-hires with future start dates, people on leave, and terminations

`data/acme_hr_jml_update.csv` is the same population a week later: 2 joiners, 3 movers, a
leaver, a return from leave and a name change. `data/acme_jml_answer_key.csv` records what
*should* happen for each, so the lifecycle configuration can be tested rather than assumed.

## Skills demonstrated

Identity governance (IGA) · authoritative sources and identity profiles · attribute
transforms · lifecycle states · account correlation and orphan detection · RBAC role
modelling · access requests and approvals · access certification campaigns · separation of
duties · virtual appliance deployment (GCP) · REST API automation (Python) · workflow
automation

## A note on scope

This is a personal learning lab. All identity data is generated; configuration screenshots
are sanitized, and no tenant URL, credential or customer information appears anywhere in
this repository.
