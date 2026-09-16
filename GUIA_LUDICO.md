# 🌱 Sua feira de dados: um passeio pelo SampaMaisAgro

Pense na aplicação como uma cesta e um mapa: você escolhe de onde sair, e ela mostra o que está perto — hortas, feiras, agricultores, orgânicos e outros registros do Sampa+Rural.

O aplicativo usa R. Você não precisa escrever código para fazer as consultas pela tela.

## 1. Primeiro, abra a porta

Na pasta do projeto, abra o arquivo app.R e clique em **Run App** no RStudio.

Outra opção, no console R:

~~~r
pkgload::load_all(".")
run_app()
~~~

Se faltarem pacotes, restaure o ambiente com renv::restore(). Os comandos precisam ser executados dentro da pasta do projeto.

O mapa inicial já mostra os dados reais guardados no computador. Não é uma simulação.

### 1.1. Sua feira está no notebook, mas você está em outro computador? 🚇

Imagine um túnel que leva a janela do seu navegador até a aplicação no notebook.
Esse é o **túnel SSH**. O notebook continua fazendo os cálculos e guardando os
dados; o outro computador serve para você ver a tela e fazer as consultas.

~~~text
Seu navegador → túnel SSH → aplicação no notebook
~~~

Você vai usar **dois terminais**, com tarefas diferentes. O projeto e os dados
precisam estar preparados no notebook, e você já deve conseguir acessá-lo por SSH.

#### Passo A — Abra a feira no notebook

Na sessão SSH conectada ao notebook, execute:

~~~bash
cd /home/paulo/Documentos/meus_codigos/sampamaisrual

R_PROFILE_USER=/dev/null Rscript -e 'pkgload::load_all(".", quiet=TRUE); run_app(host="127.0.0.1", port=3939, launch.browser=FALSE)'
~~~

Se a pasta do projeto for diferente, ajuste o caminho. Espere aparecer
`Listening on http://127.0.0.1:3939`. É o aviso de que a feira abriu!
**Deixe essa sessão funcionando.**

#### Passo B — Abra o túnel no computador que está com você

Abra **outro terminal no computador onde você usará o navegador**. Não execute
este passo dentro da sessão SSH do notebook. Digite:

~~~bash
ssh -N -L 127.0.0.1:3939:127.0.0.1:3939 paulo@IP_DO_NOTEBOOK
~~~

Troque `IP_DO_NOTEBOOK` pelo IP ou nome que você usa para entrar no notebook via
SSH. Se seu usuário não for `paulo`, troque esse nome também.

O terminal pode ficar quietinho, sem novas mensagens. Isso é normal: ele está
mantendo o túnel aberto. **Não feche esse terminal.**

#### Passo C — Espie pela janela do navegador

No computador que está com você, abra:

