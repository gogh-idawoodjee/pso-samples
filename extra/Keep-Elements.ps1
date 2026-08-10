<#
.SYNOPSIS
    Keeps only the specified top-level element types (and everything inside
    them) from an XML file, removing everything else. This is the inverse of
    Remove-AvailabilityElements-Fast.ps1 - same streaming C# approach via
    Add-Type for speed on large files.

.PARAMETER InputPath
    Path to the source XML file.

.PARAMETER OutputPath
    Path to write the cleaned XML file. If omitted, a new file is created
    in the same folder as InputPath, named "<original>.kept.xml".

.EXAMPLE
    .\Keep-OnlyElements-Fast.ps1 -InputPath ".\feed.xml"
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
    $OutputPath = Join-Path -Path $directory -ChildPath "$baseName.kept.xml"
    Write-Host "No -OutputPath given; will write cleaned copy to:`n  $OutputPath"
}

$csharpSource = @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Xml;

public static class XmlKeeper
{
    public static Dictionary<string, long> Keep(string inputPath, string outputPath, string[] keepNames)
    {
        var keepers = new HashSet<string>(keepNames, StringComparer.Ordinal);
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
            // Track how deep we are inside the outer envelope (e.g. the root
            // element itself, plus any wrapper elements) so we only apply the
            // keep/drop decision to top-level record elements, not to fields
            // nested inside a kept record (e.g. <id>, <description>, etc).
            int depth = 0;

            while (reader.Read())
            {
                if (reader.NodeType == XmlNodeType.Element)
                {
                    // depth 0 = root element (e.g. dsScheduleData) - always keep.
                    // depth 1 = top-level record elements (e.g. Activity) - filter these.
                    if (depth == 1 && !keepers.Contains(reader.LocalName))
                    {
                        string name = reader.LocalName;
                        long current;
                        counts.TryGetValue(name, out current);
                        counts[name] = current + 1;
                        reader.Skip();
                        continue;
                    }

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
                    continue;
                }

                switch (reader.NodeType)
                {
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

# Edit this list to whatever top-level element types you want to KEEP.
# Everything else at the top level gets dropped.
$keepNames = [string[]]@('Activity','Activity_Status','Activity_SLA')

Write-Host "Streaming through (compiled): $InputPath"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$counts = [XmlKeeper]::Keep($InputPath, $OutputPath, $keepNames)

$sw.Stop()

if ($counts.Count -eq 0) {
    Write-Host "No elements were dropped (everything matched the keep-list)."
}
else {
    $total = 0
    foreach ($key in $counts.Keys) {
        Write-Host "  Dropped $($counts[$key]) <$key> element(s)."
        $total += $counts[$key]
    }
    Write-Host "Dropped $total element(s) total."
}

Write-Host ("Done in {0:N1}s. Saved cleaned XML to: {1}" -f $sw.Elapsed.TotalSeconds, $OutputPath)
