# SampaMaisAgro 🌱

Uma aplicação em **R + Shiny** para descobrir registros de agricultura e alimentação próximos de um CEP ou de coordenadas, individualmente ou em lote. Usa os [dados abertos do Sampa+Rural](https://sampamaisrural.prefeitura.sp.gov.br/dados) e, após a preparação, funciona sem internet.

Comece pelo [guia passo a passo](GUIA_LUDICO.md). Para pesquisa, leia o [protocolo](PROTOCOL.md) e o [dicionário](CODEBOOK.md).
Os testes e números observados estão na [ficha de validação real](docs/VALIDACAO_REAL.md).

## O que mudou na versão 0.2

- Corrigida a rejeição de CEPs já geocodificados.
- Sem demonstração silenciosa: a aplicação exige uma base real.
- Os 14 relatórios disponíveis foram guardados em **CSV e JSON**, com contagens e SHA-256.
- Base consolidada também em CSV, JSON, Parquet e RDS.
- Mapas vetoriais locais; sem tiles externos ou chave de API.
- Filtros de feiras livres, orgânicas, hortifrutis, abastecimento/CEAGESP, hortas, agricultores, comércio de alimentos e apoio à agricultura.
- Acessibilidade declarada: sim, não ou não informada.
- Estatísticas, mapa e exportações tanto para consulta única quanto para lote.
- Testes de regressão, validação real e navegador com requisições externas bloqueadas.

Os antigos arquivos de demonstração em outputs permanecem apenas como artefatos históricos. Não são os resultados da aplicação atual.

## Abrir o projeto que já está preparado

No R, a partir da pasta do projeto:

~~~r
pkgload::load_all(".")
run_app()
~~~

Ou clique em **Run App** no arquivo app.R. Ele carrega o código atual do projeto, não uma instalação antiga do pacote.

No terminal, usando os pacotes já instalados:

~~~bash
R_PROFILE_USER=/dev/null Rscript scripts/run_app.R
~~~

O CEP **05586-001** está preparado para teste. O mapa inicial já mostra registros reais, antes da primeira consulta.

## Preparar uma instalação nova (com internet)

R ≥ 4.3; restaure as dependências com renv::restore(). Para mapas/rede, reserve memória e disco: o extrato testado contém 331 mil vias, e os três grafos ocupam aproximadamente 1,6 GB em disco antes de otimizações. A preparação pode levar dezenas de minutos; use uma máquina com cerca de 16 GB de RAM. As consultas geométricas são muito mais leves. PDF requer Pandoc e LaTeX.

~~~bash
Rscript scripts/prepare_offline.R
~~~

Esse comando coleta os dados ausentes, prepara dois CEPs de exemplo e constrói as camadas locais. Preserva uma base existente; atualização é explícita:

~~~bash
Rscript scripts/update_data.R
Rscript scripts/prepare_ceps.R 05586001 01001000
Rscript scripts/prepare_network.R
~~~

Reprocessar um snapshot já baixado, sem nova coleta:

~~~bash
Rscript scripts/update_data.R data/raw/20260914T011240Z
Rscript scripts/prepare_network.R --offline
~~~

## Onde ficam os dados

~~~text
data/
├── raw/<snapshot>/          catálogo + 14 CSV + 14 JSON + manifestos
├── processed/
│   ├── equipment.csv       base analítica legível
│   ├── equipment.json      mesma base em JSON
│   ├── equipment.rds       base usada pela aplicação
│   ├── equipment.parquet   formato colunar
│   ├── inventory.csv       arquivos, fontes, contagens e hashes
│   ├── deduplication.json  regras e contagem de repetições removidas
│   ├── source_reconciliation.csv
│   ├── network_*.rds       grafos por modo
│   ├── network_manifest.json
│   └── map_roads.rds
├── cache/cep/              resposta JSON + ponto e proveniência em RDS
└── osm/                    vias OSM JSON + limite IBGE GeoJSON
~~~

Os dados ficam **no disco local**, não são embutidos no pacote R nem enviados automaticamente ao GitHub. A pasta data está ignorada pelo Git, pois as fontes brutas incluem contatos pessoais. Transfira a pasta completa, de forma controlada, ao preparar outra máquina offline.

## O que “offline” significa

A aplicação não consulta serviços de mapas, rotas ou geocodificação durante uma consulta no modo padrão. Coordenadas funcionam diretamente.

**Um CEP precisa estar previamente no índice local.** Não há uma base gratuita completa de todos os CEPs incorporada ao projeto. Para preparar novos CEPs, enquanto estiver conectado:

~~~bash
Rscript scripts/prepare_ceps.R 01311000
Rscript scripts/prepare_ceps.R meus-ceps.csv
~~~

CEPs desconhecidos no modo offline produzem uma mensagem explicativa. Nunca são substituídos por coordenadas inventadas. A fonte atual é a [AwesomeAPI CEP](https://docs.awesomeapi.com.br/api-cep); cada resposta é arquivada. O ponto é aproximado, não um domicílio.

## Distâncias e seleção

| Família | Medidas |
|---|---|
| Geométrica | Karney elipsoidal, Haversine esférica, Euclidiana, Manhattan e Chebyshev projetadas |
| Rede a pé | Menor distância e menor tempo modelado |
| Rede de bicicleta | Menor distância e menor tempo modelado |
| Rede de carro | Menor distância e menor tempo modelado |

As projeções usam EPSG:31983. As redes permitem ida, volta ou ambas. Ative os modos desejados na interface; a ausência de grafos locais não é mascarada.

A rede é uma análise mais pesada: a consulta a pé no navegador levou cerca de
3 minutos no teste real, incluindo o carregamento do grafo. Consulte os tempos
e condições na [ficha de validação](docs/VALIDACAO_REAL.md). Comece pelas métricas
geométricas e acrescente apenas os modos de transporte necessários.

Cada resultado retém os **k primeiros OU os pontos dentro do raio**, por origem/métrica/sentido. O raio é sempre em metros, inclusive para trajetos classificados por tempo. O ranking “menor tempo” é ordenado por minutos.

Resultados de rede incluem conectores estimados até os vértices; alertas acima de 250 m e exclusão acima de 1.000 m. Sem trânsito real, restrições completas de conversão ou auditoria de calçadas. O mapa mostra os pontos, **não o desenho dos trajetos**.

## Lotes e relatórios

Na aba Lotes, envie até 100 origens. A análise acontece na própria interface, sem depender de iniciar um worker. Mapa, tabelas e estatísticas aparecem nas mesmas abas da consulta única. Há download ZIP e erros por linha.

Exemplo: [origens-reais.csv](inst/examples/origens-reais.csv). A terceira linha tem um CEP não preparado para demonstrar o tratamento de erros.

Para lotes maiores:

~~~bash
Rscript scripts/batch.R --input=origens.csv --output=outputs/meu-lote --modes=foot,bicycle,motorcar
~~~

A API em R mantém partições e checkpoints; rejeita retomada com entrada, parâmetros ou base diferentes. IDs duplicados são validados no lote inteiro. A fila SQLite continua disponível para implantação avançada.

~~~r
pkgload::load_all(".")
cfg <- read_sampa_config()
eq <- load_equipment_data(cfg)
origens <- resolve_origins(data.frame(cep = "05586-001"), cfg)
resultado <- calculate_proximity(origens$valid, eq, graphs = list(), config = cfg)
render_proximity_report(resultado, "outputs/relatorio.html", origens$valid, eq, cfg)
render_proximity_report(resultado, "outputs/relatorio.pdf", origens$valid, eq, cfg)
~~~

## Testar

~~~bash
R_PROFILE_USER=/dev/null Rscript -e 'testthat::test_local()'
R_PROFILE_USER=/dev/null Rscript scripts/validate_real_data.R
~~~

O segundo comando exige os dados reais e os três grafos, bloqueia o cliente HTTP na análise e grava evidências em outputs/validation-real. O navegador é testado por tests/e2e/test_app.py usando um servidor em localhost:3939; ele rejeita requisições externas.

Para uma execução longa, valide um modo por vez e consolide ao final. Os resultados
aprovados são reaproveitados somente quando dados, código de validação, código R e
grafo continuam idênticos:

~~~bash
R_PROFILE_USER=/dev/null Rscript scripts/validate_real_data.R foot
R_PROFILE_USER=/dev/null Rscript scripts/validate_real_data.R bicycle
R_PROFILE_USER=/dev/null Rscript scripts/validate_real_data.R motorcar
R_PROFILE_USER=/dev/null Rscript scripts/validate_real_data.R
~~~

`evidence.json` só indica `passed: true` após a consolidação completa. O teste lento
`tests/e2e/test_network.py` também exercita a consulta a pé pela interface.
Se já houver vias preparadas, os grafos podem ser reconstruídos separadamente,
sem baixar novamente o OSM: `Rscript scripts/rebuild_graphs.R bicycle` (ou `motorcar`/`foot`).

## Cuidados acadêmicos

A base consolidada contém **perfis cadastrados**, não um censo de todos os estabelecimentos. Perfis de uma mesma instalação podem continuar separados se não forem idênticos. Categorias se sobrepõem; “orgânico” é rótulo da fonte/regra, não certificação verificada. “Acessibilidade: sim” não garante percurso acessível.

A triagem geográfica usa o retângulo definido em config.yml, incluindo registros adjacentes ao município. A malha IBGE é referência cartográfica; within_municipality permite a análise de sensibilidade municipal. Coordenadas ausentes não são inventadas.

Medianas, quantis e gráficos descrevem **o subconjunto selecionado**. Não permitem inferir acesso da população, segurança alimentar ou causalidade. Modelos avançados permanecem exploratórios, fora do fluxo descritivo padrão.

Código: MIT. Credite Prefeitura/Sampa+Rural e fontes parceiras; [IBGE](https://servicodados.ibge.gov.br/api/docs/malhas?versao=3); [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), ODbL. Preserve manifestos e datas para a dissertação.
