# Building the HR authoritative source — and five failures on the way

Karimunnisa-s · 28 September 2026 · updated 29 September 2026

Goal: load a 94-employee HR file into SailPoint as an authoritative source, turn
those accounts into identities, and correlate a Microsoft Entra source against
them on employee ID.

That is a one-hour task when it works. It took four days, and every one of the
delays was worth more than the task itself. This write-up covers what broke, how
I found each cause, and what I would check first next time.

The environment is a shared training tenant with a virtual appliance I deployed
on GCP. The data is entirely fictional — 94 invented employees at a made-up
company. Tenant URLs, IP addresses and credentials are deliberately absent.

## Where it ended up

| | |
|---|---|
| HR accounts aggregated | 94 |
| Distinct identities created | 94 |
| Accounts failing to correlate | 0 |
| Entra accounts | 12 |
| Entra accounts correlated | 9 (8 by employee ID, 1 by API) |
| Entra accounts correctly left uncorrelated | 3 |
| Identities with a manager | 93 of 94 (the CEO has none) |
| Managers resolving to someone else's identity | 0 |
| Open anomalies | 0 (one root cause unproven; see Entra correlation) |

The three uncorrelated accounts are a temp auditor, a legacy service account and
an external guest — seeded without an employee ID on purpose, so that something
*should* fail to correlate. A correlation test where everything matches proves
very little.

---

## 1. A source configured to fetch a file from nowhere

**Symptom.** Aggregation failed with *"Connector failed to complete aggregation.
Connector may not be sending responses. This aggregation has been tried (2) times
without success."* The source reported 0 accounts and an "incomplete
configuration" banner, with no indication of what was incomplete.

**Investigation.** I dumped the connector attributes for every source in the
tenant and compared mine against ones that were working:

| | Mine | A working source |
|---|---|---|
| `filetransport` | `sftp` | `sftp` |
| `host` | *(empty)* | *(set)* |
| `port` | *(empty)* | `22` |
| `transportUser` | *(empty)* | *(set)* |
| `file` | a path | a path |
| `status` | `SOURCE_STATE_UNCHECKED_SOURCE_NO_ACCOUNTS` | — |

**Root cause.** The source was set to fetch its file over SFTP but had no host,
port or credentials. It had a path to a file on a server that was never named.

**Fix.** Put the CSV on the appliance itself and pointed the connector at the
appliance's internal address.

**What I'd check first next time.** A delimited source that reports zero accounts
and a vague aggregation failure — read `connectorAttributes` before touching
anything else. The configuration page showed a green-looking source; the
attribute dump showed the holes in one glance.

---

## 2. The last surviving appliance in a shared cluster

**Symptom.** *"Timeout waiting for response to message 2 from client … after 15
seconds"* on every Test Connection. The appliance showed **Connected**.

**Investigation.** SFTP worked when I ran it by hand on the appliance, so
credentials, path and port were all fine. The connector gateway log told a
different story:

```
"message":"Cannot find key to decrypt message"
com.sailpoint.pipeline.util.Decrypter.decryptObject → IllegalStateException
```

Repeating every 15–30 seconds, continuously, with timestamps unrelated to
anything I was doing.

The cluster listing explained it. Four appliances, three of them inactive since
a week earlier, mine the only one connected.

**Root cause.** Decryption keys are per-appliance. My appliance was the only live
member of a shared cluster, so it picked up every queued message for that
cluster — including work encrypted for the three dead appliances, which it had no
key for. My own request sat behind traffic it could only fail on.

A side effect worth flagging: messages my appliance consumed and failed to
decrypt were messages the intended appliance never received. I told the trainer.

**Fix.** Created my own cluster, re-paired the appliance to it, re-pointed the
source.

**The reasoning that got there.** The errors were continuous and unrelated to my
clicks. An error stream that keeps running while you do nothing is ambient, not
triggered — so the fault was not in the thing I was testing.

---

## 3. Connector secrets are encrypted per cluster

