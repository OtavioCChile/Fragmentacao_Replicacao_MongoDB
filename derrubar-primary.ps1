$primary = "shard1b"
$observer = "shard1c"

$primaryAnterior = "${primary}:27017"
$tempoLimite = (Get-Date).AddSeconds(45)

$cronometro = [System.Diagnostics.Stopwatch]::StartNew()

docker kill $primary | Out-Null

$novoPrimario = ""

while ((Get-Date) -lt $tempoLimite) {

    Start-Sleep -Milliseconds 500

    $novoPrimario = (
        docker exec $observer mongosh --quiet --eval `
        "rs.status().members.filter(m => m.stateStr === 'PRIMARY').map(m => m.name).join(',')" `
        2>$null | Out-String
    ).Trim()

    if (
        -not [string]::IsNullOrWhiteSpace($novoPrimario) -and
        $novoPrimario -ne $primaryAnterior
    ) {
        break
    }
}

$cronometro.Stop()

if (
    -not [string]::IsNullOrWhiteSpace($novoPrimario) -and
    $novoPrimario -ne $primaryAnterior
) {
    Write-Host "Primario anterior: $primaryAnterior"
    Write-Host "Novo primario: $novoPrimario"

    Write-Host (
        "Tempo até identificar o novo primario: {0:N2} segundos" `
        -f $cronometro.Elapsed.TotalSeconds
    )
}
else {
    Write-Host "Não foi possivel confirmar o novo primario no tempo limite."
}