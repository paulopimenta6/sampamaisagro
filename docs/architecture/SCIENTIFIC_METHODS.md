# Métodos científicos — capacidades candidatas da v0.3

Data: 17/09/2026. Estado: catálogo de capacidades e condições de uso; nenhuma
análise nova foi implementada ou executada nesta etapa.

## 1. Arquitetura, protocolo e interpretação

A arquitetura oferece capacidades. O protocolo da pesquisa define pergunta,
unidade, população de referência, modalidade principal, custos, hipóteses,
contrastes e critérios de diagnóstico. Nenhuma modalidade, incluindo caminhada,
será escolhida como principal por decisão arquitetural.

Uma capacidade candidata não é uma entrega científica automaticamente ativada.
Antes de sua implementação ou aplicação específica, registrar método,
parâmetros, insumos e testes correspondentes. Métodos não selecionados continuam
documentados como candidatos, sem alegação de validação.

Premissas comuns:

- Perfis publicados não equivalem a instalações físicas únicas ou a um censo
  completo das oportunidades existentes.
- A análise principal de localização utiliza coordenadas oficiais válidas.
  Eventuais coordenadas derivadas permanecem separadas e exigem sensibilidade.
- Resultados de raio OU top-k descrevem um subconjunto condicionado à seleção.
  Não são distribuição populacional nem universo automático para novos métodos.
- Grupos podem se sobrepor. Agregações devem declarar a unidade e evitar dupla
  contagem entre relatórios e métricas.
- Não se acrescentam implicitamente dados de população, renda, capacidade ou
  demanda. Inferência causal e afirmações de equidade exigem outro desenho.

## 2. Qualidade e disponibilidade de coordenadas

### Variáveis e denominadores

Incluir explicitamente `has_coordinates`: presença de ambos os campos originais
de coordenadas após reconhecer sentinelas de ausência. Sua interpretação é
distinta de coordenadas válidas, elegíveis no território ou roteáveis. Um par
preenchido fora da faixa válida não se torna ausência silenciosamente.

Manter `coordinate_status` e estados adicionais necessários para distinguir
ausência de um ou ambos os campos, erro de interpretação, invalidade, exclusão
territorial e conectividade. Coordenada derivada não muda a disponibilidade
original representada por `has_coordinates`.

Relatar denominadores por estágio: base completa, base filtrada, presença de
coordenadas, elegibilidade espacial, roteabilidade e seleção. A tabela de
qualidade do relatório usará o universo anterior à exclusão espacial; filtros
e snapshot são fixados no início da consulta. Em estrato sem registros, a
proporção será não estimável, não zero por conveniência.

### Análise estratificada

Comparar disponibilidade por categoria, fonte, relatório, grupo, snapshot e
atributos oficiais pertinentes. Distrito/zona declarados podem apoiar análises
tabulares quando disponíveis, sem inventar coordenadas ou atribuição territorial.
Reportar tamanho de cada estrato e ausência das próprias covariáveis.

Separar ausência estrutural do campo num relatório de ausência do valor em um
perfil. A conciliação não deve transformar omissão estrutural de um temático em
perda da coordenada disponível na base de referência.

### Modelo logístico exploratório

Prever como capacidade candidata um modelo binomial/logístico exploratório de
disponibilidade, com `has_coordinates` como resposta e atributos observados
selecionados pelo protocolo. Seu objetivo é descrever associações com a
disponibilidade da localização.

Registrar universo elegível ao modelo, tratamento de covariáveis ausentes,
categorias raras, separação, convergência, ajuste e incerteza. Não ajustar
automaticamente em estratos sem variação na resposta. Não interpretar falha ou
instabilidade como ausência de associação.

**Nenhuma conclusão automática de MAR/MNAR** será produzida. Associações
observadas, desempenho preditivo ou ausência de significância não identificam
por si só o mecanismo de ausência, nem validam imputação geográfica.

**IPW somente como eventual análise de sensibilidade**, mediante justificativa
do protocolo. Se adotada, registrar estimando, modelo das probabilidades,
positividade/suporte, distribuição e eventual truncamento dos pesos e comparação
com a análise sem ponderação. IPW não recupera coordenadas desconhecidas nem
garante correção de seleção não observada; não será correção padrão da base.

