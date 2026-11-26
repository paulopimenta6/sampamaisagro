# 10. Descobrir em que sentido duas métricas concordam

**Sua tarefa:** responder separadamente “a ordem mudou?”, “os primeiros são os mesmos?” e “de quantos metros foi a diferença?”. Tenha um resultado longo do capítulo anterior ou use o conjunto didático abaixo. Compare dentro da mesma origem e identifique a métrica e o sentido de cada lado.

| Pergunta | O que ler | Quem entra na conta |
|---|---|---|
| A ordem foi preservada? | `spearman_rho` e `kendall_tau`. Valores próximos de 1 indicam ordens semelhantes e de −1 indicam inversão. | Equipamentos comuns com ranks válidos em ambos os lados, `n_rank_common`. |
| Os conjuntos top-k coincidem? | `top_k_jaccard`. Divida o tamanho da interseção pelo tamanho da união dos conjuntos. | Todos os IDs com rank válido até k, selecionados separadamente em cada lado. |
| Qual foi a diferença em metros? | Mediana, P25, P75, IQR, média, DP e limites descritivos das diferenças A − B. | Mesmo `origin_id` e `equipment_id` presentes em ambos os lados com distâncias finitas, `n_distance_common`. |

## Laboratório com resposta conhecida

No **console do R**, a partir da raiz, execute:

~~~r
pkgload::load_all(".")
a <- data.frame(origin_id = "praca", equipment_id = c("feira", "horta"),
                metric_id = "a", direction = "symmetric",
                rank = 1:2, distance_m = c(300, 900))
b <- transform(a, metric_id = "b", distance_m = c(400, 1000))
pares <- rbind(a, b)
acordo <- metric_agreement(pares, k = 2L)
acordo[, c("metric_a", "direction_a", "metric_b", "direction_b",
           "n_a", "n_b", "n_common", "common_pct_a", "common_pct_b")]
acordo[, c("n_rank_common", "spearman_rho", "kendall_tau", "top_k_jaccard",
           "n_distance_common", "median_difference_m", "iqr_difference_m")]
~~~

1. Confira a **cobertura** antes de interpretar correlações. Aqui `n_a = n_b = n_common = 2` e a interseção cobre 100% de cada lado. A cobertura pode ser assimétrica. Se A contém 100 equipamentos e B contém 2, ambos comuns, as coberturas são 2% e 100%.
2. Confira a **ordenação e a seleção**. Feira e horta continuam nas posições 1 e 2. Spearman e Kendall valem 1. Os dois conjuntos top-2 são idênticos, logo Jaccard vale 1. Com conjuntos não vazios e disjuntos, Jaccard vale zero. Com ambos vazios, fica `NA`. Com menos de dois ranks comuns válidos ou sem variação de ranks, as correlações ficam `NA`.
3. Confira os **metros**. As diferenças são 300 − 400 e 900 − 1.000: ambas −100 m. Média e mediana valem −100 m e IQR vale zero. O sistema ordena os identificadores de métrica e depois os sentidos para atribuir A e B. Inverter a ordem das linhas de entrada preserva esse sinal. Os rótulos A e B definem a orientação da subtração e têm o mesmo estatuto científico.
4. Leia os limites de Bland–Altman como **média das diferenças ± 1,96 desvios-padrão das diferenças**, com pelo menos dois pares válidos. Neste exemplo, ambos são −100 m. Eles descrevem a dispersão observada. A forma da distribuição, a variação da dispersão com o comprimento dos trajetos e a dependência espacial limitam sua interpretação. Não são intervalos de confiança.

**Para os seus dados.** Use `metric_agreement(resultado, k = 5L)` se esse for o k da sua consulta. Para lotes com k diferentes, separe as origens e aplique o k correspondente antes de reunir as tabelas. Guarde a cobertura e o n de cada pergunta. Em `fastest`, os ranks comparam a ordem pelo tempo e as diferenças medem os comprimentos das rotas escolhidas. Se houver erro de duplicação no pareamento, procure repetições de origem, equipamento, métrica e sentido antes de combinar arquivos.

**Exercício.** Os top-2 são {feira, horta} e {horta, mercado}. Qual é o Jaccard? **Gabarito:** um equipamento comum e três na união, portanto 1/3. Apenas a horta desses dois conjuntos é comum aos dois top-2. Para a análise de diferenças, examine a interseção dos conjuntos **retidos completos**, que pode incluir outros pares.

[Índice do manual](README.md) · [Capítulo anterior](09-consulta-em-r.md) · [Próximo capítulo](11-moran.md)
