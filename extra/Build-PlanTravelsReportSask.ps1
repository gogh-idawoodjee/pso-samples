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

    Output is written as CSV (opens directly in Excel, double-click it).

    Each row also includes a ready-to-click Google Maps directions link
    between the two geocoded points -- this is just a URL (no API call, no
    cost), so it's a free sanity-check a human can click to eyeball the route
    without needing the Routes API validation pass. It lands as plain text
    in the CSV; select the column in Excel and use Insert > Hyperlink (or a
    HYPERLINK() formula column) if you want it clickable.

.PARAMETER InputXmlPath
    Path to the dsScheduleData XML export.

.PARAMETER Date
    The date to filter to, format yyyy-MM-dd (e.g. "2026-08-13"). Filters on
    the DATE portion of Plan_Travel.start_time, which is UTC in this file.

.PARAMETER OutputPath
    Base output path WITHOUT extension, e.g. ".\aug13_plan_travels" - the
    script appends .csv.

.PARAMETER BuildImportXml
    Switch. If passed, also writes a second file: an import-ready XML
    containing only a specific subset of entity types (see KeepElements
    below), everything else stripped out. Named after the INPUT file (not
    OutputPath) with "_import.xml" appended -- e.g. "aug13north(1).xml" in
    produces "aug13north(1)_import.xml" alongside the CSV. Off by default
    since it's the slower of the two steps on a large file; only pays the
    cost when you actually need the filtered file.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Build-PlanTravelsReport.ps1 -InputXmlPath ".\aug13north.xml" -Date "2026-08-13" -OutputPath ".\aug13_plan_travels"

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Build-PlanTravelsReport.ps1 -InputXmlPath ".\aug13north.xml" -Date "2026-08-13" -OutputPath ".\aug13_plan_travels" -BuildImportXml
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputXmlPath,

    [Parameter(Mandatory = $true)]
    [string]$Date,

    [string]$OutputPath = ".\plan_travels_output",

    [switch]$BuildImportXml
)

