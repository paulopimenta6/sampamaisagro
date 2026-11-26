# Manual do Sampa+Agro

O Sampa+Agro (SampaMaisAgro na tela) ajuda a responder uma pergunta concreta: **quais perfis de agricultura e alimentação cadastrados pelo Sampa+Rural ficam perto de uma origem, segundo a distância que escolhi?** Uma origem pode ser um CEP ou um par de coordenadas. O aplicativo apresenta pontos, tabelas e estatísticas. Quem usa R também pode repetir a consulta, comparar distâncias e estudar a distribuição dos equipamentos no território.

## Escolha por onde começar

- **[Quero fazer uma consulta](01-primeira-consulta.md).** Se recebeu a aplicação funcionando, basta o navegador. Você vai localizar um equipamento, entender o que o número na tabela mede e guardar o resultado.
- **[Preciso preparar o sistema](08-instalacao.md).** Siga este caminho se recebeu apenas a pasta de código, mudou de máquina ou precisa trabalhar sem internet. Ao terminar, volte à primeira consulta.
- **[Quero analisar os dados em R](09-consulta-em-r.md).** Comece com um exemplo de treinamento que funciona sem baixar o cadastro. Depois reproduza uma consulta da tela e avance até as comparações e a análise territorial.

## Formação completa

| Capítulo | Ao terminar, você conseguirá… |
|---|---|
| [1. Primeira consulta](01-primeira-consulta.md) | Encontrar um registro, ler a distância e conferir o raio pela tabela. |
| [2. Cadastro e qualidade](02-cadastro.md) | Identificar quem entrou na base, quem pôde ser mapeado e qual é o denominador. |
| [3. Origens e filtros](03-origens-filtros.md) | Comparar buscas mantendo as escolhas registradas. |
| [4. Raio, ranking e mapa](04-raio-ranking.md) | Explicar por que aparece um ponto fora do raio. |
| [5. Famílias de distância](05-distancias.md) | Escolher uma medida e interpretar ida, volta, metros e minutos. |
| [6. Estatísticas e exportação](06-estatisticas.md) | Conferir um resumo e uma curva acumulada com lápis e papel. |
| [7. Consultas em lote](07-lotes.md) | Preparar um arquivo, encontrar erros por linha e verificar o que terminou. |
| [8. Instalação e offline](08-instalacao.md) | Preparar, atualizar e reconhecer as cópias locais dos dados. |
| [9. Reproduzir em R](09-consulta-em-r.md) | Passar de um script pequeno ao mapa, CSV e relatório. |
| [10. Comparação entre métricas](10-comparar-metricas.md) | Distinguir ordem, coincidência dos selecionados e diferenças em metros. |
| [11. Análise territorial](11-moran.md) | Agregar os pontos e interpretar um Moran Global por permutação. |
| [12. Modelos e escrita científica](12-pesquisa.md) | Decidir se um modelo cabe na pergunta e documentar as limitações. |

Conclua com o [projeto integrador e seus critérios de revisão](projeto-final.md). Para consulta rápida, abra a [referência por termo, coluna ou sintoma](referencia.md). A [operação avançada](operacao.md) cobre acesso remoto, contêineres, processamento retomável e fila.

## Como estudar e navegar

Leia primeiro os passos numerados. Faça a atividade antes de consultar o gabarito. Os primeiros exemplos numéricos são fictícios e têm respostas fixas. Uma consulta ao cadastro local depende de sua fotografia datada, chamada *snapshot*. Anote o identificador exibido na tela sempre que quiser reproduzir um resultado.

As instruções usam os nomes dos controles e oferecem tabelas e texto para a leitura dos exemplos visuais. Use os títulos para navegar com um leitor de tela ou procure pelo nome da tarefa. No navegador, use Tab e Shift+Tab para avançar e voltar pelos controles, e a ampliação habitual para aumentar o texto. Nos capítulos em R, cada bloco identifica o ambiente e os objetos de que precisa. Os links entre capítulos também funcionam numa cópia local da pasta do projeto.

## De onde vêm as explicações

Os controles descritos correspondem à interface do projeto. O [guia lúdico](../../GUIA_LUDICO.md) oferece uma introdução por analogias. O [dicionário](../../CODEBOOK.md) define os campos, o [caderno de distâncias](../../distancias.md) explica as medidas e o [protocolo](../../PROTOCOL.md) orienta as escolhas de pesquisa. A [ficha de validação](../VALIDACAO_REAL.md) documenta resultados obtidos em uma instalação e data específicas. O [planejamento original](../../PLANEJAMENTO_PROJETO.txt) registra objetivos de desenvolvimento. As instruções práticas deste manual usam os recursos disponíveis no código.