**Symptom.** Immediately after moving the source to the new cluster:
*"Failed to decrypt cluster-encrypted connector secret."*

**Root cause.** The SFTP password was encrypted with the old cluster's key. The
new cluster's appliance holds a different key and cannot read it.

**Fix.** Re-entered the password so it was re-encrypted under the new cluster.

**Prevention.** Moving a source between clusters invalidates every stored secret
on it. Nothing warns you at the point of the move; it surfaces later as a
decryption error at connection time. Re-enter credentials as part of any
re-clustering, not as a reaction to the failure.

---

## 4. Usernames are unique per tenant, not per identity profile

**Symptom.** 94 accounts aggregated. 24 identities created. No error on the
source, no error on the aggregation.

**Investigation.** The identity exception report listed ~40 rows, all
*"Non-unique username"*. Half the rows were not my data at all — they were other
students' identities, shown as the other side of each collision.

**Root cause.** I had mapped the identity username to the employee ID. Another
identity profile in the shared tenant had already claimed employee IDs in the
same range. Usernames must be unique across the whole tenant, so the overlapping
ones were rejected. The 24 that succeeded were exactly the IDs nobody else held.

**Fix.** A transform that prefixes the employee ID, making the username unique by
construction rather than by luck.

**Prevention.** In a shared environment, derive usernames from something
namespaced to you. And read the identity exception report early — the failure was
invisible on the source and on the aggregation, and only that report named it.

---

## 5. An account name that wasn't a name

This is the one worth reading.

**Symptom.** After fixing the usernames: 94 accounts, and 48 identities. Nothing
errored.

**Investigation.** I compared distinct identity IDs against the account count,
then grouped accounts by the identity they had landed on:

```
6 accounts → one identity
6 accounts → one identity
5 accounts → one identity
5 accounts → one identity
4 accounts → one identity
```

Listing the worst group showed six different employee IDs — and one shared
value in the account **name** column: `John`.

**Root cause.** The source's Account Name attribute was mapped to the employee's
first name. Accounts were therefore matched by name, and every employee sharing a
first name was merged into a single identity. The group sizes were the frequency
distribution of first names in the file; 48 was roughly the number of distinct
first names among 94 people.

Every earlier symptom was downstream of this.

**Fix.** Account ID and Account Name both set to the employee ID. That cannot be
changed once accounts exist, so the source had to be rebuilt — which meant
deleting the identity profile first, then the transforms that referenced the
source by name, then the source itself.

Result: 94 accounts, 94 distinct identities, zero uncorrelated.

**Why it matters beyond the lab.** A merged identity is not a cosmetic problem.
Two employees on one identity means terminating one of them acts on both, or on
neither. It fails silently — no error, no exception report entry, just counts
that quietly stop making sense.

**Prevention.** An account identifier must be unique per person. Names are not
identifiers. Verify by comparing distinct identity count against account count
immediately after the first aggregation, before building anything on top.

---

## 6. Three console figures that were snapshots, not state

A recurring theme, and the thing that cost the most time overall.

| What I read | What it actually was |
|---|---|
| Identity profile's identity count | A cached counter. Read 24 for three days while 94 identities existed; later read 84 against a verified 94, and 87 after that. The 84 turned out to be ten identities missing from the search index (finding 9). |
| Identity exception report | A stored task result. Re-downloading produced a byte-identical file three days later — same rows, same order. |
| Correlation recommendations | *"No identities found. Please aggregate accounts for an authoritative source"* — while 94 identities demonstrably existed. It reads a search index that lags. |

Each of these looked like live state and was not. Twice I concluded a fix hadn't
worked when it had.

**The habit that fixed it:** count the objects directly.

```powershell
$accts = # accounts on the source, via the accounts API
"accounts:     $($accts.Count)"
"identities:   $(($accts.identityId | Select-Object -Unique).Count)"
"uncorrelated: $(($accts | Where-Object { $_.uncorrelated }).Count)"
```

