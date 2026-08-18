<#
.SYNOPSIS
    Parses a PSO dsScheduleData XML export and builds the "plan travels" table:
    only travels moving TO an activity (from a resource start location OR from
    another activity), excluding any leg where either end (destination OR
    origin) touches a PRIVATE activity_class_id or a NON-AVAILABILITY
    activity_type_id, filtered to a single date.

.DESCRIPTION
    No external modules required (no ImportExcel, no Python) - uses only
    PowerShell's built-in [xml] type, so this will run on a locked-down
    corporate machine with nothing installed beyond PowerShell itself.

    Output is written as CSV by default (guaranteed to work everywhere, opens
    directly in Excel). If Excel is actually installed on the machine, the
    script will ALSO try to save a true .xlsx via COM automation - if that
    fails for any reason (Excel not installed, COM blocked by policy, etc.)
    it just skips that step silently and you still have the CSV.

.PARAMETER InputXmlPath
    Path to the dsScheduleData XML export.

.PARAMETER Date
    The date to filter to, format yyyy-MM-dd (e.g. "2026-08-13"). Filters on
    the DATE portion of Plan_Travel.start_time, which is UTC in this file.

.PARAMETER OutputPath
    Base output path WITHOUT extension, e.g. ".\aug13_plan_travels" - the
    script appends .csv (always) and .xlsx (if Excel COM automation works).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Build-PlanTravelsReport.ps1 -InputXmlPath ".\aug13north(1).xml" -Date "2026-08-13" -OutputPath ".\aug13_plan_travels"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputXmlPath,

    [Parameter(Mandatory = $true)]
    [string]$Date,

    [string]$OutputPath = ".\plan_travels_output"
)

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] $Message"
}

# ---------------------------------------------------------------------------
# 1. Load and validate input
# ---------------------------------------------------------------------------
Write-Log "=== Plan Travels Report script starting ==="

if (-not (Test-Path $InputXmlPath)) {
    Write-Error "Input file not found: $InputXmlPath"
    exit 1
}

Write-Log "Loading XML from $InputXmlPath (this can take a few seconds for large files)..."
[xml]$xml = Get-Content -Path $InputXmlPath -Raw
$root = $xml.dsScheduleData

if ($null -eq $root) {
    Write-Error "Could not find root <dsScheduleData> element - is this the right file?"
    exit 1
}

$activityNodes  = @($root.Activity)
$locationNodes  = @($root.Location)
$resourceNodes  = @($root.Resources)
$travelNodes    = @($root.Plan_Travel)

Write-Log "  Activities:   $($activityNodes.Count)"
Write-Log "  Locations:    $($locationNodes.Count)"
Write-Log "  Resources:    $($resourceNodes.Count)"
Write-Log "  Plan_Travel:  $($travelNodes.Count)"

# ---------------------------------------------------------------------------
# 2. Build lookup tables
# ---------------------------------------------------------------------------
Write-Log "Building Activity lookup (id -> class/type/description)..."
$activityLookup = @{}
foreach ($a in $activityNodes) {
    if ($null -ne $a.id) {
        $activityLookup[[string]$a.id] = @{
            ClassId     = [string]$a.activity_class_id
            TypeId      = [string]$a.activity_type_id
            Description = [string]$a.description
        }
    }
}

Write-Log "Building Location lookup (id -> lat/long)..."
$locationLookup = @{}
foreach ($l in $locationNodes) {
    if ($null -ne $l.id) {
        $lat = $null; $lon = $null
        if ($l.latitude)  { [void][double]::TryParse($l.latitude, [ref]$lat) }
        if ($l.longitude) { [void][double]::TryParse($l.longitude, [ref]$lon) }
        $locationLookup[[string]$l.id] = @{ Lat = $lat; Lon = $lon }
    }
}

Write-Log "Building Resources lookup (id -> name)..."
$resourceLookup = @{}
foreach ($r in $resourceNodes) {
    if ($null -ne $r.id) {
        $name = ("{0} {1}" -f $r.first_name, $r.surname).Trim()
        $resourceLookup[[string]$r.id] = $name
    }
}

# ---------------------------------------------------------------------------
# 3. Helper: is this activity private or non-availability?
# ---------------------------------------------------------------------------
function Test-PrivateOrNonAvailability {
    param([string]$ActivityId)
    if ([string]::IsNullOrEmpty($ActivityId)) { return $false }
    $act = $activityLookup[$ActivityId]
    if ($null -eq $act) { return $false }   # can't determine -> don't exclude blindly
    return ($act.ClassId -eq 'PRIVATE') -or ($act.TypeId -eq 'NON-AVAILABILITY')
}

# ---------------------------------------------------------------------------
# 4. Filter + build output rows
#    ---> EDIT THE $Columns BLOCK BELOW TO ADD/REMOVE/REORDER OUTPUT COLUMNS
# ---------------------------------------------------------------------------
Write-Log "Filtering Plan_Travel to date=$Date, direction=(start->activity or activity->activity), excluding private/non-availability on EITHER end..."

$results = New-Object System.Collections.Generic.List[PSCustomObject]
$totalOnDate = 0
$excludedDestination = 0
$excludedOrigin = 0

