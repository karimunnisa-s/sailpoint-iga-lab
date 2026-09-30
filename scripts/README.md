
# Scripts

Read-only checks against the SailPoint API. Each one answers a question the
admin console does not answer directly, and each exits non-zero when the answer
is wrong — so they can gate a pipeline or run on a schedule rather than being
clicked through by hand.

Nothing here creates, changes or deletes anything.

## Setup

```powershell
cp isc-env.example.ps1 isc-env.ps1     # fill in tenant URL and PAT
. ./isc-env.ps1
Connect-ISC
```

`isc-env.ps1` holds a live client secret and is excluded by `.gitignore`. Only
the example file is committed.

Tokens last about an hour; re-run `Connect-ISC` when a call reports
`JWT expired`.

## Checks

### `Test-SourceIdentityIntegrity.ps1`

Compares account count, distinct identity count and uncorrelated count for a
source.

```powershell
./Test-SourceIdentityIntegrity.ps1 -SourceName "Acme HR - Karima"
```

```
accounts:     94
identities:   94
uncorrelated: 0

PASS  one identity per account, none uncorrelated.
```

An authoritative source should produce one identity per account. When it
doesn't, nothing errors — the aggregation reports success and the source looks
healthy. This lab hit exactly that: 94 accounts produced 48 identities because
the source's Account Name was mapped to the employee's first name, so every
employee sharing a first name merged into one identity. Six people called John
became one person.

`-ShowMerged` lists which accounts landed on shared identities, which usually
names the cause immediately.

A merged identity is not cosmetic. Two employees on one identity means
terminating one acts on both, or on neither.

### `Test-ManagerGraph.ps1`

Checks that every identity's manager resolves to someone in the same population.

```powershell
./Test-ManagerGraph.ps1 -SourceName "Acme HR - Karima"
```

```
no manager:      1
foreign manager: 0

Identities with no manager:
  Karen Whitfield

PASS  manager graph is sound.
```

One identity without a manager is expected — the person at the top. More than
that means a mapping is missing. A manager pointing outside the population
means the key resolved to the wrong identity, which in a shared tenant can mean
someone else's.

This matters because access requests route to the requester's manager. A
dangling reference leaves the request with no approver and no error; it simply
waits.

## A note on what these measure

Three figures in the console turned out to be cached snapshots rather than live
state: the identity profile's identity count, the identity exception report,
and the correlation recommendation panel. Each looked authoritative and each
was stale — one by three days.

These scripts count objects directly for that reason. The habit, more than the
code, is the point: verify by querying the thing itself, not by reading a
summary of it.

One specific trap they encode: `identityId` is populated on an account even when
the account is not correlated. The reliable flag is `uncorrelated`. Judging
correlation by the presence of an identity id gives a confident wrong answer.
