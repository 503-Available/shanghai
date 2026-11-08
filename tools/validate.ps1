# Validate data/trip.json (structure, references, times, Chinese fields, privacy).
# Usage: powershell -ExecutionPolicy Bypass -File tools\validate.ps1
# Exit code 0 = OK (warnings allowed), 1 = errors found.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root 'data\trip.json'
$errors = New-Object System.Collections.ArrayList
$warns = New-Object System.Collections.ArrayList
function Err($m) { [void]$errors.Add($m) }
function Warn($m) { [void]$warns.Add($m) }

# 1. Parse JSON (read as UTF-8 explicitly)
try {
  $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $trip = $raw | ConvertFrom-Json
} catch {
  Write-Host "[FAIL] trip.json is not valid JSON: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

# 2. Top-level keys
foreach ($k in 'title','subtitle','startDate','endDate','days','places','foodList','shoppingList','reservations','prep','subway') {
  if ($null -eq $trip.$k) { Err "missing top-level key: $k" }
}

$hangul = '[' + [char]0xAC00 + '-' + [char]0xD7A3 + [char]0x3131 + '-' + [char]0x318E + ']'
$timeRe = '^([01]\d|2[0-3]):[0-5]\d$'
$validCat = 'food','sight','shop','hotel','transport'
$validType = 'flight','move','hotel','food','sight','shop','tour'
$validResv = 'required','recommended','done'

# 3. Places: unique ids, categories, Chinese fields
$placeIds = @{}
foreach ($p in $trip.places) {
  if (-not $p.id) { Err "place without id: $($p.name)"; continue }
  if ($placeIds.ContainsKey($p.id)) { Err "duplicate place id: $($p.id)" }
  $placeIds[$p.id] = $p
  if ($validCat -notcontains $p.category) { Err "place $($p.id): bad category '$($p.category)'" }
  if (-not $p.name) { Err "place $($p.id): missing name" }
  if (-not $p.map) { Err "place $($p.id): missing map keyword" }
  foreach ($f in 'nameZh','addressZh','map') {
    if ($p.$f -and ($p.$f -match $hangul)) { Err "place $($p.id): $f contains Korean characters ($($p.$f))" }
  }
  if (-not $p.nameZh) { Warn "place $($p.id): no nameZh (driver card will be empty)" }
  if ($p.category -eq 'food' -and ($p.signature.Count -lt 1 -or $p.signature.Count -gt 2)) { Err "place $($p.id): food place needs 1-2 signature dishes" }
  foreach ($s in $p.signature) {
    if (-not $s.name -or -not $s.zh) { Err "place $($p.id): signature needs name and zh" }
    elseif ($s.zh -match $hangul) { Err "place $($p.id): signature zh contains Korean ($($s.zh))" }
  }
  if ($p.reservation -and ($validResv -notcontains $p.reservation)) { Err "place $($p.id): bad reservation '$($p.reservation)'" }
  if ($p.tel -and ($p.tel -notmatch '^[0-9\-]+$')) { Err "place $($p.id): bad tel '$($p.tel)'" }
}

# 4. Days: dates in range and consecutive, times valid and ascending, references
$start = [datetime]::ParseExact($trip.startDate, 'yyyy-MM-dd', $null)
$end = [datetime]::ParseExact($trip.endDate, 'yyyy-MM-dd', $null)
$expected = $start
$usedPlaces = @{}
foreach ($d in $trip.days) {
  $dt = [datetime]::ParseExact($d.date, 'yyyy-MM-dd', $null)
  if ($dt -ne $expected) { Err "day $($d.label): date $($d.date) is not consecutive (expected $($expected.ToString('yyyy-MM-dd')))" }
  $expected = $dt.AddDays(1)
  if ($dt -lt $start -or $dt -gt $end) { Err "day $($d.label): date out of trip range" }
  if (-not $d.weather) { Warn "day $($d.label): no weather" }
  if ($d.cover -and $d.cover.image) {
    if (-not (Test-Path (Join-Path $root $d.cover.image))) { Warn "day $($d.label): cover image not found yet ($($d.cover.image))" }
    elseif (-not $d.cover.credit) { Err "day $($d.label): cover image has no photographer credit" }
  }
  $prev = ''
  foreach ($it in $d.items) {
    if ($it.time -notmatch $timeRe) { Err "day $($d.label): bad time '$($it.time)' ($($it.title))" }
    elseif ($prev -and ($it.time -lt $prev)) { Err "day $($d.label): time goes backwards at $($it.time) ($($it.title))" }
    $prev = $it.time
    if ($validType -notcontains $it.type) { Err "day $($d.label) $($it.time): bad type '$($it.type)'" }
    if ($it.placeId) {
      if (-not $placeIds.ContainsKey($it.placeId)) { Err "day $($d.label) $($it.time): unknown placeId '$($it.placeId)'" }
      else { $usedPlaces[$it.placeId] = $true }
    }
    if ($it.reservation -and ($validResv -notcontains $it.reservation)) { Err "day $($d.label) $($it.time): bad reservation '$($it.reservation)'" }
  }
}
if ($trip.days.Count -ne (($end - $start).Days + 1)) { Err "days count $($trip.days.Count) does not match trip length" }

# 5. Other lists reference valid places
foreach ($f in $trip.foodList) { foreach ($id in $f.placeIds) { if (-not $placeIds.ContainsKey($id)) { Err "foodList $($f.id): unknown placeId '$id'" } } }
foreach ($r in $trip.reservations) {
  if ($validResv -notcontains $r.status) { Err "reservation $($r.id): bad status '$($r.status)'" }
  if ($r.placeId -and -not $placeIds.ContainsKey($r.placeId)) { Err "reservation $($r.id): unknown placeId '$($r.placeId)'" }
}
foreach ($p in $trip.places) {
  if (-not $usedPlaces.ContainsKey($p.id) -and $p.category -ne 'shop') { Warn "place $($p.id) is not used in any day" }
}

# 6. Subway
foreach ($l in $trip.subway.lines) {
  if ($l.color -notmatch '^#[0-9a-fA-F]{6}$') { Err "subway line $($l.id): bad color" }
  if (-not $l.stations -or $l.stations.Count -lt 2) { Err "subway line $($l.id): needs 2+ stations" }
}

# 7. Privacy: public repo, so no booking numbers / emails / passport-like codes
if ($raw -match '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') { Err "privacy: email address found" }
if ($raw -match '\b[A-Z]{1,2}\d{7,8}\b') { Err "privacy: passport-like number found" }
if ($raw -match '(?<![\d-])\d{8,}(?![\d-])') { Err "privacy: long number (booking no.?) found" }

# Report
Write-Host ("places={0} days={1} items={2}" -f $trip.places.Count, $trip.days.Count, (($trip.days | ForEach-Object { $_.items.Count }) | Measure-Object -Sum).Sum)
foreach ($w in $warns) { Write-Host "[WARN] $w" -ForegroundColor Yellow }
foreach ($e in $errors) { Write-Host "[ERROR] $e" -ForegroundColor Red }
if ($errors.Count) { Write-Host "FAILED: $($errors.Count) error(s)" -ForegroundColor Red; exit 1 }
Write-Host "OK: no errors ($($warns.Count) warning(s))" -ForegroundColor Green
exit 0
