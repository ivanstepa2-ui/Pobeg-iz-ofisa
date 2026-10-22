# Сборка APK «Побег из офиса» на Windows.
#   powershell -ExecutionPolicy Bypass -File build_apk.ps1             — собрать (тулчейн уже есть)
#   powershell -ExecutionPolicy Bypass -File build_apk.ps1 -Download   — сначала скачать недостающее (~1,4 ГБ)
#   powershell -ExecutionPolicy Bypass -File build_apk.ps1 -Cheat      — чит-сборка (PobegIzOfisa-cheat.apk)
#   powershell -ExecutionPolicy Bypass -File build_apk.ps1 -Release    — релиз для публикации (PobegIzOfisa-release.apk)
# Тулчейн кладётся рядом с папкой проекта (..\dzv-build): путь должен быть коротким, длинные ломают распаковку JDK.
param(
	[switch]$Download,
	[string]$Tools = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dzv-build'),
	[string]$Out = '',
	[switch]$Cheat,   # чит-сборка для автора: пресет «Android Cheat» (этажи до 30), отдельное приложение
	[switch]$Release  # релизная сборка (без флага отладки) тем же ключом — для публикации
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dl = Join-Path $Tools 'downloads'
$godotExe = Join-Path $Tools 'godot\editor\Godot_v4.3-stable_win64_console.exe'
$templates = Join-Path $env:APPDATA 'Godot\export_templates\4.3.stable'
$sdk = Join-Path $Tools 'sdk'
$jdkRoot = Join-Path $Tools 'jdk'
$GH = 'https://github.com/godotengine/godot/releases/download/4.3-stable/'
$GOOG = 'https://dl.google.com/android/repository/'

function Get-File($url, $out) {
	New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
	& curl.exe -L --fail -sS --retry 3 -o $out $url
	if ($LASTEXITCODE -ne 0) { throw "Не скачалось: $url" }
}
function Assert-Hash($file, $alg, $want) {
	$got = (Get-FileHash $file -Algorithm $alg).Hash.ToLower()
	if ($got -ne $want.ToLower()) { throw "Контрольная сумма не совпала: $file" }
}
function Expand-To($zip, $dst) {
	New-Item -ItemType Directory -Force $dst | Out-Null
	& tar.exe -xf $zip -C $dst
	if ($LASTEXITCODE -ne 0) { throw "Не распаковалось: $zip" }
}

$jdk = Get-ChildItem $jdkRoot -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
$missing = @()
if (-not (Test-Path $godotExe)) { $missing += 'Godot 4.3 (55 МБ)' }
if (-not (Test-Path (Join-Path $templates 'android_debug.apk'))) { $missing += 'шаблоны экспорта Godot 4.3 (1 ГБ)' }
if (-not $jdk) { $missing += 'JDK 17 (178 МБ)' }
if (-not (Test-Path (Join-Path $sdk 'build-tools\34.0.0\apksigner.bat'))) { $missing += 'Android build-tools 34 (56 МБ)' }
if (-not (Test-Path (Join-Path $sdk 'platform-tools\adb.exe'))) { $missing += 'Android platform-tools (8 МБ)' }
if (-not (Test-Path (Join-Path $sdk 'platforms\android-34'))) { $missing += 'Android platform 34 (60 МБ)' }

if ($missing.Count -gt 0) {
	if (-not $Download) { throw ("Не хватает: " + ($missing -join ', ') + ". Запусти с -Download.") }
	"Скачиваю: " + ($missing -join ', ')
	if (-not (Test-Path $godotExe) -or -not (Test-Path (Join-Path $templates 'android_debug.apk'))) {
		Get-File ($GH + 'SHA512-SUMS.txt') "$dl\SHA512-SUMS.txt"
		$sums = Get-Content "$dl\SHA512-SUMS.txt"
	}
	if (-not (Test-Path $godotExe)) {
		Get-File ($GH + 'Godot_v4.3-stable_win64.exe.zip') "$dl\godot.zip"
		Assert-Hash "$dl\godot.zip" SHA512 ((($sums | Where-Object { $_ -match 'win64.exe.zip$' }) -split '\s+')[0])
		Expand-To "$dl\godot.zip" (Join-Path $Tools 'godot\editor')
	}
	if (-not (Test-Path (Join-Path $templates 'android_debug.apk'))) {
		Get-File ($GH + 'Godot_v4.3-stable_export_templates.tpz') "$dl\templates.tpz"
		Assert-Hash "$dl\templates.tpz" SHA512 ((($sums | Where-Object { $_ -match 'export_templates.tpz$' }) -split '\s+')[0])
		Expand-To "$dl\templates.tpz" "$dl\tpl"
		New-Item -ItemType Directory -Force $templates | Out-Null
		Move-Item "$dl\tpl\templates\*" $templates -Force
	}
	if (-not $jdk) {
		Get-File 'https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip.sha256sum.txt' "$dl\jdk.sha256"
		Get-File 'https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip' "$dl\jdk.zip"
		Assert-Hash "$dl\jdk.zip" SHA256 (((Get-Content "$dl\jdk.sha256" -Raw).Trim() -split '\s+')[0])
		Expand-To "$dl\jdk.zip" $jdkRoot
		$jdk = Get-ChildItem $jdkRoot -Directory | Select-Object -First 1
	}
	Get-File ($GOOG + 'repository2-3.xml') "$dl\repo.xml"
	$xml = Get-Content "$dl\repo.xml" -Raw
	function Get-SdkZip($pattern, $dst, $sub) {
		$m = [regex]::Match($xml, '<checksum[^>]*>([0-9a-f]{40})</checksum>\s*<url>(' + $pattern + ')</url>')
		if (-not $m.Success) { throw "Нет в репозитории: $pattern" }
		$zip = Join-Path $dl $m.Groups[2].Value
		Get-File ($GOOG + $m.Groups[2].Value) $zip
		Assert-Hash $zip SHA1 $m.Groups[1].Value
		$tmp = Join-Path $dl ('x_' + $sub)
		if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
		Expand-To $zip $tmp
		$inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
		New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
		if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
		Move-Item $inner.FullName $dst
	}
	if (-not (Test-Path (Join-Path $sdk 'build-tools\34.0.0\apksigner.bat'))) { Get-SdkZip 'build-tools_r34-windows\.zip' (Join-Path $sdk 'build-tools\34.0.0') 'bt' }
	if (-not (Test-Path (Join-Path $sdk 'platform-tools\adb.exe'))) { Get-SdkZip 'platform-tools_r[\d.]+-win(?:dows)?\.zip' (Join-Path $sdk 'platform-tools') 'pt' }
	if (-not (Test-Path (Join-Path $sdk 'platforms\android-34'))) { Get-SdkZip 'platform-34-ext7_r03\.zip' (Join-Path $sdk 'platforms\android-34') 'pl' }
}

# Дальше вызываем внешние программы: их stderr не должен ронять скрипт (PowerShell 5.1).
$ErrorActionPreference = 'Continue'

# --- ключ подписи (debug). Тот же ключ = обновление поверх установленной игры.
$ks = Join-Path $here 'keys\debug.keystore'
if (-not (Test-Path $ks)) {
	New-Item -ItemType Directory -Force (Split-Path $ks) | Out-Null
	& (Join-Path $jdk.FullName 'bin\keytool.exe') -genkeypair -keystore $ks -alias androiddebugkey -storepass android -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US'
	'ВНИМАНИЕ: создан НОВЫЙ ключ — APK не встанет поверх версии со старым ключом (удали старую игру).'
}

# --- настройки редактора Godot: пути к SDK/JDK/ключу
$es = Join-Path $env:APPDATA 'Godot\editor_settings-4.3.tres'
if (-not (Test-Path $es)) { & $godotExe --headless --path (Join-Path $here 'godot') --import 2>&1 | Out-Null }
if (-not (Test-Path $es)) { New-Item -ItemType Directory -Force (Split-Path $es) | Out-Null; Set-Content $es "[gd_resource type=`"EditorSettings`" format=3]`n`n[resource]" -Encoding utf8 }
$t = ([IO.File]::ReadAllText($es) -split "`n" | Where-Object { $_ -notmatch '^export/android/(android_sdk_path|java_sdk_path|debug_keystore)' }) -join "`n"
$t = $t.TrimEnd() + "`n" + (@(
	"export/android/android_sdk_path = `"$($sdk.Replace('\','/'))`"",
	"export/android/java_sdk_path = `"$($jdk.FullName.Replace('\','/'))`"",
	"export/android/debug_keystore = `"$($ks.Replace('\','/'))`"",
	'export/android/debug_keystore_user = "androiddebugkey"',
	'export/android/debug_keystore_pass = "android"') -join "`n") + "`n"
[IO.File]::WriteAllText($es, $t, (New-Object Text.UTF8Encoding $false))

# --- импорт, тесты, экспорт
$env:JAVA_HOME = $jdk.FullName
$proj = Join-Path $here 'godot'
& $godotExe --headless --path $proj --import 2>&1 | Out-Null
$test = & $godotExe --headless --path $proj --fixed-fps 30 --quit-after 20000 -- --itemtest 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^\[itemtest\]' }
$test
if (-not ($test -match 'ИТОГ: OK')) { throw 'Тест предметов не прошёл — APK не собираю.' }
$preset = if ($Cheat) { 'Android Cheat' } else { 'Android' }
if (-not $Out) { $Out = if ($Cheat) { 'PobegIzOfisa-cheat.apk' } elseif ($Release) { 'PobegIzOfisa-release.apk' } else { 'PobegIzOfisa.apk' } }
# релиз подписывается тем же ключом (через переменные окружения Godot — ключ нигде не прописывается)
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $ks
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'androiddebugkey'
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = 'android'
$mode = if ($Release) { '--export-release' } else { '--export-debug' }
$apk = Join-Path $here $Out
if (Test-Path $apk) { Remove-Item $apk }
# Godot 4.3 на Windows часто падает на шаге выравнивания («Не удалось распаковать временный невыровненный APK»):
# свежий временный APK, похоже, задерживает антивирус (проверка нового файла), и Godot не может его перечитать.
# Сам временный APK при этом целый и остаётся на диске — тогда выравниваем и подписываем его сами
# (zipalign + apksigner из build-tools, тем же debug-ключом), как сделал бы Godot.
# Кэш Godot (берётся из LOCALAPPDATA) — рядом с тулчейном, чтобы точно знать, где лежит временный APK.
$cache = Join-Path $Tools 'cache'
New-Item -ItemType Directory -Force $cache | Out-Null
$env:LOCALAPPDATA = $cache
$tmpGlob = Join-Path $cache 'Godot\tmpexport-unaligned*.apk'
Remove-Item $tmpGlob -Force -ErrorAction SilentlyContinue
& $godotExe --headless --path $proj $mode $preset $apk 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match 'export:|ERROR|Signed' }
if (-not (Test-Path $apk)) {
	$tmp = Get-ChildItem $tmpGlob -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
	if (-not $tmp) { throw 'APK не создан (и временного APK нет).' }
	'Godot не смог выровнять APK сам — выравниваю и подписываю временный APK: ' + $tmp.Name
	$bt = Join-Path $sdk 'build-tools\34.0.0'
	$aligned = Join-Path $cache 'aligned.apk'
	& (Join-Path $bt 'zipalign.exe') -p -f 4 $tmp.FullName $aligned
	if ($LASTEXITCODE -ne 0) { throw 'zipalign не сработал.' }
	& (Join-Path $bt 'apksigner.bat') sign --ks $ks --ks-pass pass:android --ks-key-alias androiddebugkey --key-pass pass:android --out $apk $aligned
	if ($LASTEXITCODE -ne 0) { throw 'apksigner не подписал APK.' }
	Remove-Item $aligned, $tmp.FullName -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path $apk)) { throw 'APK не создан.' }
& (Join-Path $sdk 'build-tools\34.0.0\apksigner.bat') verify $apk
if ($LASTEXITCODE -ne 0) { throw 'Подпись APK не прошла проверку.' }
"Готово: $apk  ({0:N1} МБ)" -f ((Get-Item $apk).Length / 1MB)