foreach ($pt in $travelNodes) {

    $startTime = [string]$pt.start_time
    if ([string]::IsNullOrEmpty($startTime) -or -not $startTime.StartsWith($Date)) {
        continue
    }
    $totalOnDate++

    $activityId          = [string]$pt.activity_id            # destination
    $previousActivityId  = [string]$pt.previous_activity_id   # origin (if activity->activity)

    # must be moving TO an activity (destination present)
    if ([string]::IsNullOrEmpty($activityId)) {
        continue
    }

    # exclude if destination is private/non-availability
    if (Test-PrivateOrNonAvailability -ActivityId $activityId) {
        $excludedDestination++
        continue
    }

    # exclude if origin (previous activity) is private/non-availability
    if (-not [string]::IsNullOrEmpty($previousActivityId) -and (Test-PrivateOrNonAvailability -ActivityId $previousActivityId)) {
        $excludedOrigin++
        continue
    }

    $act        = $activityLookup[$activityId]
    $startLoc   = $locationLookup[[string]$pt.start_location_id]
    $endLoc     = $locationLookup[[string]$pt.end_location_id]
    $resourceId = [string]$pt.resource_id

    $direction  = if ([string]::IsNullOrEmpty($previousActivityId)) { 'Start Location -> Activity' } else { 'Activity -> Activity' }

    $distanceKm = $null
    if ($pt.distance) {
        $distanceKm = [math]::Round(([double]$pt.distance) / 1000, 2)
    }

    $travelSeconds = $null
    if ($pt.expected_travel_time -match '^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$') {
        $h = if ($matches[1]) { [int]$matches[1] } else { 0 }
        $m = if ($matches[2]) { [int]$matches[2] } else { 0 }
        $s = if ($matches[3]) { [int]$matches[3] } else { 0 }
        $travelSeconds = ($h * 3600) + ($m * 60) + $s
    }

    # ---- EDIT HERE: this is the full set of available fields per row ----
    $row = [PSCustomObject]@{
        'Resource ID'                = $resourceId
        'Resource Name'              = $resourceLookup[$resourceId]
        'Direction'                  = $direction
        'Previous Activity ID'       = $previousActivityId
        'Activity ID (Destination)'  = $activityId
        'Activity Type'              = if ($act) { $act.TypeId } else { $null }
        'Activity Description'      = if ($act) { $act.Description } else { $null }
        'Start Location Latitude'    = if ($startLoc) { $startLoc.Lat } else { $null }
        'Start Location Longitude'   = if ($startLoc) { $startLoc.Lon } else { $null }
        'End Location Latitude'      = if ($endLoc) { $endLoc.Lat } else { $null }
        'End Location Longitude'     = if ($endLoc) { $endLoc.Lon } else { $null }
        'Distance (km)'              = $distanceKm
        'Expected Travel Time (sec)' = $travelSeconds
        'Plan ID'                    = [string]$pt.plan_id
    }
    $results.Add($row)
}

Write-Log "  Rows on $($Date): $totalOnDate"
Write-Log "  Excluded (destination private/non-availability): $excludedDestination"
Write-Log "  Excluded (origin private/non-availability):      $excludedOrigin"
Write-Log "  FINAL rows:                                       $($results.Count)"

if ($results.Count -eq 0) {
    Write-Warning "No rows matched the filter - double check the -Date value and that the file actually has data for that day."
    exit 0
}

# sort output (resource, then destination activity)
$results = $results | Sort-Object 'Resource ID', 'Activity ID (Destination)'

# ---------------------------------------------------------------------------
# 5. Write CSV (always works, no dependencies)
# ---------------------------------------------------------------------------
$csvPath = "$OutputPath.csv"
Write-Log "Writing CSV to $csvPath ..."
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Log "  CSV written. This opens directly in Excel (double-click it)."

# ---------------------------------------------------------------------------
# 6. Try to also produce a real .xlsx via Excel COM automation
#    (only works if Excel is actually installed locally - skips cleanly if not)
# ---------------------------------------------------------------------------
$xlsxPath = (Resolve-Path -Path (Split-Path $csvPath -Parent) -ErrorAction SilentlyContinue).Path
$xlsxFullPath = Join-Path -Path (Get-Location) -ChildPath "$OutputPath.xlsx"

Write-Log "Attempting to also save a native .xlsx via Excel COM automation (optional, skips silently if Excel isn't installed)..."
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    $workbook = $excel.Workbooks.Open((Resolve-Path $csvPath).Path)
    $fullXlsxPath = [System.IO.Path]::GetFullPath("$OutputPath.xlsx")
    $workbook.SaveAs($fullXlsxPath, 51)  # 51 = xlOpenXMLWorkbook (.xlsx)
    $workbook.Close($false)
    $excel.Quit()

    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null

    Write-Log "  .xlsx written to $fullXlsxPath"
}
catch {
    Write-Log "  Skipped .xlsx (Excel COM automation not available on this machine: $($_.Exception.Message))"
    Write-Log "  That's fine - the CSV at $csvPath opens fine in Excel anyway."
}

Write-Log "=== Done ==="