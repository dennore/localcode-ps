Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $s.Width,$s.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($s.Location, [System.Drawing.Point]::Empty, $bmp.Size)
$g.SmoothingMode = 'AntiAlias'
$cp = [System.Windows.Forms.Cursor]::Position
[Drawing.Point[]]$pts = @([Drawing.Point]::new(0,0),[Drawing.Point]::new(0,32),[Drawing.Point]::new(7,24),[Drawing.Point]::new(13,36),[Drawing.Point]::new(19,32),[Drawing.Point]::new(13,20),[Drawing.Point]::new(23,20)) | %{ [Drawing.Point]::new($cp.X+$_.X,$cp.Y+$_.Y) }
$g.FillPolygon([Drawing.Brushes]::White, $pts)
$p = [Drawing.Pen]::new([Drawing.Color]::Black, 2)
$g.DrawPolygon($p, $pts)
$p.Dispose()
$bmp.Save("screenshot.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "Screenshot saved as screenshot.png"
