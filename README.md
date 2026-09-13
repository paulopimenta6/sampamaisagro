# Sampa+Rural: proximidade espacial em R

Este repositório implementa um fluxo acadêmico reprodutível para coletar, versionar e analisar os dados abertos do [Sampa+Rural](https://sampamaisrural.prefeitura.sp.gov.br/dados). Ele aceita uma origem ou lotes com até 100 mil origens, informadas por CEP ou latitude/longitude, e produz vizinhos mais próximos, mapas, tabelas, diagnósticos estatísticos e relatórios HTML/PDF.

👉 Para uma introdução passo a passo, com exemplos e linguagem simples, comece pelo [Guia divertido do Sampa+Rural](GUIA_LUDICO.md).

O projeto foi desenhado para apoiar uma dissertação, mas **não substitui o protocolo de pesquisa**: definições de exposição, população, período e hipóteses precisam ser congeladas antes da análise confirmatória. Leia [PROTOCOL.md](PROTOCOL.md) e [CODEBOOK.md](CODEBOOK.md).

## O que está implementado

- Coletor educado do catálogo e dos relatórios JSON/CSV, com autorização explícita, limite de requisições, retries, ETag, checksums e snapshots imutáveis.
- Normalização, validação espacial e quarentena; contatos diretos nunca entram na base analítica processada.
- CEP via BrasilAPI CEP V2, cache local e proveniência; coordenadas continuam sendo a opção mais precisa.
- Cinco métricas geométricas: Karney, Haversine, Euclidiana, Manhattan e Chebyshev.
- Redes OpenStreetMap para caminhada, bicicleta e automóvel; menor distância e menor tempo; ida, volta ou ambos; alertas de snapping e pares inalcançáveis.
- Consulta unitária Shiny e lotes assíncronos por SQLite, blocos e checkpoints.
- Mapas Leaflet/ggplot2, concordância entre métricas, grade hexagonal, Poisson/binomial negativa e Moran dos resíduos.
- Relatório parametrizado HTML/PDF, testes, `targets`, `renv` e contêineres separados para aplicação e worker.

## Início rápido

```r
install.packages(c("renv", "pkgload"))
renv::restore()
pkgload::load_all(".")
run_app()
```

Sem snapshot oficial, a aplicação entra em **modo demonstração** com 12 pontos sintéticos claramente identificados. Isso permite testar a interface, mas não produzir resultados de pesquisa.

### Demonstrações incluídas

- [Tela inicial da aplicação](outputs/test-artifacts/app-initial.png)
- [Consulta demonstrativa no mapa](outputs/test-artifacts/app-query.png)
- [Relatório demonstrativo em PDF](outputs/reports/relatorio-demonstracao.pdf)
- [Relatório demonstrativo em HTML](outputs/reports/relatorio-demonstracao.html)

Esses quatro arquivos usam somente dados sintéticos e são mantidos no repositório como exemplos. Outros conteúdos de `outputs/`, assim como dados, caches e lotes reais, permanecem ignorados pelo Git.

Antes da coleta, edite `config.yml`:

1. confirme que a autorização institucional cobre a coleta automatizada;
2. substitua `pesquisa@example.org` por um contato real no `user_agent`;
3. confirme a frequência permitida e mantenha `authorized: true` somente enquanto a autorização for válida.

Então execute:

```bash
Rscript scripts/update_data.R
```

O snapshot bruto vai para `data/raw/AAAA-MM-DD/`; a base sem campos livres potencialmente identificadores vai para `data/processed/`.

## Rede OpenStreetMap

Obtenha um extrato `.osm.pbf` cuja data e origem possam ser citadas. Preferencialmente, recorte-o pelo limite oficial do município e registre a licença ODbL. Depois:

```bash
Rscript scripts/prepare_network.R data/osm/sao-paulo.osm.pbf limite_municipal.gpkg
```

São gerados `network_foot.rds`, `network_bicycle.rds` e `network_motorcar.rds`. Sem esses arquivos, as cinco métricas geométricas continuam disponíveis e a interface informa a ausência da rede.

## Consulta em R

```r
cfg <- read_sampa_config()
equipamentos <- load_equipment_data(cfg)
grafos <- load_network_graphs(cfg)

origens <- data.frame(
  query_id = c("centro", "cep_exemplo"),
  latitude = c(-23.5505, NA),
  longitude = c(-46.6333, NA),
  cep = c(NA, "01001000"),
  k = 10,
  radius_m = 5000
)

resolvidas <- resolve_origins(origens, cfg)
resultado <- calculate_proximity(
  resolvidas$valid, equipamentos, grafos,
  directions = "both", config = cfg
)
```

Uma linha do resultado representa `origem × equipamento × métrica × sentido`. `distance_m` é sempre expresso em metros; `duration_min` só existe para caminhos de menor tempo. O conjunto devolvido é a união dos `k` primeiros e dos pontos dentro do raio para cada métrica.

## Lotes

Arquivo mínimo por coordenadas:

```csv
query_id,latitude,longitude,k,radius_m
q1,-23.5505,-46.6333,10,5000
q2,-23.6200,-46.7000,20,3000
```

Ou por CEP:

```csv
query_id,cep,k,radius_m
q1,01001000,10,5000
```

```bash
Rscript scripts/batch.R --input=origens.csv --output=outputs/meu-lote --modes=foot,bicycle,motorcar --direction=both
Rscript scripts/worker.R
```

O worker grava partições Parquet, erros por linha, manifesto, progresso e checkpoint. Não há log de coordenadas. Artefatos web vencem conforme `retention_days`; a linha de auditoria permanece no SQLite.

## Relatórios e testes

```r
render_proximity_report(resultado, "outputs/relatorio.html", resolvidas$valid, equipamentos, cfg)
render_proximity_report(resultado, "outputs/relatorio.pdf", resolvidas$valid, equipamentos, cfg)
```

```bash
Rscript -e 'testthat::test_local()'
R CMD check . --no-manual
```

## Reprodutibilidade e implantação

`_targets.R` descreve a linhagem da coleta até o Parquet processado. Use `renv::restore()` para restaurar versões. Na implantação, execute aplicação e worker como processos separados:

```bash
docker compose up --build
```

Os diretórios `data/`, `jobs/` e `outputs/` ficam fora do Git. Armazene snapshots e relatórios científicos em repositório institucional com controle de acesso, política de retenção e DOI quando apropriado.

## Citação e licenças

Código: MIT. Dados Sampa+Rural: cite a Prefeitura de São Paulo e cada fonte parceira indicada no cadastro. Rede: cite OpenStreetMap contributors e respeite ODbL. Geocodificação: cite BrasilAPI e a fonte subjacente informada na resposta. Registre no manuscrito as datas exatas dos snapshots.
