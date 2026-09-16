# Protocolo analítico e plano de validade

## Objetivo

Estimar e descrever a acessibilidade espacial a aparelhos cadastrados pelo Sampa+Rural no município de São Paulo, examinando o quanto a conclusão muda conforme a definição operacional de distância.

## Perguntas e hipóteses a pré-registrar

1. Qual é a distribuição da distância ao equipamento mais próximo, por categoria e território?
2. Quantos equipamentos existem dentro de raios pré-especificados?
3. A classificação de proximidade é robusta entre distância elipsoidal, distâncias projetadas e redes modais?
4. Há autocorrelação espacial residual na contagem ou densidade de equipamentos?

Antes da análise confirmatória, fixe: população de origens, categorias incluídas, período/snapshot, `k`, raios, modos, sentido da rede, tamanho da célula, covariáveis, contrastes e correção por múltiplos testes.

## Desenho e unidade de análise

O desenho básico é transversal, observacional e ecológico quando os resultados são agregados. A unidade pode ser origem individual, célula hexagonal ou unidade administrativa. Trocar a unidade após examinar resultados cria flexibilidade analítica e risco de MAUP; análises em escalas alternativas devem ser classificadas como sensibilidade.

## Exposição

Não existe uma única “distância verdadeira”. A análise principal deve declarar uma métrica coerente com o mecanismo teórico. Karney é adequada para separação geodésica; rede de caminhada para acessibilidade pedonal; menor tempo para custo de viagem sob o perfil de velocidades adotado. Manhattan e Chebyshev são cenários geométricos, não substitutos de uma malha viária.

## Qualidade e viés

- **Cobertura:** o cadastro pode omitir iniciativas, e a omissão pode variar territorialmente.
- **Mensuração:** endereço, coordenada, categoria e situação operacional podem estar desatualizados.
- **Geocodificação:** CEP é aproximado; faça análise restrita a coordenadas fornecidas.
- **Rede:** completude OSM, acessos, mão de direção e velocidades afetam caminhos.
- **Seleção:** excluir registros sem coordenadas pode introduzir viés; sempre reporte o denominador e o perfil dos excluídos.
- **Temporalidade:** cadastro, covariáveis e rede devem ter datas compatíveis.
- **Confusão:** associações territoriais podem refletir renda, densidade, uso do solo, centralidade, população e política pública.

## Análise estatística

Relate contagens, cobertura de coordenadas, mediana, IQR, quantis, curvas acumuladas e intervalos de confiança compatíveis com o desenho. Compare métricas por Spearman/Kendall, Jaccard top-k e diferenças de Bland–Altman sem eleger arbitrariamente um padrão-ouro.

Para contagens em células, comece com Poisson e offset de log-área ou log-população, examine sobredispersão e use binomial negativa quando justificado. Inspecione resíduos, influência, não linearidade e Moran; autocorrelação residual exige estrutura espacial ou inferência robusta apropriada. Muitos zeros podem justificar modelo hurdle/zero-inflated apenas com hipótese substantiva e diagnóstico. Resultados são associações, não efeitos causais.

## Sensibilidade

- Coordenadas da fonte versus CEP geocodificado.
- Karney versus Haversine e EPSG:31983.
- Menor distância versus menor tempo; ida versus volta.
- Limiares de snapping 100/250/500/1.000 m.
- Snapshots alternativos do cadastro e da rede.
- Grades de 1, 2 e 5 km e unidades administrativas.
- Inclusão/exclusão de pontos fora do limite oficial e categorias raras.

## Transparência

Publique código, dicionário, ambiente, checksums, manifestos e tabelas agregadas. Não publique origens individuais ou contatos. Diferencie análises confirmatórias, exploratórias e pós-hoc. Registre desvios deste protocolo com data e justificativa.

## Implementação offline e unidade do cadastro (versão 0.2)

Os relatórios do catálogo são arquivados integralmente em CSV e JSON. A base
completa é a referência: removem-se somente repetições de conteúdo idêntico dentro
dela. Os relatórios temáticos são conciliados por nome, categoria, fonte e
endereço, pois alguns omitem coordenadas e outros campos. Perfis não conciliados
podem ser acrescentados, com contagem separada. source_reconciliation.csv e
deduplication.json documentam essas operações.

equipment_id é um identificador de conteúdo, não um identificador oficial
permanente. Mudanças na fonte podem alterá-lo. Perfis diferentes da mesma
instalação podem permanecer separados: a contagem não é um censo deduplicado de
estabelecimentos físicos. Revisão manual de uma amostra e auditoria de colisões
de nome/endereço são necessárias para a dissertação.

A triagem usa o retângulo de config.yml, não um recorte municipal exato. A malha
simplificada IBGE é referência cartográfica e within_municipality marca a
interseção para análise de sensibilidade. Equipamentos adjacentes dentro do
retângulo são mantidos. Coordenadas ausentes não são imputadas.

Os grupos são multirrótulo e derivados de expressões em R/catalog.R sobre nome,
categoria, subcategoria e qualificações. “Orgânico” não é uma certificação
auditada; acessibilidade é uma declaração triestado da fonte.

As consultas usam o índice local de CEPs. Novos CEPs exigem preparação online
explícita. O ponto AwesomeAPI é aproximado e sua precisão em metros não é
conhecida. Compare com referência independente. A mudança de provedor corrige o
caso de regressão identificado, mas não garante a exatidão dos demais CEPs.

## Seleção, ranking e inferência

O conjunto de saída é raio **ou** top-k, por origem/métrica/sentido. Medianas,
quantis, ECDF e concordâncias descrevem esse subconjunto condicionado à seleção.
Informe denominadores por métrica. Linhas repetidas entre métricas não são
observações independentes.

As redes avaliam todos os destinos elegíveis. Menor distância minimiza metros;
menor tempo minimiza o tempo modelado e é ordenado por minutos, embora o filtro
de raio continue em metros. Penalidades de preferência não são confundidas com
distância ou tempo físicos. Conectores retilíneos até o vértice mais próximo são
estimados, não acessos observados. A rede recortada não incorpora trânsito real,
restrições completas de conversão ou condições das calçadas. Pares inalcançáveis
e snapping excluído entram no diagnóstico, nunca como distância zero; não
aparecer na tabela de vizinhos não significa ausência de equipamentos.

Spearman e Kendall comparam os rankings nos pares comuns; Jaccard descreve a seleção
top-k. Para trajetos fastest, o ranking usa tempo modelado, não comprimento.
As diferenças pareadas e os limites de Bland–Altman continuam em metros e são
exploratórios, sem independência espacial validada. O
painel não produz testes causais nem intervalos populacionais automáticos.
Modelos disponíveis na API exigem território, população e diagnóstico definidos
no protocolo específico; não são automaticamente ajustados na consulta.

## Critérios de aceitação verificáveis

- Integridade e contagem compatível dos pares CSV/JSON; hashes registrados.
- CEP 05586-001 resolvido localmente com proveniência preservada.
- Consulta por coordenadas e lote misto; erro em uma linha não invalida as demais.
- Famílias geométricas e modos de rede testados com dados reais.
- Relatórios com mapa, resumo e limitações; exportações reabertas nos testes.
- Navegador sem dependências externas durante consulta, mapas e downloads.
- Diferenciar testes funcionais de validação de acurácia, completude e
  representatividade. Validação de campo continua necessária.
