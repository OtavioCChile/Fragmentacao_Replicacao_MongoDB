$containerMongos = "mongos"
$banco = "tcc"
$colecao = "usuarios"

$arquivoCsv = Join-Path (Get-Location) "resultados-escritas.csv"
$intervaloMs = 500
$timeoutEscritaMs = 2000

Write-Host "Monitor de escritas iniciado."
Write-Host "Destino: $containerMongos / $banco.$colecao"
Write-Host "CSV: $arquivoCsv"
Write-Host "Pressione Ctrl+C para encerrar."
Write-Host ""

while ($true) {
    $idDocumento = "teste-failover-" + [guid]::NewGuid().ToString("N")
    $numero = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

    $idJson = ConvertTo-Json -InputObject $idDocumento -Compress
    $bancoJson = ConvertTo-Json -InputObject $banco -Compress
    $colecaoJson = ConvertTo-Json -InputObject $colecao -Compress
    $nomeJson = ConvertTo-Json -InputObject "Teste de disponibilidade" -Compress

    $js = @"
try {
    const destino = db.getSiblingDB($bancoJson);

    const resultado = destino.runCommand({
        insert: $colecaoJson,
        documents: [{
            _id: $idJson,
            numero: $numero,
            nome: $nomeJson
        }],
        writeConcern: {
            w: "majority",
            wtimeout: $timeoutEscritaMs
        }
    });

    const erroEscrita =
        resultado.errmsg ||
        (resultado.writeConcernError
            ? resultado.writeConcernError.errmsg : "") ||
        (resultado.writeErrors && resultado.writeErrors.length
            ? resultado.writeErrors[0].errmsg : "");

    const sucesso =
        resultado.ok === 1 &&
        resultado.n === 1 &&
        !resultado.writeConcernError &&
        (!resultado.writeErrors || resultado.writeErrors.length === 0);

    print(JSON.stringify({
        sucesso: sucesso,
        erro: erroEscrita || (
            resultado.ok !== 1 || resultado.n !== 1
                ? JSON.stringify(resultado)
                : ""
        ),
        codigo: resultado.code || "",
        inseridos: resultado.n || 0
    }));
} catch (e) {
    print(JSON.stringify({
        sucesso: false,
        erro: e.message || String(e),
        codigo: e.code || "",
        inseridos: 0
    }));
}
"@

    $jsBase64 = [Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes($js)
    )

    $comandoRemoto = "printf '%s' '$jsBase64' | base64 -d > /tmp/monitor-escrita.js && mongosh --quiet --file /tmp/monitor-escrita.js"

    $inicio = Get-Date
    $saida = & docker exec $containerMongos sh -c $comandoRemoto 2>&1
    $codigoDocker = $LASTEXITCODE
    $fim = Get-Date

    $duracaoMs = [math]::Round(($fim - $inicio).TotalMilliseconds, 0)
    $textoSaida = ($saida | ForEach-Object { "$_" }) -join "`n"

    $linhaJson = $textoSaida -split "`r?`n" |
        Where-Object {
            $_.Trim().StartsWith("{") -and $_.Trim().EndsWith("}")
        } |
        Select-Object -Last 1

    $status = "FALHA"
    $erro = ""
    $codigoMongo = ""
    $sucesso = $false

    if ($linhaJson) {
        try {
            $resposta = $linhaJson | ConvertFrom-Json
            $sucesso = (
                $resposta.sucesso -eq $true -and
                $codigoDocker -eq 0
            )
            $erro = [string]$resposta.erro
            $codigoMongo = [string]$resposta.codigo
        }
        catch {
            $erro = "Nao foi possivel interpretar a resposta do mongosh."
        }
    }
    else {
        $erro = $textoSaida
    }

    if ($sucesso) {
        $status = "SUCESSO"
    }
    elseif ([string]::IsNullOrWhiteSpace($erro)) {
        $erro = "A operacao nao foi confirmada como concluida."
    }

    if ($codigoDocker -ne 0 -and [string]::IsNullOrWhiteSpace($erro)) {
        $erro = "Falha ao executar o mongosh no container mongos."
    }

    $registro = [PSCustomObject]@{
        Inicio       = $inicio.ToString("yyyy-MM-dd HH:mm:ss.fff")
        Fim          = $fim.ToString("yyyy-MM-dd HH:mm:ss.fff")
        IdDocumento  = $idDocumento
        Banco        = $banco
        Colecao      = $colecao
        Status       = $status
        DuracaoMs    = $duracaoMs
        CodigoMongo  = $codigoMongo
        CodigoDocker = $codigoDocker
        Erro         = $erro
    }

    if (Test-Path $arquivoCsv) {
        $registro | Export-Csv -Path $arquivoCsv `
            -NoTypeInformation -Append -Encoding UTF8
    }
    else {
        $registro | Export-Csv -Path $arquivoCsv `
            -NoTypeInformation -Encoding UTF8
    }

    Write-Host (
        "{0} | {1} | {2} ms" -f
        $registro.Inicio, $status, $duracaoMs
    )

    if ($status -eq "FALHA") {
        Write-Host "Detalhe: $erro"
    }

    Start-Sleep -Milliseconds $intervaloMs
}
