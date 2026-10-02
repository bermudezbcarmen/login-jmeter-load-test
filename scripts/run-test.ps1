param(
    [ValidateSet('smoke', 'load')][string]$Mode = 'smoke',
    [string]$JMeterHome = $env:JMETER_HOME,
    [string]$JavaHome = $env:JAVA_HOME
)
$ErrorActionPreference = 'Stop'
if (-not $JMeterHome) { $JMeterHome = 'C:\tools\apache-jmeter-5.6.3' }
if (-not $JavaHome -and (Test-Path -LiteralPath 'C:\Program Files\Java\jdk-18.0.1.1')) {
    $JavaHome = 'C:\Program Files\Java\jdk-18.0.1.1'
}
$java = if ($JavaHome) { Join-Path $JavaHome 'bin\java.exe' } else { 'java' }
$jar = Join-Path $JMeterHome 'bin\ApacheJMeter.jar'
if (-not (Test-Path -LiteralPath $jar)) { throw 'Configurar JMETER_HOME con la carpeta de JMeter.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$runId = '{0}-{1}-{2}' -f $Mode, (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 6))
$jtl = Join-Path $projectRoot "results\$runId.jtl"
$log = Join-Path $projectRoot "results\$runId.log"
$report = Join-Path $projectRoot "reports\$runId"
$summaryPath = Join-Path $projectRoot "results\$runId-summary.json"
$isLoad = $Mode -eq 'load'
$threads = if ($isLoad) { 60 } else { 1 }
$ramp = if ($isLoad) { 30 } else { 1 }
$duration = if ($isLoad) { 150 } else { 30 }
$loops = if ($isLoad) { -1 } else { 5 }
$throughput = if ($isLoad) { 1260 } else { 60 }
$arguments = @(
    '-Djava.awt.headless=true', '-jar', $jar, '-n',
    '-t', (Join-Path $projectRoot 'test-plan\login-load-test.jmx'),
    '-l', $jtl, '-j', $log, '-e', '-o', $report,
    "-Jthreads=$threads", "-Jramp_up=$ramp", "-Jduration=$duration",
    "-Jloops=$loops", "-Jthroughput_per_minute=$throughput",
    ('-Jusers_file=' + (Join-Path $projectRoot 'data\users.csv')),
    '-Jjmeter.save.saveservice.output_format=csv',
    '-Jjmeter.save.saveservice.print_field_names=true',
    '-Jjmeter.save.saveservice.assertion_results_failure_message=true',
    '-Jjmeter.save.saveservice.timestamp_format=ms',
    '-Jsampleresult.timestamp.start=true',
    '-Jjmeter.save.saveservice.response_data=false',
    '-Jjmeter.save.saveservice.samplerData=false'
)
Write-Host "Modo: $Mode; hilos: $threads; objetivo: $throughput peticiones/min; duracion: $duration s"
& $java @arguments
$jmeterExit = $LASTEXITCODE
if ($jmeterExit -ne 0) { throw "JMeter termino con codigo $jmeterExit. Revisar $log" }
if (-not (Test-Path -LiteralPath $jtl)) { throw 'JMeter no genero resultados.' }
$samples = @(Import-Csv -LiteralPath $jtl | Where-Object { $_.label -eq 'HTTP Request - Login' })
if ($samples.Count -eq 0) { throw 'No se registraron peticiones de login; no se puede evaluar el ejercicio.' }
$errors = @($samples | Where-Object { $_.success -ne 'true' }).Count
$slow = @($samples | Where-Object { [double]$_.elapsed -gt 1500 }).Count
$errorPct = 100.0 * $errors / $samples.Count
$start = ($samples | ForEach-Object { [double]$_.timeStamp } | Measure-Object -Minimum).Minimum
$end = ($samples | ForEach-Object { [double]$_.timeStamp + [double]$_.elapsed } | Measure-Object -Maximum).Maximum
$elapsedSeconds = ($end - $start) / 1000.0
$steadySeconds = $duration - $ramp
$steadyStart = $start + $ramp * 1000.0
$steadyEnd = $start + $duration * 1000.0
$steady = @($samples | Where-Object {
    [double]$_.timeStamp -ge $steadyStart -and [double]$_.timeStamp -lt $steadyEnd
})
$steadyTps = if ($isLoad) { $steady.Count / [double]$steadySeconds } else { $null }
$successfulSteadyTps = if ($isLoad) {
    @($steady | Where-Object { $_.success -eq 'true' }).Count / [double]$steadySeconds
} else { $null }
$pass = if ($isLoad) {
    $steadyTps -ge 20 -and $errorPct -lt 3 -and $slow -eq 0
} else { $samples.Count -eq 5 -and $errors -eq 0 }
$summary = [ordered]@{
    mode = $Mode
    samples = $samples.Count
    errors = $errors
    errorPercent = $errorPct
    over1500ms = $slow
    maxResponseMs = ($samples | ForEach-Object { [double]$_.elapsed } | Measure-Object -Maximum).Maximum
    averageResponseMs = ($samples | ForEach-Object { [double]$_.elapsed } | Measure-Object -Average).Average
    overallTps = if ($elapsedSeconds -gt 0) { $samples.Count / $elapsedSeconds } else { 0 }
    steadyWindowSeconds = if ($isLoad) { $steadySeconds } else { $null }
    steadyTps = $steadyTps
    successfulSteadyTps = $successfulSteadyTps
    targetTps = $throughput / 60.0
    requiredTps = 20
    acceptableErrorPercentExclusive = 3
    passed = $pass
    responseCodes = @($samples | Group-Object responseCode | ForEach-Object {
        @{ code = $_.Name; count = $_.Count }
    })
    resultsFile = $jtl
    reportIndex = Join-Path $report 'index.html'
}
$json = $summary | ConvertTo-Json -Depth 5
$json | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host $json
Write-Host "Resumen: $summaryPath"
if (-not $pass) { exit 1 }
exit 0
