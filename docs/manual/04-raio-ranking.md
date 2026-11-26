# 4. Por que aparece um equipamento fora do raio?

**Sua tarefa:** reconstruir uma seleção no papel e depois reconhecê-la em **Explorar**. Você precisa de uma origem, uma métrica, um sentido, um raio em metros e um valor de `k`. O ranking ordena os equipamentos alcançáveis segundo aquela métrica. `k` é quantos dos primeiros entram mesmo que estejam além do raio, se houver equipamentos suficientes.

## Uma consulta com três perfis fictícios

Imagine a mesma origem e três distâncias crescentes. Escolha raio de **500 m** e **k = 2**. Leia cada linha da esquerda para a direita.

| Perfil | Distância | Posição | Está no raio? | Está entre os dois primeiros? | Entra no resultado? |
|---|---:|---:|---|---|---|
| Feira A | 300 m | 1 | Sim | Sim | Sim, uma vez |
| Horta B | 900 m | 2 | Não | Sim | Sim |
| Mercado C | 1.400 m | 3 | Não | Não | Fica fora |

1. Marque as linhas com distância até 500 m, inclusive. Você marcou a Feira A.
2. Marque as linhas nas posições 1 e 2. Você marcou a Feira A e a Horta B.
3. Junte as marcas. A saída tem **dois pares retidos** (origem com A e origem com B), **dois equipamentos distintos** e **um no raio**. A mesma marcação pelos dois critérios gera uma única linha.
4. Na tela, use **Distância exibida** para escolher uma métrica. Confira **Posição**, **Distância (m)** e **No raio?** em **Equipamentos encontrados**. Os filtros das colunas ajudam a localizar uma linha. O círculo no mapa, quando exibido, é uma referência geodésica. Para saber quem entrou no raio de uma métrica de rede, leia a coluna calculada para essa métrica.

**Como contar.** Cada linha representa um par em uma combinação de origem, métrica e sentido. Um perfil pode reaparecer em cinco métricas geométricas. Para contar equipamentos, escolha a combinação de interesse e conte identificadores distintos. Para contar o raio, use `within_radius`. Se recebeu uma planilha já cortada nas primeiras posições, registre esse recorte antes de apresentá-la como contagem no raio.

**Exercício.** Com as mesmas distâncias, use raio de 1.500 m e k = 1. Quantas linhas entram? **Gabarito:** entram as três porque estão no raio. A menor distância é 300 m nos dois exercícios. Portanto, k tampouco é um teto para o número de linhas. Se o seu total parecer muito grande, confira quantas métricas, origens e direções a planilha contém.

[Índice do manual](README.md) · [Capítulo anterior](03-origens-filtros.md) · [Próximo capítulo](05-distancias.md)
