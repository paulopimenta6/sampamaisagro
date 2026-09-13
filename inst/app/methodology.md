## Pergunta operacional

A aplicacao localiza equipamentos cadastrados pelo Sampa+Rural proximos a uma ou mais origens. Uma origem pode ser uma coordenada fornecida pelo pesquisador ou um CEP geocodificado de modo aproximado.

## Definicoes de distancia

Sao calculadas cinco distancias geometricas: geodesica elipsoidal (Karney), Haversine, Euclidiana, Manhattan e Chebyshev. As tres ultimas usam SIRGAS 2000 / UTM 23S (EPSG:31983). Quando os grafos OpenStreetMap estao instalados, a aplicacao acrescenta caminhada, bicicleta e automovel, cada qual para o caminho de menor distancia e para o caminho de menor tempo. Redes direcionais podem produzir resultados diferentes no trajeto de ida e de volta.

## Validade

Nenhuma metrica e assumida como padrao-ouro. A escolha deve acompanhar a pergunta de pesquisa. Coordenadas ausentes ou fora da area de estudo ficam em quarentena. Snapping acima de 250 m recebe alerta e acima de 1.000 m e excluido. Pares sem caminho permanecem identificados como inalcançaveis.

## Etica e privacidade

O aplicativo nao exibe telefones, e-mails nem redes sociais da fonte. Arquivos de lote e coordenadas de origem devem ser tratados como dados potencialmente sensiveis, com acesso restrito e retencao limitada. Resultados publicos devem ser agregados espacialmente.

## Interpretacao academica

Mapas e modelos sao descritivos e associacionais. Eles nao permitem concluir que proximidade causa um desfecho. Resultados dependem da cobertura do cadastro, do geocodificador, do snapshot do OpenStreetMap, dos perfis modais e da unidade espacial escolhida.