[http://localhost:3939](http://localhost:3939)

Pronto: a tela aparece aí, mas os cálculos continuam no notebook. Não é preciso
copiar a pasta de dados para o computador do navegador.

#### E se a feira já estiver aberta?

Não precisa iniciar a aplicação outra vez! Veja qual porta aparece na mensagem
`Listening on http://127.0.0.1:PORTA` e use esse número no **último `3939`** do
comando SSH. O primeiro `3939` é a porta que você abrirá no navegador.

Se essa primeira porta estiver ocupada no seu computador, troque somente ela
por `9393` e use `http://localhost:9393` no navegador.

**Lembretes para o túnel não fechar:**

- Mantenha as duas sessões abertas.
- Deixe o notebook ligado, conectado e sem entrar em suspensão; fechar a tampa
  pode colocá-lo para dormir.
- Os dados continuam offline, mas os computadores precisam conseguir conversar
  pela conexão SSH.
- Não é preciso abrir a porta `3939` no roteador nem mudar o host para `0.0.0.0`.
- Para fechar só o túnel, pressione **Ctrl+C** no terminal do passo B.

## 2. Encontre algo perto de um CEP 📍

1. Vá à aba **Explorar**.
2. Escolha **CEP**.
3. Digite **05586-001**.
4. Deixe “Tipos de equipamento” vazio para pesquisar todos.
5. Use raio **5000** e k **10**.
6. Clique em **Encontrar equipamentos**.

Você verá a origem aproximada na região da Rua Iquiririm, pontos próximos no mapa e uma tabela de resultados.

**Atenção:** o CEP não é o ponto exato de uma casa. O sistema informa as coordenadas e quem forneceu a localização. Para mais precisão, use uma coordenada conhecida e verificada.

## 3. Prefere latitude e longitude?

Troque a opção de origem para **Latitude e longitude**.

~~~text
Latitude:  -23.571872
Longitude: -46.730196
~~~

Latitude vem primeiro. Em São Paulo, as duas são negativas. Use ponto para os decimais. Em um arquivo, não misture CEP e coordenadas preenchidos na mesma linha.

## 4. Escolha os ingredientes da cesta 🥬

Em **Tipos de equipamento**, você pode combinar:

- Feiras livres e feiras orgânicas.
- Hortifrutis e sacolões.
- Abastecimento, CEASA e CEAGESP, quando registrados na fonte.
- Alimentos e comércio de orgânicos.
- Hortas, agricultores e produção rural.
- Comércio de alimentos, iniciativas e serviços de apoio.
- Vivência rural e aldeias, além de outros registros da fonte.

Sem seleção, entram todos os tipos. Um perfil pode pertencer a mais de um grupo.

Esses grupos são construídos a partir de nomes, categorias, subcategorias e qualificações do cadastro. Por isso, podem precisar de revisão para a sua dissertação. Um box na CEAGESP não é a mesma coisa que a central inteira; “orgânico” não significa que verificamos uma certificação.

## 5. Raio e k: duas peneiras, uma cesta

Imagine:

~~~text
Entram na cesta:
   dentro do raio
         OU
   entre os k primeiros
~~~

Com raio de 1.000 m e k = 10, se houver só três registros no raio, a lista pode trazer outros sete mais distantes.

A coluna **No raio?** permite separar os dois casos. O aplicativo não transforma “fora do raio” em “dentro” só para completar a lista.

Os cartões acima do mapa e a tabela correspondem à distância escolhida em **Distância exibida**. A mensagem geral conta a união das métricas; esse total pode ser maior que o cartão.

## 6. Por que há tantas réguas? 📏

| Régua | Imagine assim |
|---|---|
| Karney | Distância pela superfície curva da Terra, usando um elipsoide |
| Haversine | Uma versão que representa a Terra como esfera |
| Euclidiana | Uma linha reta no mapa projetado |
| Manhattan | Somar deslocamentos em dois eixos do mapa |
| Chebyshev | Usar o maior deslocamento entre esses eixos |
| Rede | Percorrer as vias cadastradas para um modo de transporte |

Manhattan e Chebyshev **não desenham ruas**. Para caminhos de rua, selecione a pé, bicicleta ou carro. Cada modo oferece:

- Menor distância.
- Menor tempo estimado.

O tempo é modelado, sem trânsito ao vivo. Ida e volta podem diferir por causa de sentidos das vias. O mapa mostra os equipamentos e a origem, não o traçado das rotas.

### Pedi caminhos e parece que está demorando… 🍲

Pense numa refeição servida em etapas: você não precisa esperar todos os pratos
para começar!

1. Clique em **Encontrar equipamentos** (ou **Analisar lote**).
2. Primeiro chegam as cinco “réguas” geométricas: já dá para ver mapa, tabela e estatísticas.
3. Enquanto você explora, outro processo R calcula os caminhos. Os resultados de rua são acrescentados por modo e por origem.

A mensagem mostra o que está sendo feito e há quanto tempo. “1/4 unidades” pode
significar que a geometria ficou pronta e faltam caminhada, bicicleta e carro.
**Isso não quer dizer que falta só três vezes o mesmo tempo!** Caminhos de rua
são muito mais trabalhosos e podem levar vários minutos.

Você pode trocar a régua exibida e visitar **Estatísticas** sem esperar acabar.
Enquanto faltar alguma parte, a tela avisa **Resultados parciais**. Se outra
pessoa estiver consultando a mesma aplicação, aparece uma fila: cada consulta
tem sua vez, para não sobrecarregar o computador.

Quer parar? Use **Cancelar consulta** ou **Cancelar lote**. O cálculo para de
verdade e o que já ficou pronto continua disponível. Downloads são liberados
quando a execução termina, é cancelada ou falha; arquivos incompletos levam
um aviso. **Uma análise cancelada não prova que não existem equipamentos próximos.**

Mudar o CEP, filtros ou modos durante a execução não muda o pedido já enviado.
Espere terminar ou cancele e faça uma nova consulta. Fechar ou recarregar a página
também cancela o trabalho daquela sessão: ele não continua “escondido”.

Se uma etapa ultrapassar 15 minutos sem avançar, aparece um erro em vez de
uma espera sem fim. O README explica como aumentar esse limite em computadores
mais lentos e onde consultar os registros técnicos. As pastas `jobs/web-job-.../`
guardam esses registros e partes prontas no computador que roda R; podem conter
seus CEPs/coordenadas e não devem ser publicadas.

Após atualizar o código, feche e abra novamente a aplicação e recarregue a página
para usar essa melhoria. Sua despensa `data/` continua a mesma: não é preciso
baixar tudo de novo.

## 7. E acessibilidade? ♿

O filtro separa:

- **Informada: sim**.
- **Informada: não**.
- **Não informada**.

“Não informada” não quer dizer “não acessível”. E “sim” não garante calçadas, rampas ou uma rota adequada à necessidade de cada pessoa. É uma declaração da fonte, não uma vistoria.

## 8. Onde estão os gráficos?

Abra **Estatísticas**, depois de consultar.

Você encontra a cobertura da base por tipo, o histograma de distâncias, o resumo por origem/métrica e a comparação entre réguas.

A mediana é o valor do meio: metade das distâncias selecionadas fica abaixo dela, metade acima. O percentil 90 é o valor abaixo do qual ficam 90% das distâncias selecionadas.

A palavra importante é **selecionadas**: o resumo usa a cesta da consulta, não toda a cidade ou toda a população.

## 9. Vários lugares de uma vez 🧺

Abra **Lotes**, baixe o exemplo e envie seu arquivo.

~~~csv
query_id,cep,latitude,longitude,k,radius_m
casa-estudo,05586001,,,10,2000
praca-estudo,,-23.55008,-46.63408,5,1000
~~~

- query_id: um nome único para cada origem.
- cep: oito dígitos, incluindo o zero inicial. Trate como texto no Excel.
- latitude/longitude: as coordenadas, quando não usar CEP.
- k e radius_m: opcionais; se vazios, usam os valores da tela.

Clique em **Analisar lote**. As linhas com problema aparecem na tabela de erros; as válidas continuam.

Durante a execução, visite **Explorar** e **Estatísticas** para acompanhar os resultados combinados. Você também pode usar **Cancelar lote**. Quando a execução termina, o ZIP contém CSV, partições Parquet, estatísticas, manifesto e erros. O manifesto diz se o cálculo ficou completo ou parcial. A interface aceita até 100 origens por execução; para volumes maiores e retomada, use o comando de lotes descrito no README.

Não publique lotes com endereços pessoais identificáveis.

## 10. A despensa offline 💾

A internet serve para encher a despensa. Depois, a consulta usa o que está guardado.

~~~mermaid
flowchart LR
    A[Com internet: preparar] --> B[CSV e JSON oficiais]
    A --> C[CEPs preparados]
    A --> D[Mapa e vias locais]
    B --> E[Sem internet: consultar]
    C --> E
    D --> E
    E --> F[Mapa, tabelas e relatórios]
~~~

Na aba **Banco offline**, confira os arquivos, formatos, contagens e os CEPs disponíveis.

Essa despensa é uma pasta de verdade no computador que executa a aplicação!
Nesta instalação, ela fica em:

~~~text
/home/paulo/Documentos/meus_codigos/sampamaisrual/data/
~~~

Se você está acessando por SSH, a despensa continua no notebook; o computador do
navegador não precisa guardar outra cópia. Dentro da pasta do projeto, os arquivos
principais ficam em:

~~~text
data/raw/          alimentos na embalagem original: CSV e JSON
data/processed/    ingredientes organizados: banco e grafos
data/cache/cep/    índice de CEPs já preparados
data/osm/          limite municipal e vias do mapa
~~~

Copiar só o código para outro computador não copia essa despensa. Para transferir uma instalação offline, leve também os dados preparados e as dependências R, respeitando privacidade e licenças.

### Um CEP novo não funciona offline?

Isso é esperado se ele ainda não foi preparado. Com internet, rode:

~~~bash
Rscript scripts/prepare_ceps.R 01311000
~~~

Ou prepare os CEPs de um arquivo:

~~~bash
Rscript scripts/prepare_ceps.R meus-ceps.csv
~~~

Depois abra a aplicação novamente. O projeto não inclui todos os CEPs do Brasil; não inventa coordenadas para preencher essa falta.

### Como baixar os dados em uma máquina nova?

~~~bash
Rscript scripts/prepare_offline.R
~~~

Essa etapa pode demorar, principalmente para construir as redes. Ela preserva uma
base já existente; para buscar novidades no cadastro, siga o passo a passo abaixo.

### Chegaram dados novos: como reabastecer a despensa? 🥬

Sim, a aplicação consegue usar novos registros publicados no Sampa+Rural!
Mas ela **não vai às compras sozinha**: a atualização é manual, não automática.

1. Pare a aplicação. Se ela estiver rodando no terminal, pressione **Ctrl+C no
   terminal do R**. Se estiver usando SSH, pode deixar o terminal do túnel aberto.
2. Com internet no notebook, rode os comandos abaixo. Ajuste o caminho se a pasta
   do projeto for diferente.

~~~bash
cd /home/paulo/Documentos/meus_codigos/sampamaisrual
R_PROFILE_USER=/dev/null Rscript scripts/update_data.R
~~~

3. Espere a atualização terminar sem erros.
4. Abra a aplicação novamente pelo **Run App** ou pelo mesmo comando usado antes.
   No acesso por SSH, mantenha a mesma porta, como `3939` no exemplo da seção 1.1.

Durante a atualização, o programa busca o catálogo oficial, baixa os CSV e JSON,
confere os registros e reorganiza a base usada nas consultas.

Cada download fica numa pasta datada em `data/raw/`: é um **snapshot**, uma
fotografia do cadastro naquele momento. As fotografias antigas ficam guardadas;
a base de uso atual em `data/processed/` é regenerada com os dados da nova coleta.
Ela é salva em RDS, CSV, JSON e Parquet.

**Apertar F5 no navegador não troca os ingredientes da aplicação.** É preciso
reiniciar o programa R, porque ele carrega a base ao abrir. Depois, confira a
identificação do snapshot na tela e visite a aba **Banco offline**.

Uma nova feira ou horta poderá aparecer nos mapas e nas estatísticas se tiver
coordenadas válidas na área de estudo e passar pelos filtros escolhidos. Não ter
coordenadas continua sendo uma limitação: o programa não inventa a localização.

Depois de reabastecer e reabrir a aplicação, você pode voltar a consultar sem internet.

**Duas pegadinhas para evitar:**

- Atualizar os equipamentos não atualiza automaticamente as vias nem prepara
  novos CEPs. São prateleiras diferentes, com etapas próprias de preparação.
- Editar um CSV à mão não muda a tela automaticamente. O arquivo que a aplicação
  lê primeiro é `data/processed/equipment.rds`, gerado pelo processamento; as
  cópias CSV e JSON não funcionam como uma planilha de edição sincronizada.

## 11. Leve o resultado com você 📄

Na aba Explorar:

- **Resultados CSV**: todas as métricas calculadas, não apenas a que aparece na tela.
- **Relatório HTML**: mapa, tabelas, gráficos e limitações, em um arquivo que pode ser aberto offline.

O relatório PDF também pode ser gerado pelo R; o exemplo está no README. É necessário ter LaTeX instalado.

Os relatórios são um ponto de partida para sua pesquisa, não um texto pronto com conclusões causais.

## 12. Quando algo parecer estranho

| Situação | O que verificar |
|---|---|
| CEP ausente | Prepare o CEP com internet ou use coordenadas verificadas |
| Nenhum resultado | Remova filtros; confira coordenadas e presença da base |
| Muitos pontos de uma categoria | O cadastro e os grupos podem se sobrepor; não são um censo |
| Rede não aparece | Prepare os grafos e reinicie a aplicação |
| Caminho indisponível | Pode haver desconexão, recorte da rede ou ponto longe das vias |
| Caminhos demorando | Veja a etapa e explore os resultados parciais; use Cancelar se quiser parar |
| Na fila local | Outra consulta está usando o processo de cálculo; aguarde ou cancele a espera |
| Etapa excedeu o tempo | As partes prontas permanecem; tente menos modos ou ajuste o limite conforme o README |
| Mapa sem fotos de ruas | É intencional: o fundo usa vetores locais, sem tiles externos |
| RStudio abre comportamento antigo | Execute app.R da pasta atual; reinicie R e carregue o projeto |
| Lote perde o zero do CEP | Salve a coluna como texto; um CEP de sete dígitos é rejeitado |

## 13. O chapéu de pesquisador 🎓

Antes de analisar a dissertação, decida quais grupos, raios, modos e origens representam sua pergunta. Guarde as decisões no protocolo.

Registre a data do cadastro, a fonte do CEP, a versão da rede e as exclusões. Coordenadas ausentes podem se concentrar justamente nos agricultores menos cadastrados: isso cria viés.

A base contém perfis; repetições exatas são removidas, mas dois perfis diferentes podem representar uma única instalação. Valide uma amostra manualmente.

O retângulo de triagem inclui pontos vizinhos ao município. Use within_municipality para comparar com o limite IBGE, lembrando que é uma malha simplificada.

Uma horta perto de alguém **não prova** alimentação adequada ou acesso efetivo. Preço, horário, transporte, condições físicas e qualidade dos alimentos não são medidos por estas distâncias.

Boa pesquisa começa com uma pergunta clara — e uma cesta de dados cuja origem você conhece. 🌱
