# Modelling access for a target application

*Building a Finance application as a target source, correlating it to the HR
population, and discovering that "uncorrelated" covers four different problems.*

Karimunnisa-s · 14 October 2026

---

## What I set out to do

The HR source from [write-up 2](02-hr-source-and-correlation.md) is
authoritative: it decides who exists. This one is the opposite. A Finance
application that holds *accounts* belonging to people HR already knows about,
with entitlements attached to them.

That distinction drives everything else. An authoritative source should produce
exactly one identity per account and nothing left over. A target application
legitimately has accounts with no owner — leavers nobody disabled, service
accounts, contractors who came through a side door. Finding those is the point
rather than a defect.

The synthetic data was built with known answers so that every step could be
checked against a number rather than a feeling:

| Check | Expected |
|---|---|
| Accounts | 31 |
| Entitlements | 6 |
| Correlated | 25 |
| Uncorrelated | 6 |
| Orphans holding `Payroll_Admin` | 2 |
| Separation-of-duties violations | 3 |
| Terminated employees with a live account | 1 |

I got 24 correlated and 7 uncorrelated. The difference turned out to be the
most interesting finding in the exercise, and it wasn't in the data at all.

---

## The entitlement file, and a connector that does not do what the CSV implies

My first version of the account file had one row per account and a
pipe-delimited cell:

```
fin1024,E1024,...,Expense_Submit|AP_Approver,2026-09-30
```

That is how a person would write it. It is not how the Delimited File connector
reads it. The connector handles multi-valued attributes by **merging rows that
share an index column** — `mergeRows`, `indexColumn`, `mergeColumns` — not by
splitting a delimiter inside a cell. Pointed at the file above, it produced
seven entitlements, each a literal string with a pipe in it.

So the data had to match the connector's model rather than my mental one. The
account file was regenerated as **53 rows — one per account-entitlement pair** —
with `account_id` as the index column and `entitlements` as the merge column.

Then entitlement aggregation returned **31 entitlements, each named after an
account**. Nonsense output, no error.

The cause: a group schema needs its own file. `group.file` was empty, so
entitlement aggregation fell back to the account file and dutifully created one
entitlement per row it found. A separate definition file fixed it:

```
id,name,displayName,description,privileged
Expense_Submit,Expense_Submit,Expense Submission,Submit expense claims for reimbursement.,false
GL_Viewer,GL_Viewer,General Ledger - Read Only,...,false
GL_Admin,GL_Admin,General Ledger - Administrator,...,true
AP_Approver,AP_Approver,Accounts Payable Approver,...Must not be combined with expense submission.,true
Payroll_View,Payroll_View,Payroll - Read Only,...,false
Payroll_Admin,Payroll_Admin,Payroll - Administrator,...,true
```

**I should record that this one was my own mistake twice over.** I had initially
decided entitlement aggregation could be skipped entirely, on the reasoning
that the entitlements were already present as account attributes. That was
wrong: without a group schema there is nothing for an access profile to
reference, nothing to carry a description, and nothing to mark privileged.
Skipping it doesn't simplify the model, it removes it.

The `description` and `privileged` columns look like paperwork and are the
difference between a certification campaign that means something and one that
doesn't. A reviewer asked to approve `Payroll_Admin` with no description either
rubber-stamps it or guesses. Six entitlements, six sentences, and the review
becomes possible.

---

## Correlation, and the rule that governs this whole lab

Correlation config: account attribute `emp_no` → identity attribute **Employee
Number**, whose technical name is `identificationNumber`. Same pattern that
works on Entra.

Saved it. Re-aggregated. **31 accounts, 0 correlated.**

Three things were wrong in sequence, and only the third was interesting.

**First, the rule saved empty.** Reading it back over the API returned
`"attributeAssignments": []`. The UI had accepted the input and stored nothing.
Worth checking a saved rule by reading it rather than by looking at the screen
that just accepted it.

