# Компиляция PAWN-мода на windows-latest раннере GitHub Actions.
# Раннер обязательно Windows, потому что pawno.exe/pawncc.exe - Windows-программы,
# они лежат прямо внутри присланного пользователем архива (mode/pawno/...).

$ErrorActionPreference = "Stop"

# !!! ВАЖНО: замени строку ниже на свой домен PythonAnywhere перед загрузкой !!!
# Например: $BOT_DOMAIN = "bigsa.pythonanywhere.com"
$BOT_DOMAIN = "sandercompile.pythonanywhere.com"

$file = git diff --name-only HEAD~1 HEAD -- uploads_pawn/ | Select-Object -First 1
if (-not $file) {
    $file = git show --name-only --pretty="" HEAD -- uploads_pawn/ | Select-Object -First 1
}
$basename = Split-Path $file -Leaf
$chatid = $basename.Split('_')[0]

function Report-Result([string]$status) {
    try {
        Invoke-RestMethod -Uri "https://$BOT_DOMAIN/build_result" -Method Post `
            -Body @{ chat_id = $chatid; status = $status; type = "pwn" } | Out-Null
    } catch {}
}

function Send-Message([string]$text) {
    Invoke-RestMethod -Uri "https://api.telegram.org/bot$env:TELEGRAM_BOT_TOKEN/sendMessage" -Method Post `
        -Body @{ chat_id = $chatid; text = $text } | Out-Null
}

function Fail([string]$text) {
    Send-Message $text
    Report-Result "failed"
    exit 1
}

Send-Message "Компилирую PAWN..."

New-Item -ItemType Directory -Force -Path project | Out-Null
try {
    Expand-Archive -Path $file -DestinationPath project -Force
} catch {
    Fail "Не удалось распаковать архив."
}

$modeDir = Join-Path "project" "mode"
$pawnoDir = Join-Path $modeDir "pawno"
$gmDir = Join-Path $modeDir "gamemodes"

if (-not (Test-Path $pawnoDir) -or -not (Test-Path $gmDir)) {
    Fail "В архиве не найдена папка mode/pawno или mode/gamemodes."
}

$pwnFile = Get-ChildItem -Path $gmDir -Filter *.pwn | Select-Object -First 1
if (-not $pwnFile) {
    Fail "В gamemodes не найден .pwn файл."
}

# Пробуем сначала pawncc.exe (это реальный компилятор командной строки,
# который лежит рядом с pawno.exe и обычно вызывается им же по кнопке Compile).
# Если его нет - пробуем pawno.exe напрямую.
$compiler = Join-Path $pawnoDir "pawncc.exe"
if (-not (Test-Path $compiler)) {
    $compiler = Join-Path $pawnoDir "pawno.exe"
}
if (-not (Test-Path $compiler)) {
    Fail "В папке pawno не найден компилятор (pawncc.exe или pawno.exe)."
}

$amxPath = Join-Path $gmDir ($pwnFile.BaseName + ".amx")
$pawnoIncludeDir = Join-Path $pawnoDir "include"
$modeIncludeDir = Join-Path $modeDir "include"

$compilerArgs = @($pwnFile.FullName, "-o$amxPath")
if (Test-Path $pawnoIncludeDir) {
    $compilerArgs += "-i$pawnoIncludeDir"
}
if (Test-Path $modeIncludeDir) {
    $compilerArgs += "-i$modeIncludeDir"
}

# Запускаем компилятор из его собственной папки (pawno), чтобы он подхватил
# лежащий рядом pawn.cfg с настройками по умолчанию - так же, как это
# происходит при компиляции через сам pawno.exe на компьютере.
Push-Location $pawnoDir
try {
    $output = (& $compiler @compilerArgs 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

if (-not (Test-Path $amxPath)) {
    $tail = $output.Trim()
    if ($tail.Length -gt 1500) {
        $tail = $tail.Substring($tail.Length - 1500)
    }
    Fail "Ошибка компиляции (код $exitCode). Вывод компилятора:`n`n$tail"
}

Compress-Archive -Path $amxPath -DestinationPath "build_amx.zip" -Force

Send-Message "Готово! Файл .amx во вложении."

$form = @{
    chat_id  = $chatid
    document = Get-Item "build_amx.zip"
}
Invoke-RestMethod -Uri "https://api.telegram.org/bot$env:TELEGRAM_BOT_TOKEN/sendDocument" -Method Post -Form $form | Out-Null

Report-Result "success"
New-Item -ItemType Directory -Force -Path project | Out-Null
try {
    Expand-Archive -Path $file -DestinationPath project -Force
} catch {
    Fail "Не удалось распаковать архив."
}

$modeDir = Join-Path "project" "mode"
$pawnoDir = Join-Path $modeDir "pawno"
$gmDir = Join-Path $modeDir "gamemodes"

if (-not (Test-Path $pawnoDir) -or -not (Test-Path $gmDir)) {
    Fail "В архиве не найдена папка mode/pawno или mode/gamemodes."
}

$pwnFile = Get-ChildItem -Path $gmDir -Filter *.pwn | Select-Object -First 1
if (-not $pwnFile) {
    Fail "В gamemodes не найден .pwn файл."
}

# Пробуем сначала pawncc.exe (это реальный компилятор командной строки,
# который лежит рядом с pawno.exe и обычно вызывается им же по кнопке Compile).
# Если его нет - пробуем pawno.exe напрямую.
$compiler = Join-Path $pawnoDir "pawncc.exe"
if (-not (Test-Path $compiler)) {
    $compiler = Join-Path $pawnoDir "pawno.exe"
}
if (-not (Test-Path $compiler)) {
    Fail "В папке pawno не найден компилятор (pawncc.exe или pawno.exe)."
}

$amxPath = Join-Path $gmDir ($pwnFile.BaseName + ".amx")
$includeDir = Join-Path $pawnoDir "include"

$compilerArgs = @($pwnFile.FullName, "-o$amxPath")
if (Test-Path $includeDir) {
    $compilerArgs += "-i$includeDir"
}

& $compiler @compilerArgs
$exitCode = $LASTEXITCODE

if (-not (Test-Path $amxPath)) {
    Fail "Ошибка компиляции (код $exitCode). Проверь .pwn файл на ошибки."
}

Compress-Archive -Path $amxPath -DestinationPath "build_amx.zip" -Force

Send-Message "Готово! Файл .amx во вложении."

$form = @{
    chat_id  = $chatid
    document = Get-Item "build_amx.zip"
}
Invoke-RestMethod -Uri "https://api.telegram.org/bot$env:TELEGRAM_BOT_TOKEN/sendDocument" -Method Post -Form $form | Out-Null

Report-Result "success"
