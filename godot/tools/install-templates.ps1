# Installe les modèles d'export de Godot s'ils manquent (utilisé par compiler.cmd).
#   install-templates.ps1 -Godot <chemin de godot.exe> [-Web] [-Yes]
# Les modèles viennent de la page officielle des versions de Godot (GitHub), pour la version exacte de l'éditeur
# installé, et vont là où l'éditeur les range : %APPDATA%\Godot\export_templates\<version>\.
# Code de sortie : 0 = modèles présents, 1 = échec, 2 = installation refusée.
param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [switch]$Web,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'

# « 4.7.2.stable.official.ed1daf0bf » → dossier « 4.7.2.stable », version publiée « 4.7.2-stable »
$v = "$((& $Godot --version) | Select-Object -First 1)".Trim()
if (-not $v) {
    Write-Host "Godot n'a pas renvoyé sa version : $Godot"
    Write-Host "Il faut la version console de Godot (godot_console.exe ou Godot_v4*_win64_console.exe)."
    exit 1
}
$parts = $v.Split('.')
$i = 0
while ($i -lt $parts.Length -and $parts[$i] -match '^\d+$') { $i++ }
if ($i -lt 2 -or $i -ge $parts.Length) {
    Write-Host "Version de Godot illisible : $v"
    exit 1
}
$num = ($parts[0..($i - 1)] -join '.')
$status = $parts[$i]
$folder = "$num.$status"
$tag = "$num-$status"
$dest = Join-Path $env:APPDATA "Godot\export_templates\$folder"

$needed = @('windows_release_x86_64.exe')
if ($Web) { $needed += 'web_nothreads_release.zip' }
$missing = @($needed | Where-Object { -not (Test-Path (Join-Path $dest $_)) })
if ($missing.Count -eq 0) { exit 0 }

Write-Host "Les modèles d'export de Godot $tag ne sont pas installés (il manque : $($missing -join ', '))."
Write-Host "Ils se téléchargent une seule fois depuis github.com/godotengine/godot (environ 1,3 Go)."
if (-not $Yes) {
    $answer = Read-Host 'Les télécharger et les installer maintenant ? (O/N)'
    if ($answer -notmatch '^[oOyY]') { exit 2 }
}

$url = "https://github.com/godotengine/godot/releases/download/$tag/Godot_v${tag}_export_templates.tpz"
$tmp = Join-Path $env:TEMP "godot-templates-$tag"
$tpz = "$tmp.tpz"
try {
    Write-Host "Téléchargement de $url"
    & curl.exe -L --fail --progress-bar -o $tpz $url
    if ($LASTEXITCODE -ne 0) { throw "téléchargement impossible (curl : code $LASTEXITCODE)" }
    Write-Host 'Décompression...'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Force $tmp | Out-Null
    & tar.exe -xf $tpz -C $tmp
    if ($LASTEXITCODE -ne 0) { throw "décompression impossible (tar : code $LASTEXITCODE)" }
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item (Join-Path $tmp 'templates\*') $dest -Recurse -Force
    Write-Host "Modèles installés dans $dest"
    exit 0
} catch {
    Write-Host "Échec de l'installation des modèles : $_"
    Write-Host "Autre solution : ouvre l'éditeur Godot, puis Éditeur > Gérer les modèles d'export > Télécharger et installer."
    exit 1
} finally {
    if (Test-Path $tpz) { Remove-Item $tpz -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
