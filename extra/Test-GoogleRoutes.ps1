<#
.SYNOPSIS
    Validates travel legs from Build-PlanTravelsReport.ps1 output against
    Google Maps Routes API (computeRoutes), and flags legs where PSO's
    reported travel time diverges from Google's.

        
.DESCRIPTION
    Reads the CSV produced by Build-PlanTravelsReport.ps1 directly (same
    column names, no reshaping needed). For each row with valid start/end
    coordinates, calls the Routes API and compares the result against the
    'Expected Travel Time (sec)' column already in the report. Appends the
    Google result, a divergence ratio/flag, and (for flagged legs) an
    estimated Area Weighting value onto each row.

    No external modules required -- Invoke-RestMethod is built into
    PowerShell 5.1+, so this runs on the same locked-down machines
    Build-PlanTravelsReport.ps1 was designed for.

.PARAMETER InputCsv
    Path to the CSV produced by Build-PlanTravelsReport.ps1
    (e.g. ".\aug13_plan_travels.csv").

.PARAMETER OutputCsv
    Path to write the validated results.

.PARAMETER ApiKey
    Google Maps Routes API key. Pass at runtime -- do not hardcode.

.PARAMETER DivergenceThresholdPercent
    Percent difference between PSO's expected travel time and Google's
    duration above which a leg is flagged "Review". Default 20.

    Set your Google Maps API Key using an environment variable [System.Environment]::SetEnvironmentVariable("GOOGLE_MAPS_API_KEY", "your-new-key-here", "User")

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-GoogleRoutes.ps1 `
        -InputCsv ".\aug13_plan_travels.csv" `
        -OutputCsv ".\aug13_plan_travels_validated.csv" `
        -ApiKey $env:GOOGLE_MAPS_API_KEY
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputCsv,

    [Parameter(Mandatory = $true)]
    [string]$OutputCsv,

    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [string]$TravelMode = "DRIVE",
    [string]$RoutingPreference = "TRAFFIC_UNAWARE",  # matches HTM's static-model comparison; PSO has no live-traffic input
    [int]$RequestDelayMs = 150,
    [double]$DivergenceThresholdPercent = 20
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $Message"
}

# ---------------------------------------------------------------------------
# 1. Load input
# ---------------------------------------------------------------------------
Write-Log "=== Google Routes Validation script starting ==="

if (-not (Test-Path $InputCsv)) {
    Write-Error "Input CSV not found: $InputCsv"
    exit 1
}

$rows = Import-Csv -Path $InputCsv
Write-Log "Loaded $($rows.Count) rows from $InputCsv"

$requiredCols = @(
    'Start Location Latitude', 'Start Location Longitude',
    'End Location Latitude', 'End Location Longitude'
)
$actualCols = $rows[0].PSObject.Properties.Name
foreach ($c in $requiredCols) {
    if ($actualCols -notcontains $c) {
        Write-Error "Expected column '$c' not found in input CSV. Is this a Build-PlanTravelsReport.ps1 output file?"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 2. Call Routes API per row
# ---------------------------------------------------------------------------
$endpoint = "https://routes.googleapis.com/directions/v2:computeRoutes"
$fieldMask = "routes.duration,routes.distanceMeters"

$headers = @{
    "Content-Type"     = "application/json"
    "X-Goog-Api-Key"   = $ApiKey
    "X-Goog-FieldMask" = $fieldMask
}

$results = New-Object System.Collections.Generic.List[Object]
$total = $rows.Count
$i = 0
$skipped = 0
$flagged = 0

foreach ($row in $rows) {
    $i++
    $label = "$($row.'Resource ID') / $($row.'Activity ID (Destination)')"
    Write-Progress -Activity "Validating travel legs" -Status "$i of $total ($label)" -PercentComplete (($i / $total) * 100)

    $startLat = $null; $startLon = $null; $endLat = $null; $endLon = $null
    $hasCoords = [double]::TryParse($row.'Start Location Latitude', [ref]$startLat) -and
                 [double]::TryParse($row.'Start Location Longitude', [ref]$startLon) -and
                 [double]::TryParse($row.'End Location Latitude', [ref]$endLat) -and
                 [double]::TryParse($row.'End Location Longitude', [ref]$endLon)

    $googleDurationSec = $null
    $googleDistanceKm  = $null
    $errorMsg          = $null

    if (-not $hasCoords) {
        $errorMsg = "Missing/invalid coordinates -- skipped"
        $skipped++
    }
    else {
        $body = @{
            origin      = @{ location = @{ latLng = @{ latitude = $startLat; longitude = $startLon } } }
            destination = @{ location = @{ latLng = @{ latitude = $endLat;   longitude = $endLon } } }
            travelMode        = $TravelMode
            routingPreference = $RoutingPreference
            units             = "METRIC"
        } | ConvertTo-Json -Depth 10

        try {
            $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -Body $body

            if ($response.routes -and $response.routes.Count -gt 0) {
                $route = $response.routes[0]
                $googleDurationSec = [int]($route.duration -replace 's$', '')
                $googleDistanceKm  = [math]::Round($route.distanceMeters / 1000, 2)
            }
            else {
                $errorMsg = "No route returned"
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
        }

        Start-Sleep -Milliseconds $RequestDelayMs
    }

    # --- Compare against PSO's Expected Travel Time (sec), already in the report ---
    $psoSeconds = $null
    [double]::TryParse($row.'Expected Travel Time (sec)', [ref]$psoSeconds) | Out-Null

    $ratio             = $null
    $percentDivergence = $null
    $flag              = "N/A"
    $estimatedWeighting = $null

    if ($googleDurationSec -and $psoSeconds -and $psoSeconds -gt 0) {
        $ratio = [math]::Round($googleDurationSec / $psoSeconds, 3)
        $percentDivergence = [math]::Round(($ratio - 1) * 100, 1)
        if ([math]::Abs($percentDivergence) -ge $DivergenceThresholdPercent) {
            $flag = "Review"
            $flagged++
            # Estimated weighting to configure in PSO's Area Weighting field --
            # same value as the ratio (Actual/Calculated = Google/PSO), just
            # rounded to 2dp to match the convention used elsewhere (Area
            # Editor weighting values). Only populated on flagged legs --
            # an "OK" leg implies a weighting of ~1, nothing to configure.
            $estimatedWeighting = [math]::Round($ratio, 2)
        }
        else {
            $flag = "OK"
        }
    }
    elseif ($errorMsg) {
        $flag = "Skipped"
    }
    else {
        $flag = "Missing PSO Time"
    }

    # --- Append Google + divergence columns onto the original row ---
    $outRow = [ordered]@{}
    foreach ($p in $row.PSObject.Properties) { $outRow[$p.Name] = $p.Value }
    $outRow['Google Duration (min)']          = if ($googleDurationSec) { [math]::Round($googleDurationSec / 60, 1) } else { $null }
    $outRow['Google Distance (km)']           = $googleDistanceKm
    $outRow['PSO Duration (min)']             = if ($psoSeconds) { [math]::Round($psoSeconds / 60, 1) } else { $null }
    $outRow['Ratio (Google / PSO)']           = $ratio
    $outRow['% Divergence']                   = $percentDivergence
    $outRow['Flag']                           = $flag
    $outRow['Estimated Weighting Adjustment'] = $estimatedWeighting
    $outRow['Validation Error']               = $errorMsg

    $results.Add([PSCustomObject]$outRow)
}

# ---------------------------------------------------------------------------
# 3. Write output
# ---------------------------------------------------------------------------
$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Log "  Total rows:          $total"
Write-Log "  Skipped (no coords): $skipped"
Write-Log "  Flagged for review:  $flagged (>= $DivergenceThresholdPercent% divergence)"
Write-Log "Output written to $OutputCsv"
Write-Log "=== Done ==="