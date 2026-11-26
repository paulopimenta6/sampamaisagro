# Operação avançada — acesso remoto, lote retomável e serviços

Escolha o roteiro correspondente à sua situação. Os comandos de **terminal** abaixo partem da raiz do projeto na máquina que guarda os dados, exceto o comando do túnel, que se executa no computador do navegador. O `README.md`, `config.yml` e o `renv.lock` na mesma pasta ajudam a reconhecer a instalação correta.

## Acessar pelo navegador de outro computador usando SSH

1. No **console do R da máquina que guarda os dados**, abra o projeto e execute:

~~~r
pkgload::load_all(".")
run_app(host = "127.0.0.1", port = 3939, launch.browser = FALSE)
~~~

2. Confira a mensagem `Listening on` e mantenha o R aberto. No **terminal do computador onde está o navegador**, substitua `usuario@servidor` pelo seu acesso SSH e execute:

~~~bash
ssh -N -L 127.0.0.1:3939:127.0.0.1:3939 usuario@servidor
~~~

3. Abra `http://127.0.0.1:3939` nesse navegador. O primeiro número de porta corresponde à entrada no seu computador. O último deve coincidir com o anunciado pelo R no servidor. Se a porta local estiver ocupada, use 9393 na primeira posição e no navegador. Para encerrar o túnel, pressione Ctrl+C no terminal do SSH. Para encerrar o aplicativo, interrompa o R que o executa. [Instruções de acesso e diagnóstico](../../README.md)

## Processar por partes e retomar

**Com R**, um pequeno lote geométrico pode ser feito com a base sintética e duas origens por coordenadas. Rode estes comandos em uma sessão do R aberta na raiz:

~~~r
pkgload::load_all(".")
entrada <- data.frame(query_id = c("praca-a", "praca-b"),
                      latitude = c(-23.55, -23.56), longitude = c(-46.63, -46.65))
lote <- process_batch(entrada, "outputs/manual-lote-demo",
                      equipment = demo_equipment(), graphs = list(),
                      parameters = list(modes = character()), resume = TRUE)
lote$summary
lote$errors
~~~

Leia `summary.json` e `validation_errors.csv` na pasta de saída. Em `partitions` ficam as tabelas Parquet por bloco. Uma repetição com as mesmas entradas e parâmetros pode reaproveitar blocos concluídos. Ao mudar dados, redes ou parâmetros, escolha outra pasta de saída. Linhas inválidas de um lote terminado continuam no arquivo de erros.

**Com terminal**, para um cadastro local preparado e rede a pé instalada, use o exemplo do repositório:

~~~bash
Rscript scripts/batch.R --input=inst/examples/origens-reais.csv --output=outputs/lote-exemplo-pe --modes=foot --direction=origin_to_equipment
~~~

Use um diretório de saída próprio por estudo e registre o comando. O exemplo inclui uma linha destinada a demonstrar falha de CEP. Para distinguir um problema de entrada de um problema de roteamento, compare o arquivo de erros com os diagnósticos por bloco. [Script de lote](../../scripts/batch.R)

## Fila SQLite e Docker

Para processar um arquivo por meio da fila existente, abra o **R** na raiz com o ambiente e a base local preparados:

~~~r
pkgload::load_all(".")
cfg <- read_sampa_config()
init_job_queue(cfg)
id <- submit_batch_job("inst/examples/origens-reais.csv", owner_id = "treino",
                       parameters = list(modes = character()), config = cfg)
id
~~~

Em um **terminal** nessa instalação, `Rscript scripts/worker.R --once` processa até um trabalho disponível. Em uma fila compartilhada, ele pode pegar um trabalho anterior ao seu. Confira o identificador e a saída em `jobs/<id>` antes de usar os arquivos. Para consultas no navegador, a própria aplicação inicia o processamento. [Função de submissão](../../man/submit_batch_job.Rd)

Com Docker e Compose já instalados, a partir da raiz com os **dados previamente preparados**, `docker compose up --build app` constrói a imagem e inicia a aplicação. O build inicial requer acesso às dependências. Abra `http://localhost:3838` na máquina do serviço. O Compose monta `data` para leitura, e `jobs` e `outputs` para escrita. O mapeamento padrão publica a porta 3838 no host: use em ambiente autorizado e controle quem acessa. Para encerrar essa execução local, pressione Ctrl+C no terminal. O serviço `worker` pode ser iniciado para a fila se a implantação o exigir. [Configuração dos serviços](../../docker-compose.yml)

**Exercício.** Você mudou o raio de um lote e o sistema recusou a retomada. **Gabarito:** use outra pasta para o novo estudo. A recusa evita misturar blocos gerados sob escolhas diferentes. Guarde o manifesto de cada execução e compare somente depois de identificar os respectivos parâmetros.

[Índice do manual](README.md)
