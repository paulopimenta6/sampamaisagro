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
