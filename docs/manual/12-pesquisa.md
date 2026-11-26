# 12. Decidir quando modelar e escrever uma conclusão defensável

**Sua tarefa:** escolher a análise que responde à pergunta e deixar informações suficientes para outra pessoa repeti-la. Use o [protocolo analítico](../../PROTOCOL.md), a grade do [capítulo 11](11-moran.md) e uma folha de registro. Os modelos existentes são exploratórios.

## Antes de ajustar

1. Escreva a pergunta em uma frase. “Quantos perfis de hortas cadastrados e mapeáveis estão a até 2 km destas origens?” pede contagens e descrição da cobertura. “Como a intensidade de perfis por km² varia entre células segundo determinada característica?” pode motivar um modelo de contagem.
2. Fixe a unidade, o snapshot, as exclusões, o domínio, a escala e as variáveis antes de olhar os coeficientes. Registre a origem e a data de qualquer covariável territorial. A base de proximidade sozinha não mede renda, população atendida ou consumo de alimentos.
3. Examine contagens e áreas, células vazias e avisos de qualidade. Um grande número de zeros pode ter várias explicações: domínio muito amplo, células pequenas, cobertura desigual ou baixa intensidade. Relate o número de zeros e investigue sua distribuição antes de escolher uma família.

## Ler o ajuste existente

No **console do R**, após criar `grade` no capítulo 11, execute este exemplo didático. Ele usa contagem e área, sem adicionar covariáveis.

~~~r
ajuste <- fit_spatial_count_model(grade, count_col = "equipment_n")
ajuste$selected_family
ajuste$dispersion
ajuste$warnings
summary(ajuste$model)
ajuste$moran
~~~

O Poisson modela a contagem esperada. O `offset(log(área_km²))` incorpora a área como exposição com coeficiente fixo 1. Assim, duas células com a mesma intensidade, uma com área duas vezes maior, têm contagens esperadas em razão 2. Neste exemplo com apenas intercepto, `exp(coef(ajuste$model)[1])` expressa a intensidade estimada de perfis por km². Para incluir preditores, é preciso tê-los nas colunas da grade, documentar suas unidades e conferir os termos de `formula(ajuste$model)`.

**Sobredispersão** indica variação maior que a esperada sob Poisson. A função calcula a soma dos resíduos de Pearson ao quadrado dividida pelos graus de liberdade residuais. Quando o ajuste de binomial negativa está disponível e a dispersão é finita e supera 1,5, o código seleciona esse ajuste. Registre também avisos, convergência, quantidade de células e compatibilidade com o desenho. O limiar implementado é uma regra exploratória do programa. Não demonstra por si só a adequação científica da família.

**Dois usos de Moran.** No capítulo 11, os valores permutados são a contagem ou a densidade observada em cada célula. Aqui, `ajuste$moran` examina **resíduos de Pearson** do modelo escolhido com `spdep::moran.test()`, quando disponível, usando Queen e pesos padronizados por linha. O resíduo expressa quanto a contagem se afasta da esperada pelo modelo. Autocorrelação residual sugere estrutura espacial ainda presente. `NULL` indica que esse diagnóstico não foi obtido. Relate qual dos dois procedimentos usou.

**Exercício.** Uma região tem maior densidade de perfis por km² e um modelo apresenta sobredispersão. Pode-se concluir que seus moradores têm melhor alimentação? **Gabarito:** a densidade descreve a distribuição dos perfis cadastrados em relação à área. A dispersão descreve o comportamento do modelo de contagem. Para falar de alimentação seriam necessários desfechos, população, desenho e controle de vieses adequados. Uma conclusão defensável identifica domínio, período, fontes e limitações de cobertura. Use o [projeto integrador](projeto-final.md) para escrever a sua.

[Índice do manual](README.md) · [Capítulo anterior](11-moran.md)
