<#
.SYNOPSIS
    Checks that a source's accounts produced one identity each.

.DESCRIPTION
    An authoritative source should produce exactly one identity per account. If
    the account identifier is not unique per person, accounts merge onto shared
    identities — and nothing errors. The aggregation reports success, the source
    looks healthy, and the only visible symptom is a count that quietly stops
    making sense.

    This compares three numbers the console does not show together:

        accounts        how many accounts exist on the source
        identities      how many DISTINCT identities they point at
        uncorrelated    how many accounts produced no identity at all

    accounts = identities and uncorrelated = 0 is the healthy result.
    identities < accounts means accounts are merging.
    uncorrelated > 0 means records failed to process.

    Do not judge correlation by whether identityId is populated: it is set even
    on uncorrelated accounts. The reliable flag is 'uncorrelated'.

.PARAMETER SourceName
    Exact display name of the source.

.PARAMETER ShowMerged
    List the identities that have more than one account, with the accounts on
    each. Use this when identities < accounts to see what is merging.

.EXAMPLE
    . ./isc-env.ps1
    Connect-ISC
    ./Test-SourceIdentityIntegrity.ps1 -SourceName "Acme HR - Karima"

.EXAMPLE
    ./Test-SourceIdentityIntegrity.ps1 -SourceName "Acme HR - Karima" -ShowMerged

.NOTES
    Exits 1 if the source is not internally consistent, so it can gate a
    pipeline or a scheduled check. Read-only: creates and changes nothing.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceName,
    [switch]$ShowMerged
)

$ErrorActionPreference = 'Stop'

if (-not $H) {
    throw "Not authenticated. Dot-source isc-env.ps1 and run Connect-ISC first."
}

$src = Get-ISCSource -Name $SourceName
Write-Host "Source:  $($src.name)"
Write-Host "Cluster: $(if ($src.cluster) { $src.cluster.name } else { '(cloud-managed)' })"
Write-Host ""

$accounts = Get-ISCAccounts -SourceId $src.id

$total        = $accounts.Count
$identities   = ($accounts.identityId | Where-Object { $_ } | Select-Object -Unique).Count
$uncorrelated = ($accounts | Where-Object { $_.uncorrelated }).Count

Write-Host ("accounts:     {0}" -f $total)
Write-Host ("identities:   {0}" -f $identities)
Write-Host ("uncorrelated: {0}" -f $uncorrelated)
Write-Host ""

$problems = @()

if ($identities -lt $total -and $uncorrelated -eq 0) {
    $problems += "$($total - $identities) account(s) share an identity with another account."
}
if ($uncorrelated -gt 0) {
    $problems += "$uncorrelated account(s) produced no identity."
}

if ($ShowMerged -or ($identities -lt $total)) {
    $merged = $accounts |
        Where-Object { $_.identityId } |
        Group-Object identityId |
        Where-Object { $_.Count -gt 1 } |
        Sort-Object Count -Descending

    if ($merged) {
        Write-Host "Merged identities:"
        foreach ($g in $merged) {
            $names = ($accounts | Where-Object { $_.identityId -eq $g.Name }).nativeIdentity
            Write-Host ("  {0} accounts -> one identity: {1}" -f $g.Count, ($names -join ', '))
        }
        Write-Host ""
        Write-Host "Check the source's Account Name attribute. If it is mapped to"
        Write-Host "anything that repeats across people (a first name, a department),"
        Write-Host "accounts are matched by that value and merged."
        Write-Host ""
    }
}

if ($problems) {
    foreach ($p in $problems) { Write-Host "FAIL  $p" }
    exit 1
}

Write-Host "PASS  one identity per account, none uncorrelated."
exit 0
