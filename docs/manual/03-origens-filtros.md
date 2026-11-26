# 3. Escolher de onde partir e o que procurar

**Sua tarefa:** repetir a busca mudando uma única escolha. Em **Explorar**, uma origem é o ponto de partida. Use uma referência pública ou fictícia para aprender. A tabela e os arquivos exportados podem guardar informações de localização.

1. Escolha **Latitude e longitude**. Digite latitude `-23.55008` e longitude `-46.63408`, usadas no arquivo de exemplo do projeto. São graus decimais no sistema WGS 84. Preserve os sinais e os campos: latitude vem primeiro na tela. Essa origem funciona offline sem consulta a um serviço de CEP.
2. Para comparar com uma busca por **CEP**, troque o método e use apenas o CEP preparado. O geocodificador associa um ponto aproximado ao código postal. A distância se refere a esse ponto. Anote o método e a origem para não atribuir a um imóvel a precisão do cadastro postal.
3. Volte às coordenadas do passo 1. Em **Tipos de equipamento**, deixe o campo vazio para incluir todos os grupos. Execute e registre a menor distância por Karney. Escolha então **Hortas urbanas e institucionais** e repita com os demais parâmetros idênticos. A seleção de vários grupos inclui quem pertence a pelo menos um dos escolhidos.
4. Em **Acessibilidade declarada**, o filtro oferece **Todos (inclusive não informada)** ou **Somente informada como sim**. O campo da base pode indicar sim, não ou não informada. Ao escolher somente sim, entram as fichas com declaração afirmativa. Leia o resultado na tabela e conte novamente. A declaração se refere ao cadastro do equipamento; o percurso pode ter degraus, travessias ou barreiras sem registro.
5. Depois de cada alteração, use **Encontrar equipamentos**. Os parâmetros são capturados no início da execução. Anote origem, método, grupos, filtro, raio, k, métrica e snapshot para reconstruir a consulta.

**Como conferir.** Se o resultado mudar muito, refaça o primeiro conjunto de escolhas e compare a mesma métrica. Se a coordenada parecer colocar a origem em outro lugar, reveja latitude, longitude e sinais antes de interpretar os números. Se o filtro deixar o resultado vazio, confira se há perfis mapeáveis no grupo e quantos têm a declaração desejada.

**Exercício.** Duas hortas têm acessibilidade “não informada” e uma tem “informada: sim”. Todas atendem aos demais critérios. Quantas passam por cada filtro? **Gabarito:** as três passam por “Todos” e uma passa por “Somente informada como sim”. A situação das outras duas permanece desconhecida.

[Índice do manual](README.md) · [Capítulo anterior](02-cadastro.md) · [Próximo capítulo](04-raio-ranking.md)
