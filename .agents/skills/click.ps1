param([int]$x,[int]$y,[string]$clickType="left")
$m = Add-Type -MemberDefinition '[DllImport("user32.dll")]public static extern bool SetCursorPos(int X,int Y);[DllImport("user32.dll")]public static extern void mouse_event(uint f,uint dx,uint dy,uint d,UIntPtr e);' -Name M -Namespace W -PassThru
$m::SetCursorPos($x,$y)
$z = [UIntPtr]::Zero
$c = @{left=@(2,4);right=@(8,16);middle=@(32,64);double=@(2,4,2,4)}
if(!$c[$clickType]){Write-Host "Invalid click type.";return}
$e = $c[$clickType]; for($i=0;$i -lt $e.Count;$i++){if($clickType -eq 'double' -and $i -eq 2){Start-Sleep -Milliseconds 50};$m::mouse_event($e[$i],0,0,0,$z)}