## 3. Métricas de acessibilidade

Capacidades propostas, calculadas por origem, categoria, modalidade, sentido e
versão das fontes:

- menor custo a uma oportunidade cadastrada;
- quantidade de oportunidades dentro de limiares de distância ou tempo;
- proporção das origens avaliadas com pelo menos uma oportunidade alcançável;
- índice de oportunidades com decaimento, com função e parâmetros explícitos;
- comparação entre modalidades, sentidos, snapping, snapshots e escalas.

A unidade inicial de oportunidade é o perfil. Cobertura territorial e cobertura
das origens analisadas não serão chamadas de cobertura populacional. Não se
implementará 2SFCA sem oferta/capacidade e demanda adequadas.

Esses indicadores devem consumir custos suficientes para o estimando; não
podem usar apenas a tabela truncada de vizinhos quando isso omitir oportunidades
necessárias. Ausência de caminho, snapping excluído e cálculo pendente serão
estados distintos, jamais custo zero ou ausência comprovada de equipamentos.

## 4. Rota principal e descritores candidatos

A primeira versão do engine validará a reconstrução da **rota principal** para
`shortest` e `fastest`, respeitando modalidade e direção. Não incluirá rotas
alternativas, k-shortest paths ou diversificação de trajetos.

Cada rota deve guardar a sequência de arestas e sua versão de grafo. Conectores
estimados serão separados dos trechos observados na rede. Empates de custo
exigem uma rota principal válida e uma política reproduzível de apresentação;
não exigem produzir todas as soluções equivalentes.

| Descritor candidato | Definição e cuidados a registrar antes da ativação |
|---|---|
| `circuity_ratio` | Razão entre comprimento do percurso e distância geodésica; declarar inclusão dos conectores; denominador zero produz estado indefinido |
| `directional_asymmetry` | Diferença ou razão de custo entre ida e volta do mesmo par, modalidade e objetivo; fórmula/unidade explícitas; não combinar execuções incompletas |
| `edge_count` | Número de arestas percorridas na representação declarada; usar sequência expandida quando houver contração |
| `turn_count` | Mudanças de direção segundo regra geométrica/topológica e limiar angular declarados; não contar automaticamente todo vértice como conversão |
| `intersection_count` | Interseções atravessadas segundo topologia e definição modal versionadas; distinguir junção de segmentação e arestas reversas |
| `connector_distance` | Distância total dos conectores e componentes de origem/destino, em metros |
| `connector_share` | Participação dos conectores na distância total; explicitar denominador e caso de custo total zero |
| Road class composition | Participação do comprimento por classe de via; manter classes desconhecidas e separar conectores |
| Surface composition | Participação do comprimento por superfície declarada; não imputar pavimentação quando o atributo faltar |
| Missing OSM attribute share | Participação do comprimento sem cada atributo OSM usado; informar atributo e denominador, sem misturar ausência estrutural e valor desconhecido |

Custos, contagens e composições dependem da representação da rede. Registrar
contração/expansão, segmentação, regras de interseção, cobertura do extrato e
versão do algoritmo. Descritores sem suporte nos dados retornarão indisponibilidade
ou cobertura parcial explícita, em vez de valores fabricados.

Não inferir calçadas adequadas, segurança, acessibilidade física ou permissão
observada de passagem apenas desses descritores e dos perfis OSM.

## 5. Isodistâncias, isócronas e alcançabilidade

A decisão de alcançar uma oportunidade deriva do custo de rede calculado para
o par, com conectores e direção explícitos. Distância usa metros; tempo usa
segundos internamente, com conversão documentada para minutos na apresentação.

Polígonos de isócrona/isodistância são produtos cartográficos. Não utilizar
teste ponto-no-polígono como mecanismo principal de seleção de oportunidades.
Uma envoltória pode incluir vazios, barreiras e componentes não alcançáveis.

Ao calcular alcance desde um ponto fora da rede, contabilizar o orçamento
consumido pelo conector da origem. Para oportunidades, contabilizar também o
conector do destino. Distinguir alcance de vértices/trechos do alcance dos
equipamentos fora desses vértices.

