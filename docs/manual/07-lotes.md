# 7. Consultar várias origens e identificar erros por linha

**Sua tarefa:** obter resultados para duas origens e explicar por que uma terceira falhou. Um lote é uma tabela em que **cada linha é uma origem**. A interface aceita até 100 origens por execução.

1. Em **Lotes**, escolha **Baixar exemplo de lote** para conhecer o formato de entrada. Para o exercício de diagnóstico, use o [arquivo de três linhas do repositório](../../inst/examples/origens-reais.csv). O modelo baixado na tela e esse exercício são arquivos diferentes.
2. Abra o arquivo em um editor de texto ou importe-o na planilha definindo a coluna `cep` como **texto**. A primeira linha de dados usa `05586001`. A segunda usa o par de coordenadas da Praça da Sé. A terceira usa `99999999` para exemplificar um CEP ausente do índice preparado. Na sua instalação, confira o cache antes de prever os resultados.
3. Confira `query_id` único por linha. Informe CEP **ou** o par latitude/longitude. Use ponto para decimais no CSV de exemplo. `k` e `radius_m` podem ser definidos por linha. Quando faltam na interface, valem os parâmetros da tela. Confira em **Explorar** os grupos, a acessibilidade, os modos e o sentido que serão aplicados ao lote.
4. Escolha o arquivo em **Lotes** e acione **Analisar lote**. A interface lê CSV, TSV, planilha Excel e Parquet. Comece apenas com geometria. As abas **Explorar** e **Estatísticas** recebem os resultados. Ao comparar linhas, mantenha visíveis a origem, a métrica e o sentido.
5. Ao terminar, leia a tabela de erros e escolha **Baixar pacote do lote (.zip)**. Descompacte em uma pasta local com o nome do exercício. Abra primeiro `manifest.json`. Leia `status`, `complete`, `valid_rows` e `error_rows`. Um lote concluído pode ter linhas inválidas. Em `errors.csv`, use a coluna de linha, o identificador e a mensagem para corrigir a entrada.

**O que há no pacote.** `results.csv` contém os pares, `statistics.csv` resume os pares, `origins.csv` descreve as origens resolvidas e `routing-diagnostics.csv` registra diagnósticos disponíveis. As partes `part-*.parquet` guardam resultados por etapa e podem ser lidas no R. O ZIP contém localização de origens. Compartilhe apenas o que for apropriado para o estudo.

**Se precisar interromper.** Use **Cancelar lote** e registre a situação do manifesto. Fechar ou recarregar a página encerra o trabalho daquela sessão. Para retomar lotes maiores por partes, use a [operação por terminal ou R](operacao.md).

**Exercício e gabarito.** Com o primeiro CEP preparado, a coordenada válida e o terceiro CEP ausente, espere duas origens resolvidas e uma linha com erro de geocodificação. Essa linha não demonstra que seu entorno tem zero equipamentos. Corrija a origem, guarde o arquivo corrigido com outro nome e refaça a consulta. Se os três resultados forem diferentes do previsto, explique-os pelos campos reais do manifesto e do arquivo de erros.

[Índice do manual](README.md) · [Capítulo anterior](06-estatisticas.md) · [Próximo capítulo](08-instalacao.md)
