<#
.SYNOPSIS
    Finds activities where Activity_Status.date_time_earliest does not match
    Activity_SLA.datetime_start, filtered to activities at or above a status threshold.

.PARAMETER InputPath
    Path to the dsScheduleData XML export.

.PARAMETER StatusThreshold
    Minimum status_id to include. Each activity's "current" status is the
    Activity_Status entry with the latest write time (date_time_stamp), not the
    highest status_id, since status can revert (e.g. a committed job pulled back
    off schedule drops from 30 back to 0).
    Default 30.

.PARAMETER OutputPath
    Path for the output markdown file. Default is alongside the input file.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Find-ActivityStatusSlaMismatch.ps1 -InputPath .\aug26north.xml
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [int]$StatusThreshold = 30,

    [string]$OutputPath
)

if (-not (Test-Path $InputPath)) {
    throw "Input file not found: $InputPath"
}

if (-not $OutputPath) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $dir  = [System.IO.Path]::GetDirectoryName((Resolve-Path $InputPath))
    $OutputPath = Join-Path $dir "$base`_status_sla_mismatches.md"
}

$statusByActivity = @{}
$slaByActivity    = @{}

$fileInfo   = Get-Item (Resolve-Path $InputPath)
$fileLength = $fileInfo.Length

Write-Host "Opening file: $($fileInfo.Name) ($([math]::Round($fileLength / 1MB, 1)) MB)"

$stream = [System.IO.File]::OpenRead($fileInfo.FullName)

$settings = New-Object System.Xml.XmlReaderSettings
$settings.IgnoreWhitespace = $true
$reader = [System.Xml.XmlReader]::Create($stream, $settings)

$statusRecCount = 0
$slaRecCount    = 0
$recordCount    = 0

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$progressIntervalMs = 250

Write-Host "Streaming Activity_Status and Activity_SLA records..."

try {
    # NOTE: ReadOuterXml() already advances the reader to the next node when it
    # returns, so this loop must NOT unconditionally call Read() on every pass -
    # doing so double-advances and silently skips every other matched record.
    # Only call Read() explicitly when the current node was NOT consumed by
    # ReadOuterXml().
    if (-not $reader.Read()) {
        Write-Host "Empty file or no content."
    }

    while ($reader.NodeType -ne [System.Xml.XmlNodeType]::None) {
        if ($sw.ElapsedMilliseconds -ge $progressIntervalMs) {
            $percent = [math]::Min(100, [math]::Round(($stream.Position / $fileLength) * 100, 1))
            Write-Progress -Activity "Parsing $($fileInfo.Name)" `
                -Status "$percent% - $recordCount records ($statusRecCount status, $slaRecCount SLA)" `
                -PercentComplete $percent
            $sw.Restart()
        }

        if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and
            ($reader.Name -eq 'Activity_Status' -or $reader.Name -eq 'Activity_SLA')) {

            $tag = $reader.Name

            # ReadOuterXml grabs the whole element (start tag through end tag) as a
            # self-contained string and advances the reader past it in one step.
            [xml]$fragment = $reader.ReadOuterXml()

            $rec = @{}
            foreach ($child in $fragment.DocumentElement.ChildNodes) {
                if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                    $rec[$child.Name] = $child.InnerText
                }
            }

            $aid = $rec['activity_id']
            if ($null -ne $aid) {
                if ($tag -eq 'Activity_Status') {
                    if (-not $statusByActivity.ContainsKey($aid)) {
                        $statusByActivity[$aid] = New-Object System.Collections.Generic.List[hashtable]
                    }
                    $statusByActivity[$aid].Add($rec)
                    $statusRecCount++
                }
                else {
                    if (-not $slaByActivity.ContainsKey($aid)) {
                        $slaByActivity[$aid] = New-Object System.Collections.Generic.List[hashtable]
                    }
                    $slaByActivity[$aid].Add($rec)
                    $slaRecCount++
                }
            }

            $recordCount++
            # Do NOT call $reader.Read() here - ReadOuterXml already moved us to
            # the next node.
        }
        else {
            if (-not $reader.Read()) { break }
        }
    }
}
finally {
    $reader.Close()
    $stream.Close()
    Write-Progress -Activity "Parsing $($fileInfo.Name)" -Completed
}

