# Distâncias no Sampa+Agro

## 1. Por que existem várias distâncias?

No Sampa+Agro, “distância” não deve ser tratada como uma quantidade única e universal.

A distância entre uma origem e um equipamento pode representar perguntas diferentes:

- qual é a separação geométrica entre os pontos?
- qual seria a distância aproximada em superfície terrestre?
- qual é o comprimento de um trajeto possível pela rede?
- qual trajeto minimiza distância?
- qual trajeto minimiza tempo?
- a conclusão sobre proximidade muda dependendo da métrica?

Por isso, não existe uma única distância que possa ser declarada automaticamente como a “verdadeira”.

As diferentes métricas são definições operacionais distintas.

O objetivo científico é verificar quanto as conclusões de acessibilidade e proximidade dependem dessas definições.

---

# 2. Famílias de distância

O projeto possui duas grandes famílias:

## 2.1 Distâncias geométricas

São calculadas diretamente a partir das posições da origem e do equipamento.

Não utilizam ruas ou caminhos.

No Sampa+Agro:

- Geodésica elipsoidal — Karney;
- Haversine esférica;
- Euclidiana projetada;
- Manhattan projetada;
- Chebyshev projetada.

Todas são simétricas:

distância(A,B) = distância(B,A)

---

## 2.2 Distâncias pela rede

Utilizam uma rede viária representando caminhos possíveis.

O projeto distingue:

- caminhada (`foot`);
- bicicleta (`bicycle`);
- automóvel (`motorcar`).

Cada modo pode ser calculado segundo dois objetivos:

- menor distância (`shortest`);
- menor tempo (`fastest`).

Também existe direção:

- origem → equipamento;
- equipamento → origem.

Diferentemente das métricas geométricas, uma rede dirigida pode produzir resultados diferentes nos dois sentidos.

---

# 3. Geodésica elipsoidal — Karney

Identificador:

`geodesic_karney`

É a distância geodésica entre dois pontos considerando a Terra como um elipsoide.

No projeto é calculada com `geosphere::distGeo()`.

## Interpretação

Representa aproximadamente o menor caminho sobre a superfície elipsoidal entre origem e destino.

## Unidade

Metros.

## Vantagens

- considera a geometria elipsoidal da Terra;
- evita a simplificação de uma Terra perfeitamente esférica;
- não depende de uma projeção cartográfica plana;
- é adequada como medida geométrica direta.

## Limitações

Não representa deslocamento real.

Pode atravessar:

- edifícios;
- rios;
- áreas fechadas;
- quarteirões;
- terrenos sem acesso;
- qualquer obstáculo existente entre os pontos.

Portanto:

**proximidade geodésica não é sinônimo de acessibilidade.**

## Papel científico

É uma excelente medida de separação geométrica e uma referência útil para comparar outras definições de distância.

Não deve, porém, ser declarada “padrão-ouro” de acessibilidade.

---

# 4. Haversine esférica

Identificador:

`geodesic_haversine`

É uma distância de grande círculo calculada assumindo uma Terra esférica.

No projeto é calculada com `geosphere::distHaversine()`.

## Unidade

Metros.

## Vantagens

- simples;
- amplamente conhecida;
- não exige transformação para uma projeção plana;
- útil para avaliar se a aproximação esférica altera materialmente os resultados.

## Limitações

A Terra não é uma esfera perfeita.

Consequentemente, pode diferir da distância elipsoidal.

Nas dimensões municipais de São Paulo, essa diferença pode ser pequena, mas isso deve ser verificado empiricamente, e não presumido.

## Papel científico

É especialmente útil como **análise de sensibilidade geométrica**:

Karney versus Haversine.

Se rankings e resultados permanecerem semelhantes, isso mostra robustez frente à aproximação da forma terrestre.

---

# 5. Euclidiana projetada

Identificador:

`euclidean_projected`

Primeiro as coordenadas são transformadas para o sistema projetado métrico adotado pelo projeto.

Atualmente o cálculo utiliza o CRS projetado definido na configuração, tipicamente EPSG:31983.

Depois:

d = √(Δx² + Δy²)

## Unidade

Metros.

## Interpretação

É a distância em linha reta no plano projetado.

## Vantagens

- cálculo simples;
- diretamente métrica;
- adequada para operações espaciais locais;
- permite comparar a solução plana com as geodésicas.