# Entity types kept in the filtered "_import.xml" companion file -- everything
# else under <dsScheduleData> is dropped. Edit this list if the required
# entity set changes.
$KeepElements = @(
    'Activity',
    'Activity_Custom_URL',
    'Additional_Attribute',
    'Input_Reference',
    'Location',
    'Location_Region',
    'Region',
    'Resource_Preference',
    'Resource_Region',
    'Resource_Region_Availability',
    'Resource_Skill',
    'Resource_Skill_Availability',
    'Resource_Type',
    'Resources',
    'Shift',
    'Shift_Break',
    'Shift_Type',
    'Skill',
    'SLA_Type'
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
# 1b. Build the filtered "_import.xml" companion file -- a copy of the
#     dsScheduleData document containing ONLY the entity types in
#     $KeepElements, everything else stripped out. Named after the INPUT
#     file, not -OutputPath, per requirement. Only runs if -BuildImportXml
#     is passed.
#
#     Uses a compiled (Add-Type/C#) streaming XmlReader/XmlWriter pass
#     instead of DOM + ImportNode -- same approach as the fast
#     Remove-AvailabilityElements script, just inverted to a whitelist and
#     scoped to depth 1 (direct children of the root) so a same-named
#     element nested inside a kept entity is never mistakenly stripped.
# ---------------------------------------------------------------------------
if ($BuildImportXml) {
    Write-Log "-BuildImportXml passed -- also building the filtered import XML..."
    $inputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($InputXmlPath)
    $outputDir = Split-Path -Path "$OutputPath.csv" -Parent
    if ([string]::IsNullOrEmpty($outputDir)) { $outputDir = "." }
    $importXmlPath = Join-Path -Path $outputDir -ChildPath "$($inputBaseName)_import.xml"

    $csharpSource = @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Xml;

public static class XmlKeepOnlyFilter
{
    // Keeps only elements in targetNames that appear at depth 1 (i.e. direct
    // children of the root element). Everything else at depth 1 is dropped
    // (reader.Skip() over the whole subtree). Elements at any other depth
    // are never filtered -- they just get copied through as part of
    // whichever depth-1 element they belong to.
    public static Dictionary<string, long> KeepOnly(string inputPath, string outputPath, string[] targetNames)
    {
        var targets = new HashSet<string>(targetNames, StringComparer.Ordinal);
        var counts = new Dictionary<string, long>(StringComparer.Ordinal);

        var readerSettings = new XmlReaderSettings();
        readerSettings.DtdProcessing = DtdProcessing.Parse;
        readerSettings.IgnoreWhitespace = false;

        var writerSettings = new XmlWriterSettings();
        writerSettings.Indent = true;
        writerSettings.Encoding = new UTF8Encoding(false);

        int depth = 0;

        using (XmlReader reader = XmlReader.Create(inputPath, readerSettings))
        using (XmlWriter writer = XmlWriter.Create(outputPath, writerSettings))
        {
            while (reader.Read())
            {
                if (reader.NodeType == XmlNodeType.Element && depth == 1 && !targets.Contains(reader.LocalName))
                {
                    string name = reader.LocalName;
                    long current;
                    counts.TryGetValue(name, out current);
                    counts[name] = current + 1;
                    reader.Skip();
                    continue;
                }

                switch (reader.NodeType)
                {
                    case XmlNodeType.Element:
                        writer.WriteStartElement(reader.Prefix, reader.LocalName, reader.NamespaceURI);
                        if (reader.HasAttributes)
                        {
                            for (int i = 0; i < reader.AttributeCount; i++)
                            {
                                reader.MoveToAttribute(i);
                                writer.WriteAttributeString(reader.Prefix, reader.LocalName, reader.NamespaceURI, reader.Value);
                            }
                            reader.MoveToElement();
                        }
                        if (reader.IsEmptyElement)
                        {
                            writer.WriteEndElement();
                        }
                        else
                        {
                            depth++;
                        }
                        break;
                    case XmlNodeType.Text:
                        writer.WriteString(reader.Value);
                        break;
                    case XmlNodeType.CDATA:
                        writer.WriteCData(reader.Value);
                        break;
                    case XmlNodeType.ProcessingInstruction:
                        if (reader.Name != "xml")
                            writer.WriteProcessingInstruction(reader.Name, reader.Value);
                        break;
                    case XmlNodeType.Comment:
                        writer.WriteComment(reader.Value);
                        break;
                    case XmlNodeType.Whitespace:
                    case XmlNodeType.SignificantWhitespace:
                        writer.WriteWhitespace(reader.Value);
                        break;
                    case XmlNodeType.EndElement:
                        writer.WriteFullEndElement();
                        depth--;
                        break;
                    case XmlNodeType.DocumentType:
                        writer.WriteDocType(reader.Name, reader.GetAttribute("PUBLIC"), reader.GetAttribute("SYSTEM"), reader.Value);
                        break;
                    default:
                        break;
                }
            }
            writer.Flush();
        }

        return counts;
    }
}
'@

    Add-Type -TypeDefinition $csharpSource -Language CSharp -ReferencedAssemblies @(
        'System.Xml.dll',
        'System.Xml.ReaderWriter.dll',
        'mscorlib.dll',
        'System.dll'
    )

    Write-Log "Building filtered import XML (compiled streaming pass, keeping only: $($KeepElements -join ', '))..."
    $importSw = [System.Diagnostics.Stopwatch]::StartNew()

    $droppedCounts = [XmlKeepOnlyFilter]::KeepOnly($InputXmlPath, $importXmlPath, [string[]]$KeepElements)

    $importSw.Stop()

    Write-Log "  Import XML written to $importXmlPath (in $([math]::Round($importSw.Elapsed.TotalSeconds, 1))s)"
    if ($droppedCounts.Count -eq 0) {
        Write-Log "  Nothing dropped -- every top-level element was already in the keep list."
    }
    else {
        $totalDropped = 0
        foreach ($key in $droppedCounts.Keys) {
            Write-Log ("    Dropped {0,-32} {1}" -f $key, $droppedCounts[$key])
            $totalDropped += $droppedCounts[$key]
        }
        Write-Log "  Dropped $totalDropped element(s) total (not in keep list)."
    }
}
else {
    Write-Log "Skipping filtered import XML (pass -BuildImportXml to also produce it)."
}

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
# 3b. Helper: build a free Google Maps directions link (no API call/cost --
#     just a deep-link URL a human can click to eyeball the route)
# ---------------------------------------------------------------------------
function Get-GoogleMapsDirectionsLink {
    param(
        [Nullable[double]]$OriginLat,
        [Nullable[double]]$OriginLon,
        [Nullable[double]]$DestLat,
        [Nullable[double]]$DestLon
    )
    if ($null -eq $OriginLat -or $null -eq $OriginLon -or $null -eq $DestLat -or $null -eq $DestLon) {
        return $null
    }
    $origin = "{0},{1}" -f $OriginLat, $OriginLon
    $dest   = "{0},{1}" -f $DestLat, $DestLon
    return "https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$dest&travelmode=driving"
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

    $originLat = if ($startLoc) { $startLoc.Lat } else { $null }
    $originLon = if ($startLoc) { $startLoc.Lon } else { $null }
    $destLat   = if ($endLoc)   { $endLoc.Lat }   else { $null }
    $destLon   = if ($endLoc)   { $endLoc.Lon }   else { $null }

    $mapsLink = Get-GoogleMapsDirectionsLink -OriginLat $originLat -OriginLon $originLon -DestLat $destLat -DestLon $destLon

    # ---- EDIT HERE: this is the full set of available fields per row ----
    $row = [PSCustomObject]@{
        'Resource ID'                = $resourceId
        'Resource Name'              = $resourceLookup[$resourceId]
        'Direction'                  = $direction
        'Previous Activity ID'       = $previousActivityId
        'Activity ID (Destination)'  = $activityId
        'Activity Type'              = if ($act) { $act.TypeId } else { $null }
        'Activity Description'      = if ($act) { $act.Description } else { $null }
        'Start Location Latitude'    = $originLat
        'Start Location Longitude'   = $originLon
        'End Location Latitude'      = $destLat
        'End Location Longitude'     = $destLon
        'Distance (km)'              = $distanceKm
        'Expected Travel Time (sec)' = $travelSeconds
        'Google Maps Directions Link' = $mapsLink
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
#    Wrapped with retry in case a leftover process still has this exact file
#    locked from a previous run.
# ---------------------------------------------------------------------------
$csvPath = "$OutputPath.csv"
Write-Log "Writing CSV to $csvPath ..."

$maxAttempts = 5
$attempt = 0
$csvWritten = $false
while (-not $csvWritten -and $attempt -lt $maxAttempts) {
    $attempt++
    try {
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        $csvWritten = $true
    }
    catch {
        if ($attempt -ge $maxAttempts) {
            Write-Error "Could not write $csvPath after $maxAttempts attempts -- it's likely locked by another process. Error: $($_.Exception.Message)"
            exit 1
        }
        Write-Log "  $csvPath appears locked (attempt $attempt of $maxAttempts) -- retrying in 2s..."
        Start-Sleep -Seconds 2
    }
}
Write-Log "  CSV written. This opens directly in Excel (double-click it)."
Write-Log "  Google Maps links are in a plain text column -- select the column in Excel and use Insert > Hyperlink, or wrap it in a HYPERLINK() formula column, if you want them clickable."

Write-Log "=== Done ==="