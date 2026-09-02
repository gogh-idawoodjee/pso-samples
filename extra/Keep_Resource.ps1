<#
.SYNOPSIS
    Filters an XML file down to a single <Resources> record and every other
    element that belongs to it, dropping everything tied to other resources.
    Every other element type in the file (not resource-linked) is left
    completely untouched.

.DESCRIPTION
    Two-pass streaming approach (fast, low-memory even on large files):

    Pass 1: scans the file once and records:
      - the IDs of <Shift> elements whose <resource_id> matches -ResourceId
      - the <availability_id> of any <Resource_Region_Availability> or
        <Resource_Skill_Availability> element whose <resource_id> matches
        -ResourceId (this is how <Availability> records - which have no
        resource_id of their own - get tied back to a resource)

    Pass 2: streams through the file again and writes it back out:
      - <Resources> is kept only if its <id> equals -ResourceId.
      - <Shift> is kept only if its <resource_id> equals -ResourceId.
      - <Shift_Break> is kept only if its <shift_id> matches one of the
        kept shift IDs from Pass 1.
      - <Availability> is kept only if its <id> matches one of the
        availability IDs collected in Pass 1 (i.e. it's still referenced
        by a kept Resource_Region_Availability or Resource_Skill_Availability
        record). Otherwise it's an orphan and gets dropped.
      - All other resource_id-linked element types below are kept only if
        their <resource_id> equals -ResourceId:
          Resource_Region_Availability, Resource_Skill, Resource_Skill_Availability,
          Resource_Preference, Resource_Region, Plan_Resource, Plan_Route,
          Plan_Break, Plan_Travel, Activity_Status
      - Every other element in the file (anything not in the list above)
        is copied through exactly as-is.

.PARAMETER InputPath
    Path to the source XML file.

.PARAMETER OutputPath
    Path to write the filtered XML file. If omitted, a new file is created
    in the same folder as InputPath, named "<original>.filtered.xml".

.PARAMETER ResourceId
    The id of the single Resources record to keep (e.g. "962").

.EXAMPLE
    .\Filter-ResourceAndShifts.ps1 -InputPath ".\559.xml" -ResourceId "962"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [string]$ResourceId
)

$resolvedInput = Resolve-Path -Path $InputPath -ErrorAction Stop
$InputPath = $resolvedInput.Path

if (-not $OutputPath) {
    $directory = Split-Path -Path $InputPath -Parent
    $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $OutputPath = Join-Path -Path $directory -ChildPath "$baseName.filtered.xml"
    Write-Host "No -OutputPath given; will write filtered copy to:`n  $OutputPath"
}

$typeSuffix = [guid]::NewGuid().ToString('N')
$typeName = "ResourceShiftFilter_$typeSuffix"

$csharpSource = @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using System.Xml.Linq;

public static class $typeName
{
    // Element types kept only if their own <resource_id> matches the target.
    // (Resources, Shift_Break, and Availability are special-cased separately.)
    private static readonly string[] ResourceIdLinkedTypes = new string[]
    {
        "Shift",
        "Resource_Region_Availability",
        "Resource_Skill",
        "Resource_Skill_Availability",
        "Resource_Preference",
        "Resource_Region",
        "Plan_Resource",
        "Plan_Route",
        "Plan_Break",
        "Plan_Travel",
        "Activity_Status"
    };

    // Finds a direct child element by local name, ignoring whatever XML
    // namespace it's actually in (the file may have a default xmlns on
    // the root that XElement.Element("name") would otherwise require).
    private static string GetChildValue(XElement parent, string localName)
    {
        foreach (var child in parent.Elements())
        {
            if (child.Name.LocalName == localName)
                return child.Value;
        }
        return null;
    }