## Limitações

Toda projeção cartográfica produz alguma deformação.

Sua adequação depende:

- da área estudada;
- da projeção escolhida;
- da extensão espacial;
- da finalidade da análise.

O livro enfatiza a importância de conhecer e verificar o sistema de referência espacial, pois projeção, datum e elipsoide fazem parte da representação dos dados geográficos.

## Papel científico

Muito útil na comparação:

Karney × Haversine × Euclidiana projetada.

---

# 6. Manhattan projetada

Identificador:

`manhattan_projected`

É calculada como:

d = |Δx| + |Δy|

Também é conhecida como distância L1.

## Interpretação

É a soma dos deslocamentos nos dois eixos do sistema projetado.

Recebe o nome “Manhattan” por lembrar deslocamentos em uma malha perfeitamente ortogonal.

## Unidade

Metros.

## Vantagens

É útil para investigar como uma geometria em grade pode alterar:

- rankings;
- proximidade;
- seleção top-k.

## Limitações

Não é uma rota real.

São Paulo não possui uma malha perfeitamente ortogonal e a métrica:

- não conhece ruas;
- não conhece sentido de circulação;
- não conhece obstáculos;
- não conhece topografia;
- não conhece conexões reais.

## Papel científico

Deve ser considerada principalmente uma **métrica geométrica de sensibilidade**, e não uma medida substantiva de acessibilidade urbana.

---

# 7. Chebyshev projetada

Identificador:

`chebyshev_projected`

É calculada como:

d = max(|Δx|, |Δy|)

Também conhecida como distância L∞.

## Interpretação

A distância é determinada pelo maior deslocamento entre os eixos horizontal e vertical.

## Unidade

Metros.

## Vantagens

Permite verificar como uma definição geométrica bastante diferente modifica:

- rankings;
- top-k;
- seleção de equipamentos.

## Limitações

Não representa deslocamento urbano real.

Sua interpretação física no contexto da mobilidade em São Paulo é limitada.

## Papel científico

Deve ser usada como **análise de sensibilidade geométrica**, e não como principal indicador de acessibilidade.

---

# 8. Distância pela rede — caminhada

Modo:

`foot`

A origem e o equipamento são associados à rede de caminhos e o trajeto é calculado por essa rede.

Podem existir:

### Menor distância

`network_foot_shortest`

Procura o caminho com menor comprimento.

### Menor tempo

`network_foot_fastest`

Procura o caminho com menor tempo modelado.

## Interpretação

É uma aproximação mais próxima da experiência de acesso pedonal do que uma linha reta.

## Limitações

Depende da qualidade da rede usada.

Pode não representar adequadamente:

- calçadas;
- travessias;
- acessibilidade universal;
- barreiras temporárias;
- segurança;
- declividade real;
- condições locais.

Portanto:

**distância de rede para caminhada ainda é um modelo, não uma observação direta do trajeto de uma pessoa.**

---

# 9. Distância pela rede — bicicleta

Modo:

`bicycle`

Possui igualmente:

- `network_bicycle_shortest`;
- `network_bicycle_fastest`.

## Interpretação

Representa um trajeto modelado pela rede compatível com deslocamento ciclístico.

## Vantagens

Permite avaliar acessibilidade para além da caminhada e do automóvel.

## Limitações

O resultado depende das regras e atributos disponíveis na rede.

Não significa necessariamente:

- rota mais segura;
- rota ciclável ideal;
- existência contínua de ciclovia;
- conforto;
- preferência real do ciclista.

---

# 10. Distância pela rede — automóvel

Modo:

`motorcar`

Possui:

- `network_motorcar_shortest`;
- `network_motorcar_fastest`.

## Menor distância

Minimiza comprimento da rota.

## Menor tempo

Minimiza tempo modelado.

Esses dois trajetos podem ser diferentes.

Uma rota mais longa pode ser mais rápida.

## Limitações importantes

O tempo é modelado.

Não representa necessariamente:

- trânsito observado;
- congestionamentos;
- acidentes;
- obras;
- condições específicas do horário da viagem.

---

# 11. Menor distância versus menor tempo

Essa distinção é fundamental.

Para `shortest`:

o ranking é determinado pela distância.

Para `fastest`:

o ranking é determinado pelo tempo modelado.

