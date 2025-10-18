param(
  [string]$Root = "c:\\Projetos\\_Livros\\APOSTILA_DB_EPUB",
  [string]$Output = "Apostila_DB_build.epub",
  [switch]$NoIcons,
  [switch]$PreferPng
)

$ErrorActionPreference = 'Stop'

# Carregar APIs de compressão
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$rootPath = $Root
$outPath = Join-Path $rootPath $Output

if (Test-Path $outPath) {
  Remove-Item $outPath -Force
}

# Abrir arquivo ZIP (EPUB) para criação
$zipStream = [System.IO.File]::Create($outPath)
$zip = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)

function Add-ZipEntry {
  param(
    [System.IO.Compression.ZipArchive]$Archive,
    [string]$FullPath,
    [string]$EntryPath,
    [bool]$NoCompress = $false
  )
  $level = [System.IO.Compression.CompressionLevel]::Optimal
  if ($NoCompress) { $level = [System.IO.Compression.CompressionLevel]::NoCompression }
  $entry = $Archive.CreateEntry($EntryPath, $level)
  $inStream = [System.IO.File]::OpenRead($FullPath)
  $outStream = $entry.Open()
  try {
    $inStream.CopyTo($outStream)
  } finally {
    $inStream.Dispose(); $outStream.Dispose()
  }
}

function Add-ZipEntryContent {
  param(
    [System.IO.Compression.ZipArchive]$Archive,
    [string]$EntryPath,
    [string]$Content,
    [bool]$NoCompress = $false
  )
  $level = [System.IO.Compression.CompressionLevel]::Optimal
  if ($NoCompress) { $level = [System.IO.Compression.CompressionLevel]::NoCompression }
  $entry = $Archive.CreateEntry($EntryPath, $level)
  $outStream = $entry.Open()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $outStream.Write($bytes, 0, $bytes.Length)
  } finally {
    $outStream.Dispose()
  }
}

# 1) mimetype (sem compressão e primeira entrada)
Add-ZipEntry -Archive $zip -FullPath (Join-Path $rootPath 'mimetype') -EntryPath 'mimetype' -NoCompress $true

# 2) META-INF/container.xml
Add-ZipEntry -Archive $zip -FullPath (Join-Path $rootPath 'META-INF/container.xml') -EntryPath 'META-INF/container.xml'

# 3) OEBPS: incluir SOMENTE arquivos do manifest + content.opf
$opfPath = Join-Path $rootPath 'OEBPS\content.opf'
$xml = New-Object System.Xml.XmlDocument
$xml.Load($opfPath)
$nsmgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
$nsmgr.AddNamespace('opf','http://www.idpf.org/2007/opf')
$items = $xml.SelectNodes('//opf:manifest/opf:item', $nsmgr)
$hrefs = @()
foreach ($it in $items) { $hrefs += $it.GetAttribute('href') }
# Garantir inclusão de content.opf
$hrefs += 'content.opf'

$oebpsBase = Join-Path $rootPath 'OEBPS'
foreach ($href in $hrefs) {
  $fullPath = Join-Path $oebpsBase $href
  if (-not (Test-Path -LiteralPath $fullPath)) {
    Write-Warning "Recurso listado no manifest não encontrado: $href"
    continue
  }
  $entryPath = 'OEBPS/' + ($href -replace '\\','/')
  if (($NoIcons -or $PreferPng) -and ($href -match '\.(x?html)$')) {
    # Leitura robusta do arquivo como string
    try {
      $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
    } catch {
      try { $content = [System.IO.File]::ReadAllText($fullPath) } catch { $content = '' }
    }
    if ($null -eq $content) { $content = '' }

    # Preferir PNGs no Kindle: trocar src de imagens SVG por PNG quando existir
    if ($PreferPng) {
      $imagesDir = Join-Path $oebpsBase 'images'
      $imgMatches = [System.Text.RegularExpressions.Regex]::Matches(
        $content,
        'src=["\'']\.\./images/(?<name>[^"\'']+?)\.svg["\'']',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
      )
      foreach ($m in $imgMatches) {
        $name = $m.Groups['name'].Value
        $pngPath = Join-Path $imagesDir ($name + '.png')
        if (Test-Path -LiteralPath $pngPath) {
          $old = $m.Value
          $new = ($m.Value -replace '\.svg', '.png')
          $content = $content.Replace($old, $new)
        }
      }
    }

    # Remover <img ... class="icon-img" ...>
    $content = [System.Text.RegularExpressions.Regex]::Replace(
      $content,
      '<img[^>]*class\s*=\s*["\'']icon-img["\''][^>]*>',
      '',
      [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    # Remover <svg ... class="icon-img" ...>...</svg>
    $content = [System.Text.RegularExpressions.Regex]::Replace(
      $content,
      '<svg[^>]*class\s*=\s*["\'']icon-img["\''][^>]*>.*?</svg>',
      '',
      [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    # Remover qualquer conteúdo textual/símbolos antes de <strong> dentro de .box-title
    $content = [System.Text.RegularExpressions.Regex]::Replace(
      $content,
      '(<div[^>]*class\s*=\s*["\'']box-title["\''][^>]*>)\s*.*?<strong>',
      '$1<strong>',
      [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    # Ocultar pseudo-elementos ::before por segurança
    if ($content -notmatch 'data-noicons') {
      $noIconsCss = '<style data-noicons> .box-title .icon-img{display:none !important;} .box-title::before{content:"" !important;} pre.code, pre.code.sql { background:#fff !important; color:#000 !important; border-color:#cfcfcf !important; } pre.code.sql .kw, pre.code.sql .type, pre.code.sql .number, pre.code.sql .string, pre.code.sql .comment, pre.code.sql .op { color: inherit !important; font-weight: 400 !important; font-style: normal !important; } </style>'
      $content = [System.Text.RegularExpressions.Regex]::Replace(
        $content,
        '</head>',
        $noIconsCss + '</head>'
      )
    }
    Add-ZipEntryContent -Archive $zip -EntryPath $entryPath -Content $content
  } elseif ($NoIcons -and ($href -match '\.css$')) {
    # Sanitizar CSS para remover qualquer conteúdo inserido via ::before em títulos
    try {
      $css = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
    } catch {
      try { $css = [System.IO.File]::ReadAllText($fullPath) } catch { $css = '' }
    }
    if ($null -eq $css) { $css = '' }

    # Substituir a propriedade content dentro de blocos de .<classe> .box-title::before
    $css = [System.Text.RegularExpressions.Regex]::Replace(
      $css,
      '(\.[A-Za-z-]+\s+\.box-title::before\s*\{[^}]*?)content\s*:\s*[^;]+;?([^}]*\})',
      '$1content: none !important;$2',
      [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    # Fallback para seletores que usam apenas .box-title::before
    $css = [System.Text.RegularExpressions.Regex]::Replace(
      $css,
      '(\.box-title::before\s*\{[^}]*?)content\s*:\s*[^;]+;?([^}]*\})',
      '$1content: none !important;$2',
      [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    # Garantir regra global de segurança
    if ($css -notmatch '\.box-title::before\s*\{\s*content\s*:\s*none') {
      $css += "`n.box-title::before{content: none !important;}" + "`n.box-title .icon-img{display:none !important;}" + "`n"
    }

    Add-ZipEntryContent -Archive $zip -EntryPath $entryPath -Content $css
  } else {
    Add-ZipEntry -Archive $zip -FullPath $fullPath -EntryPath $entryPath
  }
}

# Fechar ZIP
$zip.Dispose()
$zipStream.Dispose()

Write-Host "EPUB gerado:" $outPath