**Second, with the rule saved correctly, still 0 correlated.** Re-aggregating
changed nothing. Repeatedly.

The reason is the single most useful thing I have learned in this lab, and it
has now appeared in four separate guises:

> **Correlation is evaluated when an account is created, not when it is
> updated.** Aggregation also skips rows whose content has not changed. So a
> correlation rule fixed after the accounts exist does not reach back into them,
> and re-running aggregation does not help, because from the connector's point
> of view nothing has changed.

The fix is to delete the accounts and let them be created again under the
corrected configuration. There is no bulk delete in the UI, so this went
through `DELETE /v3/accounts/{id}` in a loop.

The same rule, in its other costumes: an Account Name mapped to a first name
merged 94 accounts into 48 identities and no later fix corrected the existing
ones; usernames that collided tenant-wide stayed broken until the identities
were recreated; two identity-profile mappings lost in a rebuild broke Entra
correlation silently and only new accounts picked up the repair. Four
symptoms, one rule. If I could keep one sentence from this lab it would be that
one.

**Third, I fixed the number the wrong way.** With correlation working I had 7
uncorrelated accounts, and the plan said 6. So I added `email` as a second
correlation criterion, and the count improved — because the email criterion
matched the accounts that were *designed* to have no owner. I had quietly
deleted the exercise in order to make its score look right. The criterion came
back out.

That is a real temptation rather than a lab artefact. An orphan count going
down looks like progress on any dashboard, and the cheapest way to achieve it
is a looser matching rule. The result is accounts confidently attributed to
people who do not own them, which is worse than an honest orphan.

---

## Four kinds of "uncorrelated"

Final state: **31 accounts, 24 correlated, 7 uncorrelated.** All seven surface
in the console identically. They are four different problems.

| Account | Cause | What it means operationally |
|---|---|---|
| `fin1018`, `fin1034`, `fin1035`, `fin1093` | no `emp_no` at all | data quality gap — the app was never given the key |
| `svc_finrecon` | service account | correct that it has no owner; needs an *accountable* owner instead |
| `fin_tmp01` | `emp_no` is `E9999` | a key that looks valid and resolves to nobody — stale or invented |
| `fin1003` | `emp_no` is `E1003`, which matches **two** identities | ambiguous match |

The first three were planted. The fourth was not, and it is the one I would
talk about in an interview.

`fin1003` carries `E1003`. In this shared training tenant, `E1003` belonged to
**two** identities: Linda Cruz, from another student's population, and Barbara
Nguyen, from mine. ISC refused to correlate the account to either one.

That refusal is correct, and it is better behaviour than the alternative. An
identifier that is unique in my data was not unique in the tenant, and the
system declined to guess which person a Finance account belonged to rather than
attaching it to someone at random. A product that resolved the ambiguity
silently would have produced a confident wrong answer — and the wrong answer
here is "this person has access they don't have", which is exactly what
certifications and leaver processes act on.

It also means **my own expected number was wrong**, and that is the honest
lesson. I had built the data with six orphans and verified against six. The
seventh came from the environment, not the file. A test whose expected values
are derived only from your own inputs cannot see the shared system you are
running inside.

Two of the orphans — `fin1034` and `fin1035` — hold `Payroll_Admin`. Unowned
accounts with administrative rights over payroll is the finding an access
certification exists to surface, and it is waiting in the data for the campaign
step.

---

## Figures that disagreed with themselves

A recurring theme from write-up 2 continued here, so it is worth recording that
it was not a one-off.

After deleting accounts through the API, the API reported 5 remaining and the
UI reported 0. Mid-rebuild I saw 28 accounts / 26 correlated / 2 uncorrelated,
then 31 / 24 / 7 after a further aggregation, with no configuration change in
between. There was also a stale object listed alongside the six entitlements
that no longer corresponded to anything.