Three numbers, and between them they distinguish "nothing processed", "merged
identities" and "records failed" — none of which the console distinguishes on its
own.

---

## 7. Aggregation optimization hides fixed configuration

After correcting the username mapping, the identity count didn't move. The
configuration was right and the numbers said otherwise.

Aggregation skips accounts whose source data hasn't changed. My CSV was
byte-identical, so every account was treated as unmodified and the previously
failed records were never re-evaluated. A configuration fix does not retroactively
repair records created under the broken configuration.

To force a full pass I added a column to the file so every row hashed
differently. In the end the source was rebuilt anyway, which made the point moot —
but the lesson holds, and it is a common source of "the fix didn't work" when the
fix was fine.

---

## Infrastructure notes

Smaller items, kept because each cost real time.

**A firewall rule's source ranges are a union.** `default-allow-ssh` carried both
`0.0.0.0/0` and a `/32` for my home address. Adding the `/32` narrowed nothing —
a packet matches if it matches *any* range, so SSH was open to the internet the
whole time I believed it was restricted. Found by verifying a claim I was about
to publish. Fixed by replacing the range list rather than adding to it.

**`gcloud compute ssh` does not work on the appliance.** It is a hardened image
without Google's guest agent, so metadata SSH keys are ignored. Connecting
directly as the appliance's own user works; the serial console works when nothing
else does.

**Ephemeral external IPs change on every stop/start.** I lost time three separate
times connecting to an address that no longer belonged to the VM. Reserved a
static address. The source configuration was unaffected throughout because it
points at the internal address, which is stable — that turned out to be a better
decision than I realised when I made it.

**API notes.** Each of these cost a round trip:

- Access tokens from a personal access token expire within minutes. Expect
  `JWT is expired` mid-sequence and fetch a fresh token before each batch.
- `/v3/roles` and `/v3/access-profiles` cap `limit` at 50. Asking for 250 returns
  a 400, *"syntactically correct but semantically invalid"*, which does not
  mention the limit.
- Aggregating with optimization disabled is not offered in the UI.
  `POST /beta/sources/{id}/load-accounts` with `disableOptimization=true` does
  it, and for a delimited-file source the CSV must be uploaded in the same
  request.
- An account's SailPoint `id` is not the connected system's ID (for Entra, the
  `objectId`). Look the account up by `nativeIdentity` instead of copying IDs
  from page URLs.
- In PowerShell, a JSON array from `Invoke-RestMethod` can reach the pipeline as
  a single object. `ForEach-Object { $_ }` unrolls it; otherwise `Select-Object`
  prints one row holding arrays.
- A field-scoped search (`attributes.employeeNumber:…`) returned nothing even
  for a value known to exist, while free text matched far more than asked for.
  I stopped trusting search for exact matches and filtered API results locally.

---

## Entra correlation

With identities finally correct, correlating the Entra source was configuration
rather than archaeology: account attribute `employeeId` → identity attribute
Employee Number.

Of 12 accounts: 9 correlated (8 by the rule, 1 linked by API, below) and 3
correctly did not, having no employee ID to match on.

The result I was looking for: **two accounts named John Smith correlated to two
different identities**, on employee IDs `E1068` and `E1071`. Two people who share
a name, kept apart because correlation keys on the employee ID rather than the
name.

That is the same principle as finding 5, seen from the other side. When matching
keys on a name, people merge. It is a more convincing demonstration having
watched six Johns collapse into one identity earlier the same day.

A small thing that made the account list readable: an uncorrelated account still
has an identity, a placeholder named after the account itself. In the source's
account list, a UPN in the Identity column means *uncorrelated*; a person's name
means correlated. It also means a distinct-`identityId` count on a source
includes placeholders, so filter out uncorrelated accounts before counting.

**The E1006 account: resolved, cause not proven.** The first version of this
write-up left one account open. Its identity's Employee Number was blank, and I
blamed the profile rebuild. By the next morning the identity showed `E1006`, and
the account still would not correlate. What I ruled out:

