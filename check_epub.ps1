Param(
    [string]$EpubPath = "c:\Projetos\_Livros\APOSTILA_DB_EPUB\Apostila_DB_build.epub"
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path -LiteralPath $EpubPath)) {
    Write-Error "Arquivo EPUB não encontrado: $EpubPath"
    exit 1
}

$fs = [System.IO.File]::OpenRead($EpubPath)
try {
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Read)

    $first = $zip.Entries[0].FullName
    $entriesCount = $zip.Entries.Count
    Write-Output ("FirstEntry: " + $first)
    Write-Output ("EntriesCount: " + $entriesCount)

    $container = $zip.Entries | Where-Object { $_.FullName -eq "META-INF/container.xml" }
    Write-Output ("ContainerXMLFound: " + ([bool]$container))

    $nav = $zip.Entries | Where-Object { $_.FullName -eq "OEBPS/nav.xhtml" }
    Write-Output ("NavXHTMLFound: " + ([bool]$nav))

    $opf = $zip.Entries | Where-Object { $_.FullName -eq "OEBPS/content.opf" }
    Write-Output ("OPFFound: " + ([bool]$opf))

    Write-Output "Entries:" 
    foreach ($e in $zip.Entries) {
        Write-Output (" - " + $e.FullName)
    }

} finally {
    if ($zip) { $zip.Dispose() }
    $fs.Dispose()
}