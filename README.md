# SailPoint IGA Lab

A hands-on identity governance lab built on **SailPoint Human Fabric** (formerly
Identity Security Cloud / IdentityNow) for a fictional company, **Acme Corp**.
Everything here is built from synthetic data: no real people, customers or tenant
details appear in this repo.

The goal is to practise the full lifecycle an IAM engineer owns — from an
authoritative HR feed through roles, certifications and automation — and to
document the decisions and the failures, not just the happy path.

> **Status:** in progress · started 22 September 2026 · by Karimunnisa-s

## Start here

**[Building the HR authoritative source — and six failures on the way](docs/02-hr-source-and-correlation.md)**

An HR source that aggregated 94 accounts cleanly and produced 48 identities, with
no error anywhere. Tracing that back to an account identifier that wasn't unique,
past four other failures on the way. It's the write-up that best shows how I work
when something is wrong and nothing is saying so.

## The scenario

Acme Corp: 94 employees across 9 departments, with contractors, pre-hires, people
on leave and terminations. A flat-file HR extract is the authoritative source; a
Microsoft Entra directory and a Finance application are the target systems,
complete with the messiness a real environment has — two employees who share a
name, accounts missing an employee ID, a service account nobody owns, an orphaned
contractor account, and a toxic combination of entitlements.

## What's here

| Folder | Contents |
|---|---|
| `docs/` | One write-up per milestone: goal, build, problems and fixes, lessons |
| `data/` | The synthetic Acme data sets (HR baseline, a week of JML changes, the expected outcomes, app accounts) |
| `transforms/` | Transform definitions as JSON — email, display name, username, lifecycle state |
| `scripts/` | Read-only integrity checks against the SailPoint REST API (PowerShell) |
| `screenshots/` | Sanitized screenshots |

## Write-ups

1. **[Deploying a virtual appliance on Google Cloud](docs/01-va-deployment-gcp.md)** —
   why an ARM MacBook can't host the appliance image, and the pairing failure
   that took longest to diagnose. *Appliance paired and Connected.*

2. **[Building the HR authoritative source — and six failures on the way](docs/02-hr-source-and-correlation.md)** —
   94 accounts, 48 identities, no errors: an account name mapped to a first name,
   so everyone called John became one person. Plus a shared appliance cluster
   consuming messages it had no key for, usernames colliding across a shared
   tenant, and three console figures that turned out to be cached snapshots.
   *94 accounts → 94 identities; Entra correlating on employee ID.*

## The data

`data/acme_hr_baseline.csv` is the authoritative population — 94 employees with
deliberately awkward cases: duplicate names, accented characters, a preferred
name, a manager-less CEO, contractors, pre-hires, people on leave and
terminations.

`data/acme_hr_jml_update.csv` models the same population a week later: two
joiners, three movers, a leaver, a return from leave and a name change.

`data/acme_jml_answer_key.csv` states what each of those changes *should* cause.
Keeping the expected outcome separate from the input is what makes this a test
rather than a demonstration.

`data/acme_finance_app_accounts.csv` is the Finance target application, with
entitlements, orphan accounts and a separation-of-duties conflict.

## Verifying rather than trusting

Three figures in the admin console turned out to be cached snapshots rather than
live state — an identity count that read 24 for three days while 94 identities
existed, an exception report that returned a byte-identical file days later, and
a recommendation panel reporting no identities while the tenant was full of them.

`scripts/` holds the checks written in response. Each answers a question the
console doesn't answer directly, and each exits non-zero when the answer is
wrong:

- **`Test-SourceIdentityIntegrity.ps1`** — compares account count against
  *distinct* identity count. Catches silent identity merges, which is how one
  person's termination ends up acting on somebody else.
- **`Test-ManagerGraph.ps1`** — confirms every manager reference resolves inside
  the population. A dangling reference means an access request with no approver
  and no error.

## Demonstrated so far

Authoritative sources and identity profiles · attribute transforms (concat,
lookup, firstValid, diacritical folding) · lifecycle states · account correlation
and orphan detection · virtual appliance deployment on GCP · Microsoft Entra
integration (app registration, consent, account and entitlement aggregation) ·
REST API automation in PowerShell · reading logs and diagnosing silent failures

## Planned

Access profiles and RBAC role modelling · access requests and approvals ·
provisioning to Entra (create, update, disable) · access certification campaigns ·
separation of duties policy · workflow automation · Python verification tooling

These are the remaining milestones, listed so the gap between what's built and
what's planned is visible rather than implied.

## A note on scope

This is a personal learning lab built in a shared training tenant. All identity
data is generated. Screenshots are sanitized, and no tenant URL, hostname, IP
address, credential or customer information appears in this repository. Internal
object identifiers are partially redacted where they appear.
