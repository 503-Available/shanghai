# Generate app icons (Oriental Pearl Tower line icon + "2026") with System.Drawing.
# Usage: powershell -ExecutionPolicy Bypass -File tools\make-icons.ps1
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'icons'
$navy = [System.Drawing.Color]::FromArgb(255, 30, 58, 95)

function New-RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

# size: output px, rounded: transparent rounded corners, scale: content scale (maskable safe zone)
function Make-Icon([int]$size, [bool]$rounded, [float]$scale, [string]$name) {
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.TextRenderingHint = 'AntiAliasGridFit'
  $g.Clear([System.Drawing.Color]::Transparent)
  $bg = New-Object System.Drawing.SolidBrush $navy
  if ($rounded) { $g.FillPath($bg, (New-RoundRect 0 0 $size $size ($size * 0.18))) }
  else { $g.FillRectangle($bg, 0, 0, $size, $size) }

  # Work in a 512 unit box, scaled around the center
  $k = $size / 512.0 * $scale
  $off = ($size - 512 * $k) / 2
  function P([float]$v) { return $off + $v * $k }
  $white = [System.Drawing.Color]::White
  $pen = New-Object System.Drawing.Pen $white, ([float](16 * $k))
  $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
  $thin = New-Object System.Drawing.Pen $white, ([float](11 * $k))
  $thin.StartCap = 'Round'; $thin.EndCap = 'Round'
  $fill = New-Object System.Drawing.SolidBrush $white

  $cx = 256
  # antenna and shaft
  $g.DrawLine($thin, (P $cx), (P 58), (P $cx), (P 120))
  $g.DrawLine($pen, (P $cx), (P 140), (P $cx), (P 146))
  $g.DrawLine($pen, (P $cx), (P 214), (P $cx), (P 236))
  # top small sphere, upper sphere, big lower sphere (outlined)
  $g.FillEllipse($fill, (P ($cx - 14)), (P 112), (28 * $k), (28 * $k))
  $g.DrawEllipse($pen, (P ($cx - 34)), (P 146), (68 * $k), (68 * $k))
  $g.DrawEllipse($pen, (P ($cx - 58)), (P 236), (116 * $k), (116 * $k))
  # three legs
  $g.DrawLine($pen, (P ($cx - 42)), (P 334), (P ($cx - 84)), (P 392))
  $g.DrawLine($pen, (P ($cx + 42)), (P 334), (P ($cx + 84)), (P 392))
  $g.DrawLine($pen, (P $cx), (P 352), (P $cx), (P 392))
  # year
  $font = New-Object System.Drawing.Font 'Segoe UI', ([float](54 * $k)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = 'Center'
  $g.DrawString('2026', $font, $fill, (P $cx), (P 404), $sf)

  $path = Join-Path $outDir $name
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host "saved $name"
}

Make-Icon 512 $true 1.0 'icon-512.png'
Make-Icon 192 $true 1.0 'icon-192.png'
Make-Icon 512 $false 0.72 'icon-maskable-512.png'
Make-Icon 180 $false 0.86 'apple-touch-icon.png'
