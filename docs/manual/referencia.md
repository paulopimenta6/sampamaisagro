# Referência rápida — termos, colunas e soluções

Use a busca do seu leitor de Markdown para encontrar um nome de coluna ou o sintoma que apareceu na tela. Os arquivos técnicos usam ponto decimal e nomes em inglês. Na narrativa em português, por exemplo, 0,5 km corresponde a 500 m.

## Palavras que mudam a leitura de um resultado

| Palavra | Significado prático |
|---|---|
| Perfil | Uma ficha consolidada do cadastro. Duas fichas diferentes podem se referir a uma instalação física. |
| Origem / destino | Ponto a partir do qual se faz a pergunta e equipamento para o qual se calcula a proximidade. |
| Par / estrato | Um par liga origem a equipamento. Um estrato reúne linhas com mesma origem, métrica e sentido. |
| Denominador | O conjunto que corresponde a 100%. Na qualidade é o n consolidado da categoria. Na ECDF são os pares retidos com distância válida naquele estrato. |
| Snapshot / manifesto | Cópia dos dados identificada no tempo / arquivo que descreve fontes ou execução. Leia o manifesto correspondente ao que quer verificar. |
| Grafo / snapping | Representação das conexões entre trechos de vias / associação aproximada de um ponto a um vértice da rede. |
| Quartil / ECDF | Valor que separa uma fração dos dados ordenados / fração acumulada das observações até um limite. |
| Cobertura comum | Proporção dos equipamentos de um lado de uma comparação que também estão disponíveis no outro. |
| Permutação / semente | Redistribuição dos valores para construir a referência do teste / número usado para reproduzir a sequência aleatória. |
| Zero / `NA` | Contagem ou distância observada igual a zero / valor indisponível ou estatística sem condições de cálculo. |

## Leitura de colunas

| Onde | Campo | O que conferir |
|---|---|---|
| Entrada de lote | `query_id`, `cep`, `latitude`, `longitude` | Identificador, CEP de oito dígitos como texto ou coordenadas em graus. |
| Cadastro | `equipment_id`, `record_version_id`, `snapshot_date` | Identificação do perfil, da sua versão e do snapshot. |
| Cadastro | `category`, `groups`, `primary_group` | Categoria da fonte, grupos derivados sobrepostos e rótulo principal para exibição. |
| Qualidade | `coordinate_pct`, `spatial_eligible_pct` | Percentuais relativos a todos os perfis da mesma categoria na base recebida. |
| Pares | `origin_id`, `metric_id`, `direction` | Leia os três juntos. `symmetric` indica uma medida geométrica simétrica. |
| Pares | `distance_m`, `duration_min`, `rank` | Metros, minutos modelados quando disponíveis e ordem dentro do estrato. |
| Pares | `within_radius`, `selection_k`, `selection_radius_m` | Indicador de inclusão no raio e parâmetros efetivos da origem. |
| Exportação da tela | `analysis_status`, `completed_units`, `total_units` | Estado e etapas da execução a que pertencem os valores. |
| Resumo | `pares_retidos`, `pares_distancia_valida`, `pares_distancia_ausente` | Quantas linhas chegaram ao resumo e quantas contribuíram para as distâncias. |
| Grade | `equipment_n`, `area_km2`, `density_km2` | Perfis por célula, km² efetivos, perfis por km². |

O [dicionário de dados](../../CODEBOOK.md) detalha outros campos. Os capítulos [6](06-estatisticas.md), [10](10-comparar-metricas.md) e [11](11-moran.md) mostram como calcular e interpretar os principais indicadores.

## Fazer a leitura com teclado, ampliação ou leitor de tela

