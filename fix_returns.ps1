$files = Get-ChildItem backend/src/routes/*.js
foreach ($file in $files) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    # 1. Fix cases where return is followed by newline before res.json
    $content = $content -replace '(?m)return\s*\r?\n\s*res\.json', 'return res.json'
    # 2. Fix cases where return is followed by newline before next(err)
    $content = $content -replace '(?m)return\s*\r?\n\s*next\(', 'return next('
    [System.IO.File]::WriteAllText($file.FullName, $content)
}