Assim, no modo `fastest`, o equipamento com menor `distance_m` não precisa ser o primeiro colocado.

O `distance_m` desse resultado representa o comprimento da rota escolhida por ser mais rápida.

Portanto:

**“mais próximo” geometricamente não é necessariamente “mais rápido de alcançar”.**

---

# 12. Sentido da viagem

As métricas geométricas são simétricas.

Já a rede pode ser calculada em:

`origin_to_equipment`

ou

`equipment_to_origin`

Em uma rede com restrições direcionais:

distância(A → B)

pode diferir de:

distância(B → A)

Isso é especialmente relevante para redes viárias.

Por isso, o Sampa+Agro não deve misturar sentidos diferentes nas mesmas estatísticas sem identificá-los.

---

# 13. Snapping à rede

Para calcular uma rota, origem e equipamento precisam ser associados a pontos da rede.

O projeto registra:

- distância do encaixe da origem;
- distância do encaixe do equipamento;
- avisos quando o encaixe é distante;
- exclusão quando excede o limite permitido.

Isso é importante porque uma rota aparentemente precisa pode começar com um ponto mal associado à rede.

A distância de *snapping* deve ser tratada como componente de qualidade do resultado de rede.

---

# 14. Distância ao mais próximo

Uma medida especialmente útil é:

**distância da origem ao equipamento mais próximo de determinada categoria.**

Ela pode ser calculada separadamente para cada métrica.

Por exemplo:

- feira mais próxima por Karney;
- feira mais próxima a pé;
- feira de menor tempo por automóvel.

Esses resultados podem apontar para equipamentos diferentes.

Essa discordância é, por si só, cientificamente informativa.

---

# 15. Contagem dentro de um raio

Outra medida de acessibilidade é:

**quantos equipamentos existem dentro de determinada distância da origem?**

O livro apresenta uma lógica espacial semelhante ao utilizar *buffers* para calcular a proporção de território contida a até 30 km de estradas principais.

No Sampa+Agro, a mesma ideia conceitual pode ser usada para perguntas como:

- quantas feiras existem até 1 km?
- quantas até 2 km?
- quantas até 5 km?

Isso complementa a distância ao equipamento mais próximo.

---

# 16. Distância não é acessibilidade completa

Mesmo as métricas de rede não capturam toda a acessibilidade.

Acessibilidade também pode depender de:

- horário de funcionamento;
- custo;
- capacidade do estabelecimento;
- barreiras físicas;
- características socioeconômicas;
- disponibilidade dos produtos;
- qualidade do serviço;
- transporte público;
- segurança;
- preferências individuais.

Portanto, no Sampa+Agro:

**distância é uma dimensão operacional da acessibilidade espacial, não uma medida completa de acesso.**

---

# 17. Hierarquia recomendada para análise

## Núcleo descritivo

- Karney;
- distância ao mais próximo;
- contagem dentro de raios;
- métricas de rede relevantes.

## Sensibilidade geométrica

- Haversine;
- Euclidiana projetada;
- Manhattan;
- Chebyshev.

## Acessibilidade de rede

- caminhada;
- bicicleta;
- automóvel;
- shortest;
- fastest;
- direção quando relevante.

---

# 18. Comparação entre métricas

Na Unidade 3, diferentes distâncias poderão ser comparadas por:

- Spearman;
- Kendall;
- Jaccard top-k;
- diferenças pareadas;
- Bland–Altman quando metodologicamente apropriado.

Uma comparação especialmente interpretável será:

`distância de rede − distância geométrica`

para o mesmo par origem–equipamento.

Mediana e IQR dessas diferenças ajudam a mostrar quanto a necessidade de seguir a rede aumenta a distância em relação à separação direta.

Essa análise deve ser pareada: exatamente o mesmo par origem–equipamento precisa existir nas duas métricas.

---

# 19. Princípio científico final

Nenhuma métrica deve ser escolhida apenas porque produz o menor número ou porque parece mais sofisticada.

Cada uma responde a uma pergunta diferente.

O objetivo científico do Sampa+Agro é justamente avaliar:

**quanto nossa conclusão sobre proximidade e acessibilidade espacial muda quando mudamos a definição operacional de distância.**

Essa comparação é uma característica científica do projeto, não um problema a ser eliminado.