1. Abra o índice do manual no visualizador Markdown ou navegador. Percorra os títulos para localizar **Formação completa**, ou use Tab até o link **Quero fazer uma consulta** e pressione Enter. Shift+Tab retorna ao link anterior. Se aparecer o texto bruto, escolha a visualização renderizada do Markdown para ter títulos, links e tabelas identificados.
2. No [exercício de seleção](04-raio-ranking.md), navegue até a tabela pelo comando de tabelas do seu leitor. Leia primeiro o cabeçalho **Perfil**. Na linha **Horta B**, associe **900 m**, **posição 2**, **fora do raio** e **entre os dois primeiros**. A explicação numerada logo depois da tabela dá a mesma resposta em ordem de leitura contínua.
3. Na aplicação, procure **Explorar**, os campos identificados pelo rótulo, **Encontrar equipamentos** e a mensagem de situação. Para conhecer o destino encontrado, siga até **Equipamentos encontrados**. Um mapa interativo pode exigir muitos passos pelo teclado. Use a tabela para ler nome, distância, posição e indicador do raio.
4. Ao ampliar a página, uma tabela larga pode exigir rolagem horizontal. Identifique os cabeçalhos antes de ler os valores. O CSV aberto numa planilha permite manter só as colunas de interesse. Para o histograma ou a ECDF, use a contagem tabular do [capítulo 6](06-estatisticas.md) para responder a uma pergunta sobre um limite específico.

**Se o atalho de títulos pular o exercício:** na conferência local com WebKitGTK e Orca, o texto do título do capítulo 4 estava disponível para leitura, mas a camada de acessibilidade também o identificou como quadro. Use a busca de texto por “Por que aparece um equipamento fora do raio?” ou abra o capítulo pelo índice. Se ouvir apenas “cabeçalho de coluna”, avance para a primeira linha ou siga a explicação numerada após a tabela.

## Quando algo parece estranho

| Sintoma | Primeira verificação | Ação |
|---|---|---|
| A página não abre | O processo R está aberto? Qual porta ele anunciou? | Abra o endereço indicado. Para acesso remoto, confira as duas pontas do [túnel](operacao.md). |
| Nenhuma base aparece | A pasta de dados pertence à máquina que executa o R? | Confira a configuração e faça a [preparação inicial](08-instalacao.md) se necessário. |
| CEP desconhecido ou com sete dígitos | Compare o texto de entrada com a tabela de CEPs preparados. | Recupere os oito dígitos da fonte. Se válido e ausente no cache, prepare-o online ou use coordenadas conhecidas. |
| Ponto em local inesperado | Leia os campos e sinais de latitude e longitude. | Corrija a origem e refaça a consulta. |
| Grupo sem equipamentos na tabela | Há registros mapeáveis nesse grupo? O filtro de acessibilidade está ativo? | Confira **Banco offline** e repita alterando um filtro de cada vez. |
| Apareceu alguém além do raio | Veja `rank` e `selection_k`. | Use `within_radius` para contar apenas os que estão dentro. |
| Opção de rede ausente | Confira modos instalados em **Banco offline**. | Prepare o grafo desejado e reinicie a aplicação. |
| Caminho indisponível ou execução parcial | Leia o diagnóstico de rotas e o estado da execução. | Registre o motivo, preserve as partes válidas e compare métricas em conjuntos identificados. |
| CSV maior que a tabela visível | Confira métrica e sentido da tela e do arquivo. | Restrinja o CSV ao mesmo estrato antes de conferir. |
| O pseudo-p de Moran não saiu | Leia o erro: variável constante, valores não finitos, ausência de ligações ou permutações sem contraste? | Confira valor territorial, W e domínio e relate a razão. O [exemplo 2×2](11-moran.md) permite distinguir as situações. |

## Créditos e privacidade

Identifique a Prefeitura de São Paulo, Sampa+Rural e parceiros como fontes do cadastro. Registre IBGE para a malha municipal, © OpenStreetMap contributors e ODbL para a rede, e o provedor e a data para origens por CEP. Preserve snapshot e manifestos. Uma data de download pode diferir da data de referência da rede. Consulte os [créditos e cuidados acadêmicos do projeto](../../README.md).

Para compartilhar um resultado, prefira origens públicas ou agregações territoriais adequadas. Antes de enviar CSV, HTML, PDF ou ZIP, confira origens, coordenadas, endereços, mapas e identificadores. A pasta de dados brutos pode conter contatos. Pacotes de lote, logs e pastas de trabalho merecem acesso restrito, inclusive quando a consulta foi feita offline.

[Índice do manual](README.md)
