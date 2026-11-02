# Artefatos Experimentais: Fragmentação e Replicação no MongoDB

Este repositório reúne os arquivos de configuração, scripts, registros brutos e capturas de tela utilizados como material suplementar de apoio ao artigo **"Aplicação de fragmentação e replicação em banco de dados distribuído: uma prova de conceito no MongoDB"**.

## Estrutura do repositório

- `docker-compose.yml`: define os dez contêineres do *cluster* MongoDB (imagem `mongo:8`), compostos por dois *shards* replicados (`rsShard1` e `rsShard2`, com três nós cada), três servidores de configuração (`cfgRS`) e um roteador `mongos`, além do mapeamento de portas, volumes persistentes e rede interna `mongo-cluster`.
- `derrubar-primary.ps1`: script em PowerShell utilizado nos ensaios de falha. Interrompe o contêiner definido na variável `$primary` por meio de `docker kill`, consulta `rs.status()` a partir do contêiner definido em `$observer` a cada 500 ms (com limite de 45 s) e informa no terminal o novo primário identificado e o tempo decorrido.
- `monitorar-escritas.ps1`: script em PowerShell executado em paralelo aos ensaios de interrupção. Submete via `mongos`, a cada 500 ms, inserções na coleção `tcc.usuarios` com identificador exclusivo e `writeConcern { w: "majority", wtimeout: 2000 }`, gravando o resultado e a duração de cada tentativa em arquivo CSV.
- `resultados-escritas.csv`: registros brutos das tentativas de escrita coletados nos ensaios 2 a 5, contendo horários de início e fim, identificador do documento, banco, coleção, status (`SUCESSO` ou `FALHA`), duração em milissegundos, códigos de retorno e mensagens de erro.
- `TESTE1.png` a `TESTE5.png`: capturas de tela das saídas de terminal dos cinco ensaios realizados, apresentando a execução simultânea do monitor de escritas, do script de interrupção do primário e a verificação de `rs.status()` após a eleição, incluindo os registros do ensaio 1 (ausentes no CSV).

## Requisitos e reprodução

Para reproduzir o ambiente experimental localmente:

1. Utilize **Docker** (com suporte a `docker compose`) e **Windows PowerShell**.
2. Inicie os contêineres a partir do diretório do projeto com `docker compose up -d`.
3. Execute os comandos de inicialização dos *replica sets*, adição dos *shards*, fragmentação da coleção por *hash* de `_id` e carga dos 10.000 documentos sintéticos conforme especificado nas **Listagens 1 e 2** do artigo.
4. Inicie `.\monitorar-escritas.ps1` em um terminal e, após ajustar as variáveis `$primary` e `$observer` de acordo com o estado atual de `rsShard1`, execute `.\derrubar-primary.ps1` em um segundo terminal.