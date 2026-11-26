# Projeto integrador — entregar uma análise que outra pessoa possa conferir

**Pergunta de trabalho:** “Em duas origens públicas, quais perfis de um grupo cadastrado ficam a até 2 km e quanto a resposta muda entre a separação geodésica e outra métrica escolhida?” Você pode escolher outro grupo, raio ou métrica. Escreva a decisão e sua justificativa **antes** da consulta.

## Preparar, executar e interpretar

1. Crie uma pasta de estudo com identidades de origem que possam ser divulgadas. Com um arquivo de texto, preencha a ficha abaixo. Registre o snapshot, o que representa cada origem, os filtros, a escala de distância e o que você considera uma observação.
2. Use **Banco offline** para registrar a cobertura do grupo e a qualidade da base. Escolha duas origens, prepare a entrada e faça a consulta. Confirme a situação de execução e se as duas origens foram resolvidas. Se uma falhar, registre a mensagem e a decisão tomada.
3. Para cada origem, produza uma linha por métrica e sentido com equipamentos distintos, pares retidos, pares com distância válida, quantidade no raio e mediana em metros. Guarde o CSV, o mapa, uma tabela legível sem mapa e o script ou os parâmetros que geraram os arquivos.
4. Compare as duas métricas em cada origem. Registre a cobertura dos pares, o k, o Jaccard e a mediana das diferenças A − B. Explique ao leitor se a mudança ocorreu na ordem, no conjunto selecionado ou no comprimento. Se houver poucos pares, relate o denominador e o que ficou indisponível.
5. Se sua pergunta também tratar da distribuição territorial, defina o limite externo, a escala, a variável e a vizinhança antes da agregação. Acrescente a tabela de células, o total de perfis dentro do domínio, os zeros, o I observado, o número de permutações, a semente e o pseudo-p ou a razão para a ausência do teste. Inclua modelo de contagens apenas se houver uma pergunta que o justifique.
6. Entregue arquivos identificados e um texto curto, com créditos das fontes e limites da conclusão. Peça a outra pessoa que reconstrua uma linha da tabela com o seu roteiro.

## Ficha para copiar no roteiro da pesquisa

~~~text
Pergunta e unidade de análise:
Fonte, snapshot, versão do projeto e data da análise:
Origem A / origem B e método de localização:
Grupo(s), categoria(s), exclusões e denominadores da cobertura:
Raio em metros, k, métrica principal e métrica de comparação:
Modo, objetivo, sentido e versão da rede, quando usados:
Status da execução, origens válidas e erros:
Pasta de entrada e comandos ou escolhas da tela:
Resultado principal com unidade e denominador:
Limitação que mais afeta a interpretação:
Quais arquivos outra pessoa deve abrir para conferir:
~~~

**Modelo de conclusão para completar.** “Dos ___ perfis cadastrados no grupo ___, ___ eram mapeáveis no snapshot ___. Para a origem ___ e métrica ___, havia ___ perfis no raio de ___ m. A mediana de ___ m descreve ___ pares válidos entre ___ retidos. Comparando com ___, havia ___ equipamentos comuns e a diferença mediana A − B foi ___ m. A interpretação depende especialmente de ___.”

## Critérios para revisar a entrega

| Competência | Evidência verificável |
|---|---|
| Usar a interface | Uma pessoa localiza o equipamento de posição 1 pela tabela, informa metros e confere “No raio?”. |
| Operar offline | Identifica base, CEP preparado e redes locais. Explica qual preparação resolveria um CEP ou grafo ausente. |
| Reproduzir em R | Outra pessoa obtém os mesmos IDs e contagens para o mesmo snapshot e parâmetros. |
| Interpretar | Distingue perfis, pares e células. Justifica denominadores e explica um resultado parcial ou indisponível. |
| Comunicar | Entrega tabela com unidades, mapa com descrição textual, procedência, limites e origens adequadas ao compartilhamento. |

**Gabarito para revisão:** a contagem real muda com o snapshot. A conclusão do estudo precisa ser rastreável até as linhas da entrada e do resultado. Se o colega obtiver contagem diferente, compare primeiro snapshot, grupo, origem, métrica, sentido, raio, k e estado da execução. Se a conclusão afirmar que uma população tem acesso efetivo à alimentação, identifique que dado do estudo mediu esse desfecho. Neste exercício, a evidência disponível é a proximidade aos perfis cadastrados.

[Índice do manual](README.md)