I have stopped treating any single reading as authoritative. The habit that
replaced it: count the objects, twice, and prefer the count that survives a
re-read.

---

## Access profiles

Six entitlements grouped into five access profiles:

| Access profile | Entitlements | Intended |
|---|---|---|
| `Finance — Expense Submission` | `Expense_Submit` | birthright |
| `Finance — Ledger Read` | `GL_Viewer` | birthright for Finance |
| `Finance — Ledger Administration` | `GL_Admin` | requestable |
| `Finance — AP Approval` | `AP_Approver` | requestable |
| `Finance — Payroll Administration` | `Payroll_View`, `Payroll_Admin` | requestable |

My first attempt was one profile containing all six entitlements, which defeats
the purpose. The unit of an access profile is the unit a person can be granted
or can request, so bundling everything means the only available decision is
"all of Finance or none of it". Payroll is the one legitimate bundle: viewing
payroll without being able to modify it is a coherent role, but modifying it
without viewing it is not, so those two travel together.

**Two things I could not complete in the console, and how both resolved:**

**Owners could not be set to me.** My admin login has no identity in this
tenant, so it cannot be selected as an owner, and the profiles were initially
owned by the trainer's account. That is not cosmetic — the owner is who a
certification campaign routes to, so the reviews would have gone to someone with
no basis for answering. Resolved by assigning an Acme business identity, the VP
of Finance, once the identities existed.

**The profiles could not be marked requestable.** The option was not available
in the UI, and I could not tell whether that was a licence limitation on this
training tenant or a setting I had not found. It was neither:
`POST /v3/access-profiles` sets `requestable` without complaint. A UI gap, not a
tenant restriction — see [write-up 4](04-role-modelling-and-blast-radius.md),
where the access model is rebuilt from a definition file with the flag set
correctly on all five profiles.

**And one I did not notice until later.** The entitlement file carries a
`privileged` column, and after aggregation all six entitlements read
`privileged = false`. The flag has to be set on the entitlement object; the data
does not supply it. Worth knowing before a certification campaign, because
privileged access is exactly what a reviewer is meant to scrutinise.

---

## Where this leads

The application is loaded, correlated and described. Nobody has been granted
anything yet, which is the next milestone: access profiles into roles, roles
scoped to the right population, and the distinction between access you receive
because of who you are and access you receive because you asked and someone
approved.

That is [write-up 4](04-role-modelling-and-blast-radius.md), which also covers
the thing I did not expect to be the most useful finding of the exercise —
that role membership criteria are evaluated against every identity in the
tenant, so the obvious criteria for these roles would have granted to 192
identities against an intended 84.

The separation-of-duties policy and the leaver test follow. The data is already
carrying both: three accounts hold `Expense_Submit` and `AP_Approver` together,
and one terminated employee still has a live Finance account with active
entitlements.

One piece of tooling came out of this write-up rather than the lab: my own
`Test-SourceIdentityIntegrity.ps1` reports FAIL on this source, because it
checks that every account produced an identity. That is correct for an
authoritative source and wrong for a target application, where unowned accounts
are the finding rather than the defect. The check encodes an assumption it never
states. Worth fixing, and worth noticing that a check can be confidently wrong
in a direction nobody looks at.

---

## What I would check first next time

1. **Does the connector's model match the file's shape?** Merged rows, not
   delimited cells. Check before generating data, not after aggregating it.
2. **Does entitlement aggregation have its own file?** An empty `group.file`
   silently falls back to the account file.
3. **Do the accounts predate the configuration?** If a mapping or correlation
   rule changed, existing records will not reflect it. Delete and re-create.
4. **Is an improving metric improving for the right reason?** A falling orphan
   count can mean better matching or looser matching.
5. **Is the identifier unique in the tenant, or only in my data?** `E1003` was
   unique in my file and ambiguous in the environment.
6. **Does the automation belong to a person or to the tenant?** If a human
   identity can take the integration down, it will.
