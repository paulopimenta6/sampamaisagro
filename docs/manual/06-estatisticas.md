# 6. Ler o resumo, a curva acumulada e os arquivos exportados

**Sua tarefa:** responder “qual fração dos pares selecionados está a até 1 km?” e dizer exatamente quais pares foram medidos. Faça uma consulta e abra **Estatísticas**.

1. Em **Resumo por origem e métrica**, escolha uma linha identificando `origin_id`, `metric_id` e `direction`. Examine primeiro `pares_retidos`, `pares_distancia_valida` e `pares_distancia_ausente`. Retidos = válidos + ausentes. Os quantis usam **somente distâncias finitas**. Sem valor finito, o resumo numérico fica `NA` (indisponível). Já `no_raio` conta as marcações verdadeiras de `within_radius`.
2. Leia o mínimo como o menor comprimento entre os pares retidos naquele estrato. P25 é o primeiro quartil, mediana é o ponto central e P75 é o terceiro quartil. O intervalo interquartil (IQR) é P75 menos P25. O P90 situa a parte alta da distribuição. O sistema usa interpolação entre posições: um quantil pode ficar entre duas distâncias observadas.
3. Em **Explorar**, use **Relatório HTML** após a execução terminar com resultados disponíveis. No relatório, encontre o resumo e a curva de distribuição acumulada empírica (ECDF). Procure a origem, a métrica e o sentido da curva e seu n válido na tabela. Para um limite no eixo horizontal, a altura dá a fração de distâncias válidas menores ou iguais àquele limite.
4. A leitura equivalente por tabela usa o mesmo estrato do **Resultados CSV**. Conte quantas distâncias finitas atendem ao limite e divida pelo total de distâncias finitas. Se a pergunta usa 1 km, compare `distance_m` com **1.000**. O histograma na tela agrupa distâncias em faixas; use a tabela para uma contagem exata.

## Gabarito com dois pares

Retome os **300 e 900 m** selecionados no [capítulo 4](04-raio-ranking.md). Há dois pares válidos. O mínimo é 300 m, P25 é 450 m, a mediana é 600 m, P75 é 750 m, IQR é 300 m, P90 é 840 m e o máximo é 900 m. A curva vale **0** antes de 300 m, **0,5** de 300 m até antes de 900 m e **1** a partir de 900 m. A até 500 m está 1/2. A até 1 km estão 2/2. O cadastro original também tinha um perfil a 1.400 m que ficou fora da seleção.

**Se os totais divergirem.** A tabela de **Explorar** exibe a métrica escolhida. O CSV exporta as métricas calculadas. Confira o estado final em `analysis_status` e o andamento em `completed_units` e `total_units`. Um cancelamento ou falha pode deixar resultados parciais disponíveis. O relatório informa a situação quando recebe esses metadados. Na tela, a qualidade em **Banco offline** refere-se à base consolidada; no relatório, a tabela de qualidade depende do conjunto fornecido a ele.

**Exercício.** Se uma tabela fornecida ao resumo tivesse os mesmos 300 e 900 m mais uma linha sem distância, qual denominador usaria na curva? **Gabarito:** dois, entre três pares retidos. A linha ausente não vira zero. As falhas de roteamento anteriores à seleção exigem consultar o diagnóstico. Para obter PDF pelo R, veja o [capítulo 9](09-consulta-em-r.md).

[Índice do manual](README.md) · [Capítulo anterior](05-distancias.md) · [Próximo capítulo](07-lotes.md)