Write-Host "Parse complete: $recordCount records ($statusRecCount Activity_Status, $slaRecCount Activity_SLA)"
Write-Host "Unique activities with status: $($statusByActivity.Count)"
Write-Host "Unique activities with SLA: $($slaByActivity.Count)"

Write-Host "Evaluating activities at status >= $StatusThreshold..."

$results       = New-Object System.Collections.Generic.List[object]
$missingSla    = New-Object System.Collections.Generic.List[string]
$missingEarly  = New-Object System.Collections.Generic.List[string]
$statusCount   = 0

foreach ($aid in $statusByActivity.Keys) {
    $entries = $statusByActivity[$aid]
    # "Current" status = the audit-trail entry with the latest write time, NOT the
    # highest status_id. Status can revert (e.g. 30 -> 0 when a job is pulled off
    # schedule), so sorting by status_id picks a stale high-water mark instead of
    # what's actually current.
    #
    # Ties on date_time_stamp happen (second-level precision, multiple writes in
    # the same second). Sort-Object's tie-break behavior on -Descending isn't
    # guaranteed consistent, so break ties explicitly here: walk the entries in
    # file/append order and keep the LAST one seen at the max timestamp, since
    # append order reflects true event order even when the timestamp can't.
    $cur = $null
    $curTs = ''
    foreach ($e in $entries) {
        $t = if ($e['date_time_stamp']) { $e['date_time_stamp'] } else { $e['date_time_status'] }
        if ($null -eq $cur -or $t -ge $curTs) {
            $cur = $e
            $curTs = $t
        }
    }
    $statusId = [int]$cur.status_id

    if ($statusId -lt $StatusThreshold) { continue }
    $statusCount++

    if (-not $slaByActivity.ContainsKey($aid)) {
        $missingSla.Add($aid)
        continue
    }

    $dte = $cur['date_time_earliest']
    if (-not $dte) {
        $missingEarly.Add($aid)
        continue
    }

    $slaStart = $slaByActivity[$aid][0]['datetime_start']

    if ($dte -ne $slaStart) {
        $results.Add([pscustomobject]@{
            ActivityId       = [int]$aid
            Status           = $statusId
            DateTimeEarliest = $dte
            SlaStart         = $slaStart
        })
    }
}

$results = $results | Sort-Object ActivityId

Write-Host "Found $($results.Count) mismatches out of $statusCount activities at status >= $StatusThreshold"
Write-Host "Writing output to: $OutputPath"

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# Activities with Status >= $StatusThreshold where Date/Time Earliest != SLA Start")
[void]$md.AppendLine("")
[void]$md.AppendLine("Source: $InputPath")
[void]$md.AppendLine("")
[void]$md.AppendLine("Activities at or above status $StatusThreshold : $statusCount")
[void]$md.AppendLine("Mismatches: $($results.Count)")
if ($missingSla.Count -gt 0) {
    [void]$md.AppendLine("Missing SLA entirely: $($missingSla.Count) ($($missingSla -join ', '))")
}
if ($missingEarly.Count -gt 0) {
    [void]$md.AppendLine("Missing date_time_earliest: $($missingEarly.Count) ($($missingEarly -join ', '))")
}
[void]$md.AppendLine("")
[void]$md.AppendLine("| Activity ID | Status | Date/Time Earliest | SLA Start |")
[void]$md.AppendLine("|---|---|---|---|")
foreach ($r in $results) {
    [void]$md.AppendLine("| $($r.ActivityId) | $($r.Status) | $($r.DateTimeEarliest) | $($r.SlaStart) |")
}

# UTF-8 with BOM for Windows codepage safety
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($OutputPath, $md.ToString(), $utf8Bom)

Write-Host "Done."