    public static Dictionary<string, long> Run(string inputPath, string outputPath, string resourceId, Action<int, long, long> onProgress)
    {
        resourceId = (resourceId ?? "").Trim().Trim('"', '\'');

        var linkedTypeSet = new HashSet<string>(ResourceIdLinkedTypes, StringComparer.Ordinal);

        var counts = new Dictionary<string, long>(StringComparer.Ordinal);
        var trackedTypes = new List<string>(ResourceIdLinkedTypes);
        trackedTypes.Add("Resources");
        trackedTypes.Add("Shift_Break");
        trackedTypes.Add("Availability");
        foreach (var t in trackedTypes)
        {
            counts[t + "_kept"] = 0;
            counts[t + "_dropped"] = 0;
        }

        var seenResourceIds = new List<string>();
        var keptShiftIds = new HashSet<string>(StringComparer.Ordinal);
        var keptAvailabilityIds = new HashSet<string>(StringComparer.Ordinal);

        var readerSettings = new XmlReaderSettings();
        readerSettings.DtdProcessing = DtdProcessing.Parse;
        readerSettings.IgnoreWhitespace = false;

        // ---------- Pass 1: collect shift IDs and availability IDs belonging to the target resource ----------
        using (FileStream fs1 = new FileStream(inputPath, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, FileOptions.SequentialScan))
        using (XmlReader reader = XmlReader.Create(fs1, readerSettings))
        {
            long totalBytes = fs1.Length;
            long nodeCounter = 0;
            const int progressEveryNNodes = 4000;

            while (reader.Read())
            {
                nodeCounter++;
                if (onProgress != null && nodeCounter % progressEveryNNodes == 0)
                {
                    onProgress(1, fs1.Position, totalBytes);
                }

                if (reader.NodeType != XmlNodeType.Element) continue;
                string localName = reader.LocalName;

                if (localName == "Shift")
                {
                    XElement el = XElement.Load(reader.ReadSubtree());
                    string rid = (GetChildValue(el, "resource_id") ?? "").Trim();
                    string sid = (GetChildValue(el, "id") ?? "").Trim();
                    if (rid == resourceId && sid.Length > 0)
                    {
                        keptShiftIds.Add(sid);
                    }
                }
                else if (localName == "Resource_Region_Availability" || localName == "Resource_Skill_Availability")
                {
                    XElement el = XElement.Load(reader.ReadSubtree());
                    string rid = (GetChildValue(el, "resource_id") ?? "").Trim();
                    string aid = (GetChildValue(el, "availability_id") ?? "").Trim();
                    if (rid == resourceId && aid.Length > 0)
                    {
                        keptAvailabilityIds.Add(aid);
                    }
                }
            }

            if (onProgress != null) onProgress(1, totalBytes, totalBytes);
        }

        // ---------- Pass 2: write filtered output ----------
        var writerSettings = new XmlWriterSettings();
        writerSettings.Indent = true;
        writerSettings.Encoding = new UTF8Encoding(false);

        using (FileStream fs2 = new FileStream(inputPath, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, FileOptions.SequentialScan))
        using (XmlReader reader = XmlReader.Create(fs2, readerSettings))
        using (XmlWriter writer = XmlWriter.Create(outputPath, writerSettings))
        {
            long totalBytes = fs2.Length;
            long nodeCounter = 0;
            const int progressEveryNNodes = 4000;

            while (reader.Read())
            {
                nodeCounter++;
                if (onProgress != null && nodeCounter % progressEveryNNodes == 0)
                {
                    onProgress(2, fs2.Position, totalBytes);
                }

                string name = reader.NodeType == XmlNodeType.Element ? reader.LocalName : null;

                if (name == "Resources")
                {
                    XElement el = XElement.Load(reader.ReadSubtree());
                    string id = (GetChildValue(el, "id") ?? "").Trim();
                    seenResourceIds.Add(id);
                    if (id == resourceId)
                    {
                        el.WriteTo(writer);
                        counts["Resources_kept"]++;
                    }
                    else
                    {
                        counts["Resources_dropped"]++;
                    }
                    continue;
                }

                if (name == "Shift_Break")
                {
                    XElement el = XElement.Load(reader.ReadSubtree());
                    string sid = (GetChildValue(el, "shift_id") ?? "").Trim();
                    if (sid.Length > 0 && keptShiftIds.Contains(sid))
                    {
                        el.WriteTo(writer);
                        counts["Shift_Break_kept"]++;
                    }
                    else
                    {
                        counts["Shift_Break_dropped"]++;
                    }
                    continue;
                }

                if (name == "Availability")
                {
                    XElement el = XElement.Load(reader.ReadSubtree());
                    string id = (GetChildValue(el, "id") ?? "").Trim();
                    if (id.Length > 0 && keptAvailabilityIds.Contains(id))
                    {
                        el.WriteTo(writer);
                        counts["Availability_kept"]++;
                    }
                    else
                    {
                        counts["Availability_dropped"]++;
                    }
                    continue;
                }

                if (name != null && linkedTypeSet.Contains(name))
                {
                    XElement el = XElement.Load(reader.ReadSubtree());
                    string rid = (GetChildValue(el, "resource_id") ?? "").Trim();
                    if (rid == resourceId)
                    {
                        el.WriteTo(writer);
                        counts[name + "_kept"]++;
                    }
                    else
                    {
                        counts[name + "_dropped"]++;
                    }
                    continue;
                }

                // Everything else: copy through exactly as-is.
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
                            writer.WriteEndElement();
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
                        break;
                    case XmlNodeType.DocumentType:
                        writer.WriteDocType(reader.Name, reader.GetAttribute("PUBLIC"), reader.GetAttribute("SYSTEM"), reader.Value);
                        break;
                    default:
                        break;
                }
            }

            if (onProgress != null) onProgress(2, totalBytes, totalBytes);

            writer.Flush();
        }

        if (counts["Resources_kept"] == 0)
        {
            var distinctIds = new List<string>();
            var seenSet = new HashSet<string>(StringComparer.Ordinal);
            foreach (var rid in seenResourceIds)
            {
                if (seenSet.Add(rid) && distinctIds.Count < 15)
                    distinctIds.Add(rid);
            }
            File.WriteAllText(
                outputPath + ".resourceids.txt",
                "Resource IDs found in file (first 15 distinct): " + string.Join(", ", distinctIds)
            );
        }