| Check | Result |
|---|---|
| Entra `employeeId` | Byte-checked: 5 characters, codes `69 49 48 48 54` |
| Identity Employee Number | The same, byte-checked |
| Correlation config | One rule; the default name/UPN row cannot match these identities |
| Was the account re-evaluated? | Yes. I changed its office location in Entra; the new value arrived on aggregation and it still did not correlate |
| Errors on the identity | None |
| CSV correlation import | *"The following account(s) failed to correlate"* |

`PATCH /v3/accounts/{id}` on `identityId` links an account to an identity by ID,
with no lookup involved. That worked. The account shows `manuallyCorrelated: true`
and has survived full aggregations since. Worth remembering for the leaver test:
this account is now held by the manual link, not by the rule.

Two loose ends. The CSV import may have failed on its own terms. I put the
identity's username (`karima.E1006`) in its `userName` column, but the identity's
*name* is `E1006`. The likelier explanation for the rule failing came a day later,
in finding 8: other students' identities in this tenant carry the same E10xx
employee numbers. If one of them holds `E1006`, the lookup was ambiguous and
correlation declined to guess, which fits every row of that table. I have not
verified it, so it stays a hypothesis. If it is true, the Entra rule has the same
weakness the manager lookups had, and the 8 that did correlate did so because
nobody else held their numbers.

---

## 8. Managers: three wrong keys, and 20 accounts on strangers' identities

**Symptom.** Manager blank on every identity. No error anywhere.

**First cause: nothing configured.** The source's manager correlation mapping was
empty, lost in the rebuild with everything else. The identity profile correctly
took Manager from `manager_id`, but nothing told SailPoint how to turn `E1063`
into a person.

**Second: a key the API accepted but could not use.** I set `manager_id` →
`employeeNumber` by API. It returned success and stored the value. Nothing
resolved, even though the raw ID reached the identity (`managerId` = `E1026`) and
exactly one of my identities held `E1026`. A read-only survey of manager
correlation on roughly 90 other sources in the tenant found that none used
`employeeNumber`. Comparing a working identity's attributes later showed why:
Employee Number's technical name is `identificationNumber`. The API validates
the shape of a request, not whether the attribute exists.

**Third: keys that are not unique across the tenant.** Switching to `name`, the
most common choice in that survey, resolved John Larsen to Yuki Lopez. A full
count then showed 21 identities without a manager instead of 1. Twenty of them
were near-empty: no first name, no department, a display name equal to the raw
ID, never synced. Every one reported to E1001, E1002 or E1003.

**The leak.** Those 20 were not unprocessed. Their HR accounts had left them.
Each account now pointed at one of three identities belonging to other
students, grouped exactly by manager:

| Other student's identity | My accounts it held |
|---|---|
| A | all 8 reports of E1001 |
| B | both reports of E1002 |
| C | all 10 reports of E1003 |

The cause was an **account** correlation rule on the HR source: identity
`employeeId` equals account `manager_id`. That attaches each employee's account
to the identity whose ID matches *their manager's*. My identities do not carry
`employeeId`, so it matched nothing of mine. Three of the other students'
identities did carry E1001 to E1003, so when forced aggregations re-ran
correlation on all 94 accounts, those three teams were pulled across. I do not
know when the rule was set. The likeliest explanation is that it was entered on
the Account Correlation screen while setting up manager correlation, which sits
next to it.

**Repair.** Cleared the rule; an authoritative source's accounts create
identities and need no account correlation. Each orphaned identity was still
named after its account, so every account could be matched back to its own
orphan by name and moved with `PATCH /v3/accounts/{id}`. 20 of 20 restored.

Then `identificationNumber`, the correct attribute name at last, resolved the
E1002 to E1004 teams to three *more* strangers' identities. In this tenant every
E10xx value is shared.

**Final fix.** A key that is unique by construction. A new CSV column,
`manager_key` = `karima.<manager_id>`, correlated against `uid`, the prefixed
username from finding 4 that the tenant already forces to be unique. The check
I trusted was not the Manager field itself but whether each manager is one of
mine:

