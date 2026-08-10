<#
.SYNOPSIS
    Removes all specified elements (and
    everything inside them) from an XML file. Fast version: same streaming
    approach as before, but compiled as native C# via Add-Type instead of
    interpreted PowerShell, to avoid per-node script overhead on large files.

.PARAMETER InputPath
    Path to the source XML file.

.PARAMETER OutputPath
    Path to write the cleaned XML file. If omitted, a new file is created
    in the same folder as InputPath, named "<original>.clean.xml".

.EXAMPLE
    .\Remove-Elements.ps1 -InputPath ".\feed.xml"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$resolvedInput = Resolve-Path -Path $InputPath -ErrorAction Stop
$InputPath = $resolvedInput.Path

if (-not $OutputPath) {
    $directory = Split-Path -Path $InputPath -Parent
    $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $OutputPath = Join-Path -Path $directory -ChildPath "$baseName.clean.xml"
    Write-Host "No -OutputPath given; will write cleaned copy to:`n  $OutputPath"
}

$csharpSource = @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Xml;

public static class XmlStripper
{
    public static Dictionary<string, long> Strip(string inputPath, string outputPath, string[] targetNames)
    {
        var targets = new HashSet<string>(targetNames, StringComparer.Ordinal);
        var counts = new Dictionary<string, long>(StringComparer.Ordinal);

        var readerSettings = new XmlReaderSettings();
        readerSettings.DtdProcessing = DtdProcessing.Parse;
        readerSettings.IgnoreWhitespace = false;

        var writerSettings = new XmlWriterSettings();
        writerSettings.Indent = true;
        writerSettings.Encoding = new UTF8Encoding(false);

        using (XmlReader reader = XmlReader.Create(inputPath, readerSettings))
        using (XmlWriter writer = XmlWriter.Create(outputPath, writerSettings))
        {
            while (reader.Read())
            {
                if (reader.NodeType == XmlNodeType.Element && targets.Contains(reader.LocalName))
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

$targetNames = [string[]]@('Plan_Break','Shift','Slot_Usage_Rule','Plan_Route','Availability', 'Activity','Location','Allocation','Allocation_Data','Additional_Attribute','Appointment_Template','Resource_Region_Availability','Activity_Custom_URL','Activity_Skill','Resource_Skill','Resource_Preference','Resource_Region','Resource_Skill_Availability','Appointment_Template_Item','Activity_Group','Object_Group','Resource_Custom_URL','Appt_Template_Slot_Usage')

Write-Host "Streaming through (compiled): $InputPath"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$counts = [XmlStripper]::Strip($InputPath, $OutputPath, $targetNames)

$sw.Stop()

if ($counts.Count -eq 0) {
    Write-Host "No matching elements found. Nothing to remove."
}
else {
    $total = 0
    foreach ($key in $counts.Keys) {
        Write-Host "  Removed $($counts[$key]) <$key> element(s)."
        $total += $counts[$key]
    }
    Write-Host "Removed $total element(s) total."
}

Write-Host ("Done in {0:N1}s. Saved cleaned XML to: {1}" -f $sw.Elapsed.TotalSeconds, $OutputPath)
