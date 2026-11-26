# 11. Estudar se células vizinhas têm valores semelhantes

**Sua pergunta:** depois de agregar os perfis em células de um território fixo, os valores de células vizinhas são mais parecidos ou mais diferentes do que esperaríamos ao redistribuir os valores entre as células? Este capítulo usa a API em **R**, com os pacotes `sf` e `spdep`. A unidade de análise agora é uma **área**. Os equipamentos individuais são a entrada da agregação.

## Construir uma grade que possa ser comparada

1. Defina previamente o grupo de perfis, o limite territorial externo (*boundary*), a escala e a variável. Para comparar grupos ou períodos, use o mesmo domínio. Um domínio derivado dos pontos com `boundary = NULL` atende à exploração inicial, mas pode mudar de forma quando os pontos mudam. Duas contagens em domínios diferentes têm bases de comparação diferentes.
2. Passe os **perfis elegíveis**, uma linha por perfil, a `create_hex_grid()`. Evite usar a tabela longa da consulta, que repete perfis entre métricas. No exemplo, um retângulo fixado para fins didáticos, na região de São Paulo, contém os 12 pontos de `demo_equipment()`. Em um estudo municipal, substitua-o pelo polígono de referência documentado.
3. No **console do R**, na raiz, execute:

~~~r
pkgload::load_all(".")
perfis <- validate_equipment(demo_equipment())$eligible
caixa <- sf::st_bbox(c(xmin = -46.82, ymin = -24.00, xmax = -46.40, ymax = -23.39),
                     crs = sf::st_crs(4326))
limite <- sf::st_sf(geometry = sf::st_as_sfc(caixa))
grade <- create_hex_grid(perfis, cell_size_m = 5000, boundary = limite)
c(celulas = nrow(grade), perfis_contados = sum(grade$equipment_n),
  celulas_vazias = sum(grade$equipment_n == 0))
head(sf::st_drop_geometry(grade)[, c("hex_id", "equipment_n", "area_km2", "density_km2")])
~~~

Confira que a soma das contagens é 12 neste domínio. Em geral, compare a soma com os perfis atribuíveis **dentro do limite**. Cada ponto de fronteira conta uma vez. Células vazias ficam na grade com zero. Células cortadas na borda podem ter áreas diferentes. `density_km2` divide a contagem pela área efetiva. Contagem mede perfis por célula, densidade mede perfis por km². Uma taxa por habitante exigiria outro denominador.

## Calcular e interpretar

~~~r
m <- global_moran(grade, value_col = "equipment_n", queen = TRUE, style = "B",
                  nsim = 999L, alternative = "two.sided", seed = 1L)
unlist(m[c("n_cells", "n_zero", "n_islands", "moran_i", "pseudo_p",
           "permutation_mean", "permutation_sd")])
~~~

- **Quem é vizinho?** Queen considera contato por lado ou vértice. Rook exige contiguidade por lado. A matriz W guarda a regra e os pesos. Com `B`, cada ligação recebe peso 1. Com `W`, os pesos são padronizados por linha. Uma ilha tem zero vizinhos. Continua no vetor e nas permutações, com lag espacial zero. Confira `n_islands`, `cell_ids` e `listw`.
- **O que o teste permuta?** As células, a geometria e W ficam fixas. Redistribuem-se os valores territoriais observados, incluindo zeros. `moran_i` é o índice observado; `permutation_values` contém os índices simulados. O pseudo-p compara a posição do observado com essa distribuição, sob a alternativa registrada. Guarde semente, número de simulações, ordem das células e versões.
- **O que escrever?** I positivo indica semelhança entre vizinhos segundo W, e I negativo indica contraste. Um resultado compatível com a distribuição nula fornece evidência insuficiente de autocorrelação global para essa variável e escala. Tendências de larga escala também podem elevar I. O teste global não localiza hot spots nem identifica causas.
- **O que varia com a escala?** Se a pergunta pedir, repita com 1.000, 2.000 e 5.000 m escolhidos previamente, mantendo o domínio. Registre a contagem de células, as áreas, os zeros, as ilhas e a saída de cada escala. Essa sensibilidade à unidade territorial é um aspecto do problema da unidade de área modificável (MAUP). Escolher a escala depois de ver qual produziu o menor pseudo-p distorce a comparação.

## Exercício com gabarito — um índice definido e um teste sem contraste

No **R**, construa quatro quadrados. O `nsim` pequeno abaixo serve ao exercício didático. O padrão científico da função é 999.

~~~r
caixa4 <- sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 2, ymax = 2),
                      crs = sf::st_crs(31983))
quatro <- sf::st_sf(equipment_n = 0:3,
                    geometry = sf::st_make_grid(caixa4, n = c(2, 2)))
tryCatch(global_moran(quatro, "equipment_n", queen = TRUE, style = "B",
                      nsim = 19L, seed = 11L), error = conditionMessage)
rook <- global_moran(quatro, "equipment_n", queen = FALSE, style = "B",
                     nsim = 19L, seed = 11L)
unlist(rook[c("moran_i", "permutation_sd", "pseudo_p")])
~~~

**Resposta esperada.** Com Queen, cada uma das quatro células toca todas as demais. Cada permutação tem I = −1/3. O índice observado é definido, mas a distribuição simulada não varia. A função explica a degenerescência e não devolve pseudo-p. Com Rook, as diagonais deixam de ser vizinhas. Nessa disposição o I observado é zero e as permutações têm variabilidade. Os dois resultados têm interpretações diferentes. A troca de W neste exercício demonstra o método; na pesquisa, a pergunta orienta a escolha de W.

**Se aparecer outro erro.** Confirme que a entrada contém polígonos válidos, que a coluna escolhida é numérica e finita e que existe alguma ligação entre células. Uma variável constante impossibilita calcular o próprio I. Falta de dados pede investigação, enquanto zero observado deve permanecer zero. [Ajuda de global_moran](../../man/global_moran.Rd)

[Índice do manual](README.md) · [Capítulo anterior](10-comparar-metricas.md) · [Próximo capítulo](12-pesquisa.md)
