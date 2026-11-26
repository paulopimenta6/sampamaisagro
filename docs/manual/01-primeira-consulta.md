# 1. Encontrar um equipamento perto de um CEP

**Sua tarefa:** encontrar uma feira cadastrada, descobrir a que distância ela fica e dizer se está dentro de 2 km. Para começar, use uma instalação com a base já preparada. Se só tem os arquivos do repositório, faça primeiro a [preparação da máquina](08-instalacao.md).

1. Se recebeu um endereço da aplicação em funcionamento, abra-o no navegador. Se trabalha no computador que guarda o projeto, abra `sampamaisrural.Rproj` no RStudio, abra o arquivo `app.R` da raiz e use **Run App**. Quando a janela abrir, mantenha a sessão do R em execução.
2. Em **Explorar**, leia o aviso **Base oficial local** e anote o identificador do snapshot. O mapa inicial já mostra a base mapeável. A tabela de equipamentos encontrados receberá as linhas específicas da sua busca depois da consulta.
3. Abra **Banco offline**. Na tabela **CEPs preparados para consulta sem internet**, procure `05586001`. Use esse CEP se ele estiver disponível, ou escolha outro da lista com localização válida. Anote o escolhido.
4. Volte a **Explorar**. Em **Como localizar a origem?**, marque **CEP** e digite os oito dígitos. Em **Tipos de equipamento**, escolha **Feiras livres**. Em **Acessibilidade declarada**, mantenha **Todos**. Defina **Raio de busca (metros)** como `2000` e **Mínimo de vizinhos por métrica (k)** como `5`. Deixe as caixas de trajetos em rede desmarcadas.
5. Acione **Encontrar equipamentos**. Leia a mensagem de andamento até a conclusão. Em **Distância exibida**, escolha a geodésica elipsoidal (Karney). Ela mede a separação sobre a superfície de referência da Terra.
6. Na tabela **Equipamentos encontrados**, localize a linha com **Posição** igual a 1. Leia **Equipamento**, **Distância (m)** e **No raio?**. O mesmo percurso pode ser feito inteiramente pela tabela. Divida os metros por 1.000 para expressar a distância em quilômetros.

**Conferência.** Preencha: “No snapshot ___, para o CEP ___, o perfil ___ ocupa a posição ___ por Karney, fica a ___ m da origem e a coluna ‘No raio?’ indica ___.” Compare o valor em metros com 2.000, lembrando que a tela pode arredondá-lo. Para valores no limite, use o indicador calculado pelo sistema.

**Se a tabela ficar vazia.** Leia primeiro a mensagem da consulta. Confirme o CEP em **Banco offline**. Se o grupo tiver zero registros mapeáveis nesse snapshot, limpe **Tipos de equipamento** e consulte novamente. Guarde essa segunda busca como outra consulta. Se nenhum CEP local funcionar, use o exemplo por coordenadas do [capítulo 3](03-origens-filtros.md).

**Exercício.** A primeira linha mostra 2.400 m e “Não” para um raio de 2.000 m. Isso pode acontecer? **Gabarito:** sim. Um dos cinco primeiros pode ficar além de 2 km. Relate 2,4 km e a condição fora do raio. A regra completa está no [capítulo 4](04-raio-ranking.md).

[Índice do manual](README.md) · [Próximo capítulo](02-cadastro.md)
