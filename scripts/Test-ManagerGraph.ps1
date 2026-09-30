<#
.SYNOPSIS
    Checks the manager hierarchy of a source's identities for dangling references.

.DESCRIPTION
    Every identity's manager should resolve to another identity in the same
    population, with one exception: whoever sits at the top.

    Two failure modes matter, and neither raises an error in the console:

      no manager        the manager attribute is empty. Expected exactly once,
                        for the person at the top of the hierarchy. More than
                        one usually means a mapping is missing or the manager
                        key did not resolve.

      foreign manager   the manager points at an identity outside this
                        population. In a shared tenant this can mean a manager
                        key collided with someone else's identity.

    Why it matters: access requests route to the requester's manager. A manager
    reference that resolves to nothing leaves the request sitting in a queue
    with no approver, and nobody finds out until someone chases it.

.PARAMETER SourceName
    Exact display name of the authoritative source.

.PARAMETER ExpectedRootCount
    How many identities are allowed to have no manager. Default 1 (the CEO).

.EXAMPLE
    . ./isc-env.ps1
    Connect-ISC
    ./Test-ManagerGraph.ps1 -SourceName "Acme HR - Karima"

.NOTES
    Exits 1 if the graph is not sound. Read-only.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceName,
    [int]$ExpectedRootCount = 1
)

$ErrorActionPreference = 'Stop'

if (-not $H) {
    throw "Not authenticated. Dot-source isc-env.ps1 and run Connect-ISC first."
}

$src      = Get-ISCSource -Name $SourceName
$accounts = Get-ISCAccounts -SourceId $src.id
$ids      = @($accounts.identityId | Where-Object { $_ } | Select-Object -Unique)

Write-Host "Source:     $($src.name)"
Write-Host "Identities: $($ids.Count)"
Write-Host ""

$report = foreach ($id in $ids) {
    try {
        $identity = Invoke-RestMethod -Headers $H -Uri "$base/beta/identities/$id"
    }
    catch {
        [pscustomobject]@{
            who = "(unreadable identity $id)"; manager = $null; foreign = $false; error = $true
        }
        continue
    }

    [pscustomobject]@{
        who     = $identity.attributes.displayName
        manager = $identity.managerRef.name
        foreign = [bool]($identity.managerRef -and $identity.managerRef.id -notin $ids)
        error   = $false
    }
}

$noManager = @($report | Where-Object { -not $_.manager -and -not $_.error })
$foreign   = @($report | Where-Object { $_.foreign })
$unread    = @($report | Where-Object { $_.error })

Write-Host ("no manager:      {0}" -f $noManager.Count)
Write-Host ("foreign manager: {0}" -f $foreign.Count)
if ($unread.Count) { Write-Host ("unreadable:      {0}" -f $unread.Count) }
Write-Host ""

if ($noManager) {
    Write-Host "Identities with no manager:"
    $noManager | ForEach-Object { Write-Host "  $($_.who)" }
    Write-Host ""
}

if ($foreign) {
    Write-Host "Identities whose manager is outside this population:"
    $foreign | ForEach-Object { Write-Host "  $($_.who) -> $($_.manager)" }
    Write-Host ""
}

$ok = ($noManager.Count -eq $ExpectedRootCount) -and
      ($foreign.Count -eq 0) -and
      ($unread.Count -eq 0)

if (-not $ok) {
    Write-Host "FAIL  expected exactly $ExpectedRootCount identity with no manager and no foreign references."
    exit 1
}

Write-Host "PASS  manager graph is sound."
exit 0