        return counts;
    }
}
"@

Add-Type -TypeDefinition $csharpSource -Language CSharp -ReferencedAssemblies @(
    'System.Xml.dll',
    'System.Xml.ReaderWriter.dll',
    'System.Xml.Linq.dll',
    'System.Core.dll',
    'mscorlib.dll',
    'System.dll',
    'System.IO.dll'
)

Write-Host "Pass 1/2: scanning for shifts and availability links for resource '$ResourceId'..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$compiledType = [System.AppDomain]::CurrentDomain.GetAssemblies() |
    ForEach-Object { $_.GetType($typeName) } |
    Where-Object { $_ -ne $null } |
    Select-Object -First 1

$runMethod = $compiledType.GetMethod('Run')

# Throttle Write-Progress updates; separate bars for Pass 1 and Pass 2 (Id 1 / Id 2)
# so both show up stacked in the console instead of overwriting each other.
$lastProgressUpdate = @{ 1 = [System.Diagnostics.Stopwatch]::StartNew(); 2 = [System.Diagnostics.Stopwatch]::StartNew() }
$passLabel = @{ 1 = "Pass 1/2: scanning for shift & availability links"; 2 = "Pass 2/2: writing filtered file" }

$progressCallback = [Action[int, long, long]]{
    param($pass, $bytesRead, $totalBytes)
    $timer = $lastProgressUpdate[$pass]
    if ($timer.ElapsedMilliseconds -ge 200 -or $bytesRead -ge $totalBytes) {
        $pct = if ($totalBytes -gt 0) { [Math]::Min(100, [Math]::Round(($bytesRead / $totalBytes) * 100, 1)) } else { 100 }
        $mbRead = [Math]::Round($bytesRead / 1MB, 1)
        $mbTotal = [Math]::Round($totalBytes / 1MB, 1)
        Write-Progress -Id $pass -Activity $passLabel[$pass] -Status "$mbRead MB / $mbTotal MB ($pct%)" -PercentComplete $pct
        $timer.Restart()
    }
}

$counts = $runMethod.Invoke($null, @($InputPath, $OutputPath, $ResourceId, $progressCallback))

Write-Progress -Id 1 -Activity $passLabel[1] -Completed
Write-Progress -Id 2 -Activity $passLabel[2] -Completed
$sw.Stop()

Write-Host ""
Write-Host "Resources                     : kept $($counts['Resources_kept']), dropped $($counts['Resources_dropped'])"
Write-Host "Shift                         : kept $($counts['Shift_kept']), dropped $($counts['Shift_dropped'])"
Write-Host "Shift_Break                   : kept $($counts['Shift_Break_kept']), dropped $($counts['Shift_Break_dropped'])"
Write-Host "Availability                  : kept $($counts['Availability_kept']), dropped $($counts['Availability_dropped'])"
Write-Host "Resource_Region_Availability  : kept $($counts['Resource_Region_Availability_kept']), dropped $($counts['Resource_Region_Availability_dropped'])"
Write-Host "Resource_Skill                : kept $($counts['Resource_Skill_kept']), dropped $($counts['Resource_Skill_dropped'])"
Write-Host "Resource_Skill_Availability   : kept $($counts['Resource_Skill_Availability_kept']), dropped $($counts['Resource_Skill_Availability_dropped'])"
Write-Host "Resource_Preference           : kept $($counts['Resource_Preference_kept']), dropped $($counts['Resource_Preference_dropped'])"
Write-Host "Resource_Region               : kept $($counts['Resource_Region_kept']), dropped $($counts['Resource_Region_dropped'])"
Write-Host "Plan_Resource                 : kept $($counts['Plan_Resource_kept']), dropped $($counts['Plan_Resource_dropped'])"
Write-Host "Plan_Route                    : kept $($counts['Plan_Route_kept']), dropped $($counts['Plan_Route_dropped'])"
Write-Host "Plan_Break                    : kept $($counts['Plan_Break_kept']), dropped $($counts['Plan_Break_dropped'])"
Write-Host "Plan_Travel                   : kept $($counts['Plan_Travel_kept']), dropped $($counts['Plan_Travel_dropped'])"
Write-Host "Activity_Status               : kept $($counts['Activity_Status_kept']), dropped $($counts['Activity_Status_dropped'])"

if ($counts['Resources_kept'] -eq 0) {
    $diagFile = "$OutputPath.resourceids.txt"
    if (Test-Path $diagFile) {
        Write-Host ""
        Write-Host "WARNING: No Resources element matched ResourceId '$ResourceId'." -ForegroundColor Yellow
        Get-Content $diagFile | Write-Host -ForegroundColor Yellow
        Write-Host "Check for typos, extra quotes, or whitespace in the -ResourceId value you passed." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host ("Done in {0:N1}s. Saved filtered XML to: {1}" -f $sw.Elapsed.TotalSeconds, $OutputPath)
