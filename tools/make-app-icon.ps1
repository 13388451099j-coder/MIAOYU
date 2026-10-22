# Generate the iOS AppIcon set (1024 master -> all sizes).
#
# Why this script exists:
#   The project shipped without Assets.xcassets while Info.plist declared
#   CFBundleIconName = AppIcon, so the build produced a blank/white app icon.
#
# Artwork mirrors the Android adaptive icon
# (app/src/main/res/drawable/ic_launcher_foreground.xml):
#   blue-violet gradient + white rounded speech bubble + three blue dots.
#   iOS icons must be opaque and square (the system applies the mask itself),
#   so the canvas is full-bleed with no transparency and no outer corners.
#
# Usage (from the project root):
#   powershell -ExecutionPolicy Bypass -File tools\make-app-icon.ps1
# Output: MiaoyuApp/Assets.xcassets/AppIcon.appiconset/*.png (committed).
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less
# files as ANSI and mangles non-ASCII comments.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'MiaoyuApp\Assets.xcassets\AppIcon.appiconset'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function New-MasterIcon {
    param([int]$Size = 1024)

    # 24bppRgb = no alpha channel at all. The default 32bppArgb bitmap keeps an
    # alpha channel, and GDI+ bicubic downscaling samples outside the source with
    # alpha 0, which leaves semi-transparent pixels along the border (measured
    # A=222 at the corners) - iOS/App Store want a fully opaque icon.
    $bmp = New-Object System.Drawing.Bitmap -ArgumentList $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    # Background: 135-degree gradient #3370FF -> #1F5AE0
    $rect = New-Object System.Drawing.Rectangle -ArgumentList 0, 0, $Size, $Size
    $c1 = [System.Drawing.ColorTranslator]::FromHtml('#3370FF')
    $c2 = [System.Drawing.ColorTranslator]::FromHtml('#1F5AE0')
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList $rect, $c1, $c2, 45.0
    $g.FillRectangle($brush, $rect)
    $brush.Dispose()

    # The Android vector uses a 108x108 viewport; map it onto the canvas.
    $s = $Size / 108.0

    # White speech bubble: 25..83 x 30..66, corner radius 8
    $x0 = 25 * $s; $y0 = 30 * $s; $w = 58 * $s; $h = 36 * $s; $r = 8 * $s
    $bubble = New-Object System.Drawing.Drawing2D.GraphicsPath
    $bubble.AddArc([float]$x0, [float]$y0, [float]($r * 2), [float]($r * 2), 180, 90)
    $bubble.AddArc([float]($x0 + $w - $r * 2), [float]$y0, [float]($r * 2), [float]($r * 2), 270, 90)
    $bubble.AddArc([float]($x0 + $w - $r * 2), [float]($y0 + $h - $r * 2), [float]($r * 2), [float]($r * 2), 0, 90)
    $bubble.AddArc([float]$x0, [float]($y0 + $h - $r * 2), [float]($r * 2), [float]($r * 2), 90, 90)
    $bubble.CloseFigure()

    # Bubble tail: (51.5,64) -> (42,76.5) -> (44.5,64)
    $tail = New-Object System.Drawing.Drawing2D.GraphicsPath
    $pts = @(
        (New-Object System.Drawing.PointF -ArgumentList ([float](51.5 * $s)), ([float](64 * $s))),
        (New-Object System.Drawing.PointF -ArgumentList ([float](42 * $s)), ([float](76.5 * $s))),
        (New-Object System.Drawing.PointF -ArgumentList ([float](44.5 * $s)), ([float](64 * $s)))
    )
    $tail.AddPolygon($pts)

    $white = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::White)
    $g.FillPath($white, $bubble)
    $g.FillPath($white, $tail)

    # Three blue dots (ellipsis)
    $blue = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.ColorTranslator]::FromHtml('#3370FF'))
    foreach ($cx in 40, 54, 68) {
        $d = 6 * $s
        $g.FillEllipse($blue, [float](($cx - 3) * $s), [float](45 * $s), [float]$d, [float]$d)
    }

    $white.Dispose(); $blue.Dispose(); $bubble.Dispose(); $tail.Dispose(); $g.Dispose()
    return $bmp
}

$master = New-MasterIcon -Size 1024

# point x scale = pixel. iPad sizes included for future use
# (TARGETED_DEVICE_FAMILY is currently 1 = iPhone only).
$variants = @(
    @{ file = 'icon-20@2x.png';   px = 40 },
    @{ file = 'icon-20@3x.png';   px = 60 },
    @{ file = 'icon-29@2x.png';   px = 58 },
    @{ file = 'icon-29@3x.png';   px = 87 },
    @{ file = 'icon-40@2x.png';   px = 80 },
    @{ file = 'icon-40@3x.png';   px = 120 },
    @{ file = 'icon-60@2x.png';   px = 120 },
    @{ file = 'icon-60@3x.png';   px = 180 },
    @{ file = 'icon-76@2x.png';   px = 152 },
    @{ file = 'icon-83.5@2x.png'; px = 167 },
    @{ file = 'icon-1024.png';    px = 1024 }
)

foreach ($v in $variants) {
    $bmp = New-Object System.Drawing.Bitmap -ArgumentList $v.px, $v.px, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    # Prime the canvas opaquely so edge interpolation cannot introduce alpha.
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#1F5AE0'))
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($master, 0, 0, $v.px, $v.px)
    $g.Dispose()
    $path = Join-Path $outDir $v.file
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "wrote $($v.file) ($($v.px)x$($v.px))"
}

$master.Dispose()
Write-Output "done -> $outDir"