Registrar método de construção do contorno, parâmetros, limiar, sentido, grafo,
tratamento das bordas e eventual degeneração geométrica. Uma falha do polígono
não deve apagar custos válidos; contorno visual válido não prova conectividade.
Respeitar a compatibilidade `sf`/`sc` descrita na
[arquitetura proposta](TARGET_V0.3.md).

## 6. Catálogo de estatística espacial candidata

As capacidades abaixo permanecem candidatas. Disponibilidade de um pacote no
ambiente não equivale a método implementado, validado ou adequado à pesquisa.

| Capacidade | Unidade/condições mínimas de interpretação |
|---|---|
| Global Moran's I | Variável territorial e matriz de pesos especificadas; declarar hipótese, distribuição de referência e componentes isolados |
| Geary's C | Mesmas exigências de alinhamento territorial e pesos; interpretação própria, sem tratá-lo como repetição do Moran |
| Local Moran/LISA por permutação | Hipótese de permutação, sementes, número de permutações e correção das comparações locais |
| Getis-Ord Gi* por permutação | Vizinhança, inclusão do próprio local, esquema de permutação e multiplicidade explícitos |
| KDE | Janela, projeção métrica, largura de banda, correção de borda e unidade de intensidade |
| F, G e J | Janela de observação e correção de borda; distinguir distância de espaço vazio e entre eventos |
| K e L | Escala de distâncias, correção de borda e hipótese de referência |
| K/L inhomogeneous | Estimativa de intensidade e hipótese de inhomogeneidade registradas |
| Pair correlation | Escala, suavização e correção de borda explícitas |
| Pair correlation inhomogeneous | Requisitos anteriores e modelo/estimativa de intensidade |
| Cross-type analysis | Definição das marcas/tipos; tratar sobreposição de categorias e hipótese de independência ou rotulagem |
| Monte Carlo envelopes | Modelo nulo, estatística, sementes, número de simulações e envelope pontual ou global declarados |
| GAM espacial | Família, offset, suavização, covariáveis, convergência e diagnósticos |
| Análise multiescala | Escalas predefinidas e interpretação de sensibilidade/MAUP, sem escolher retrospectivamente a mais favorável |
| Validação espacial em blocos, quando aplicável | Objetivo preditivo, separação espacial, tamanho dos blocos e prevenção de vazamento de informação |

O conjunto espacial deve ter janela territorial explícita e exclusões
documentadas. A extensão dos pontos observados não substituirá silenciosamente
o território de pesquisa. Uma grade será fixada por território, origem e
resolução; pontos sobre bordas terão atribuição determinística.

Perfis distintos na mesma coordenada não serão eliminados ou deslocados por
jitter silencioso. Análises que exijam processo pontual simples devem explicar
o tratamento de coincidências e apresentar sensibilidade quando pertinente.

A ausência seletiva de coordenadas limita o padrão espacial observável.
Modelar intensidade ou autocorrelação não elimina esse viés. Hipóteses nulas
de aleatoriedade espacial exigem justificativa substantiva para o ambiente urbano.

## 7. Diagnóstico, reprodução e publicação

Cada método selecionado produzirá resultados e metadados: universo, denominador,
filtros, modalidade quando aplicável, território, CRS, snapshots, unidades,
parâmetros, sementes, versões, diagnóstico e limitações.

Falhas, não convergência, insuficiência de dados e métodos não aplicáveis terão
estados explícitos. Covariáveis ausentes não serão removidas da fórmula sem
aviso; áreas não positivas não serão corrigidas silenciosamente com epsilon.

Preservar a comparação de métricas já existente, identificando o subconjunto
comum e o condicionamento por seleção. Inferência adicional requer desenho
que considere dependência espacial, repetição entre métricas e multiplicidade.

O protocolo escolherá os métodos e limiares científicos antes da análise
correspondente. Esta documentação não define uma modalidade principal, nem
um resultado científico a ser alcançado. Gates futuros constam dos
[critérios de aceitação](../migration/V0.3_ACCEPTANCE_CRITERIA.md).
