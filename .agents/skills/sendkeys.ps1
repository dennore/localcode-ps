param([string]$text)
(New-Object -ComObject WScript.Shell).SendKeys($text)
