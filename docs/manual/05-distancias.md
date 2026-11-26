# 5. Escolher o que “perto” quer dizer

**Sua tarefa:** escolher uma medida antes de conhecer seu resultado. Pergunte primeiro se precisa de separação geométrica, comprimento de um trajeto permitido ou tempo estimado de deslocamento. A aplicação calcula cinco métricas geométricas. As redes dependem dos grafos locais, isto é, dos arquivos que ligam os trechos de vias permitidos para cada modo.

| Medida | Como imaginar a medida | Quando usá-la |
|---|---|---|
| Geodésica elipsoidal (Karney) | Menor separação sobre um modelo da Terra achatado nos polos | Referência para separação geográfica direta |
| Haversine | Arco calculado supondo uma Terra esférica | Verificar a sensibilidade à simplificação da superfície |
| Euclidiana projetada | Diagonal reta numa projeção local em metros | Medir separação no plano do mapa |
| Manhattan projetada | Soma dos deslocamentos em dois eixos perpendiculares | Explorar deslocamento restrito aos eixos |
| Chebyshev projetada | Maior dos dois deslocamentos por eixo | Explorar um cenário geométrico alternativo |

Nas três últimas, o projeto usa por padrão SIRGAS 2000 / UTM 23S, código EPSG:31983. Exemplo de leitura sem mapa: deslocamentos de 300 m e 400 m nos dois eixos dão **500 m** pela Euclidiana, **700 m** pela Manhattan e **400 m** pela Chebyshev. Nenhuma dessas contas verificou se há uma rua transitável entre os pontos.

## Fazer uma comparação de rede

1. Em **Banco offline**, veja quais modos estão instalados. Em **Explorar**, use a origem do [capítulo 3](03-origens-filtros.md). Mantenha os filtros e selecione apenas **A pé** em **Adicionar trajetos em rede**, se disponível. Escolha **Ida e volta** e inicie. Bicicleta e carro usam redes e regras próprias.
2. Leia a etapa atual. A geometria pode aparecer enquanto a rede ainda está sendo calculada. Compare resultados depois de verificar a situação da execução. Se o modo desejado faltar, siga a [preparação de redes](08-instalacao.md).
3. Na tabela, confira **Sentido**, **Posição**, **Distância (m)** e **Tempo (min)** quando disponível. Ida sai da origem em direção ao equipamento. Volta parte do equipamento. Mão de direção e regras de acesso podem alterar o caminho.
4. No objetivo `shortest`, o ranking segue o comprimento. Em `fastest`, segue o **tempo modelado**. `distance_m` continua sendo o comprimento daquele trajeto escolhido, inclusive os conectores estimados. Mesmo na rota rápida, a condição “no raio” continua em metros.
5. Em **Estatísticas**, leia **Diagnóstico das rotas antes da seleção**. Para cada ponta, o projeto estima uma ligação ao vértice da rede (*snapping*). Por padrão, acima de 250 m há alerta e acima de 1.000 m o par pode ser excluído. Confira os valores em sua configuração. Um caminho indisponível representa uma limitação da rede ou do encaixe e deve ser registrado separadamente.

**Exercício.** Dois destinos têm trajetos mais rápidos de 12 e 9 minutos, medindo respectivamente 1.000 e 1.300 metros. Qual vem primeiro em `fastest`? Qual está num raio de 1.100 m? **Gabarito:** o destino a 9 minutos vem primeiro. Só o de 1.000 m está no raio. Na interpretação, indique o modo, o sentido e o objetivo. O tempo vem do modelo de velocidades, sem observação do trânsito ou vistoria das calçadas. [Definições operacionais das distâncias](../../distancias.md)

[Índice do manual](README.md) · [Capítulo anterior](04-raio-ranking.md) · [Próximo capítulo](06-estatisticas.md)
