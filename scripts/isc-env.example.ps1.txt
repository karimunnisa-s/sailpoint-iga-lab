# isc-env.example.ps1
#
# Copy to isc-env.ps1, fill in the values, and dot-source it before running
# anything else in this folder:
#
#   . ./isc-env.ps1
#
# isc-env.ps1 holds a live client secret and is excluded by .gitignore.
# Only this example file belongs in version control.

$base = "https://YOUR-TENANT.api.identitynow.com"
$cid  = "PASTE_PAT_CLIENT_ID"
$csec = "PASTE_PAT_CLIENT_SECRET"

function Connect-ISC {
    <#
    .SYNOPSIS
        Authenticates to the ISC API and sets $TOKEN and $H for later calls.
    .DESCRIPTION
        ISC expects client_credentials in the query string rather than the body;
        sending them in the body returns {"error":"JWT is required"}, which is
        misleading enough to be worth this note.

        Tokens last about an hour. Re-run this when a call returns "JWT expired".
    #>
    [CmdletBinding()]
    param()

    if (-not $base -or -not $cid -or -not $csec) {
        throw "Set `$base, `$cid and `$csec before calling Connect-ISC."
    }

    $uri = "$base/oauth/token?grant_type=client_credentials" +
           "&client_id=$cid&client_secret=$csec"

    try {
        $tok = Invoke-RestMethod -Method Post -Uri $uri -ErrorAction Stop
    }
    catch {
        throw "Authentication failed: $($_.Exception.Message)"
    }

    $script:TOKEN = $tok.access_token
    $script:H     = @{ Authorization = "Bearer $($tok.access_token)" }

    "Connected. Token expires in $($tok.expires_in)s."
}

function Get-ISCSource {
    <#
    .SYNOPSIS
        Finds a source by exact name, paging through all sources.
    .DESCRIPTION
        A shared tenant can hold more than 250 sources. The default page size
        silently truncates, so a source that exists appears to be missing —
        this pages until a short page comes back.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $all = @(); $offset = 0
    do {
        $page = Invoke-RestMethod -Uri "$base/v3/sources?limit=250&offset=$offset" -Headers $H
        $all += $page
        $offset += 250
    } while ($page.Count -eq 250)

    $match = $all | Where-Object { $_.name -eq $Name }

    if (-not $match)            { throw "No source named '$Name' (searched $($all.Count))." }
    if ($match.Count -gt 1)     { throw "More than one source named '$Name'." }

    $match
}

function Get-ISCAccounts {
    <#
    .SYNOPSIS
        Returns every account on a source, paging through results.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceId
    )

    $filter = [uri]::EscapeDataString("sourceId eq `"$SourceId`"")
    $all = @(); $offset = 0
    do {
        $page = Invoke-RestMethod -Headers $H `
                  -Uri "$base/v3/accounts?limit=250&offset=$offset&filters=$filter"
        $all += $page
        $offset += 250
    } while ($page.Count -eq 250)

    $all
}