```powershell
$mine = @($accts.identityId | Select-Object -Unique)
# for each identity $x:
$foreign = $x.managerRef -and $x.managerRef.id -notin $mine
```

Result: 94 accounts, 94 identities, 0 uncorrelated; 93 managers; 0 resolving
outside my identities. The one blank is the CEO.

**Why it matters beyond the lab.** For part of an afternoon, three whole teams
were attached to other people's identities. In production, that is an HR feed
attaching employees to the wrong person, finding 5's problem across tenants
rather than within one source. At no point was there an error. The only symptom
was a blank Manager field.

**Prevention.** In a shared tenant, every correlation key is a tenant-wide
lookup, for account and manager correlation alike. If a value can exist in
someone else's data, it will eventually match it, so namespace the key. And after
any rebuild, confirm that an authoritative source's account correlation is empty
or deliberate.

---

## 9. Other people's configuration, landing on my identities

Three incidents I did not cause, each found by following an error outside my own
configuration.

**A role scoped to the whole tenant.** Every aggregation I ran logged a failed
*Create Account* on my IT identities, against a source I had never configured:
a 401 during that source's unique-account-ID check. The actor was "unknown", and
the timestamp fell inside my own aggregation window, so the attempt came from
identity refresh. The Access tab showed no role. Scanning the tenant's 76 roles
by API found nothing through access profiles. The answer came from resolving
each directly-assigned entitlement to its source. The trigger was a role with
criteria on an *identity* attribute (department equals HR or IT), which applies
to every identity in the tenant, holding one entitlement on that source. My HR
department is called "Human Resources", so only an exact-match string spared it.
The 401 was the only thing preventing real account creation in someone else's
Entra tenant. I saved the role's full definition, deleted it and reported it.
There have been no new failures since. In hindsight, disabling it would have
been the better call: it is reversible, and the role was not mine.

**My source's credentials, changed.** My Entra source began failing with
`AADSTS700016`: the application was not found in the directory. The source's
client ID had been replaced with an app from another directory, some time
after my last good aggregation. Restoring my own client ID and re-entering the
secret fixed it. The source's `modified` timestamp matched the second error to
the second. It records health-status updates, not edits, so it could not say
who made the change.

**One department missing from search.** All ten IT identities were absent from
the search index while the other 84 were present. That, rather than only a
stale counter, was the "84 against a verified 94" in finding 6. It coincided
exactly with the department that role was provisioning. After the role was
removed and the identities reprocessed, all 94 were indexed. The two are
correlated; I have not shown that one caused the other.

---

## What I'd tell someone starting this

1. After the first aggregation, compare distinct identity count against account
   count. If they differ, stop and fix the account identifier before building
   anything.
2. Read the identity exception report early. Failures there are invisible
   everywhere else.
3. Don't trust summary counts, cached reports or recommendation panels. Count the
   objects.
4. A continuous error stream with timestamps unrelated to your actions is
   ambient, not triggered — look outside the thing you're testing.
5. In a shared tenant, assume every namespace is contested: usernames, employee
   ID ranges, cluster queues, roles, even your own source's credentials.
6. Verify claims before writing them down. The firewall rule I was about to
   describe as restrictive was not.
7. Every correlation key is a tenant-wide lookup. Namespace it (a prefixed
   column matched to `uid`) rather than trusting that nobody else holds the
   same values.
8. An authoritative source should have no account correlation unless you put it
   there on purpose. Check it after every rebuild.
9. The API validates format, not meaning. When correct-looking configuration does
   nothing, compare it against configurations that work.
10. When a query returns nothing, run a control that should return something.
    A broken query and absent data both look like zero.
11. Before removing anything that isn't yours, save its definition, tell the
    owner, and prefer disable to delete.

---

*Fictional data throughout. Tenant identifiers, hostnames, addresses and
credentials are deliberately omitted.*
