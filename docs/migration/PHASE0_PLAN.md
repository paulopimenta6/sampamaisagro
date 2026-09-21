# Fase 0 — Proteção da v0.2

Implementação autorizada em 17/09/2026. Base:
`c751eccbfbfa38a522e50c828be4278cdcda43d9`, branch
`refactor/scientific-platform-v0.3`. Árvore inicialmente limpa.

## Objetivo e fronteira

Criar uma rede de regressões reproduzíveis antes da transformação científica.
A única correção funcional é o denominador de qualidade do relatório e o
congelamento dos filtros associados à consulta. A Fase 1 não está autorizada.

Preservar motores de coleta, normalização, validação, distâncias, redes, mapas,
batch, fila e jobs progressivos; snapshots, grafos e validação real permanecem
intactos. Não implementar registry, update checking, schema drift, modelo v0.3,
entity_id, diff, estatística nova, isócronas, rotas, cache ou targets.

## Ordem operacional

1. Registrar Git, ambiente e inventário dos ativos existentes.
2. Criar `AGENTS.md` e a documentação operacional.
3. Inspecionar `.atomic-*` somente por leitura, com memória limitada.
4. Criar fixtures públicas sintéticas e configuração isolada.
5. Capturar expectativas candidatas antes de corrigir o relatório; conferir
   custos manuais e contagens; aprovar explicitamente as projeções estáveis.
6. Acrescentar regressões sem substituir os testes existentes.
7. Demonstrar o defeito do denominador no fluxo do download.
8. Corrigir somente inventário/contexto transmitidos ao relatório e testar HTML.
9. Implantar CORE com testthat, pacote construído, R CMD check e controle de rede.
10. Executar smoke do benchmark controlado, sem otimizar o motor.
11. Implantar BROWSER manual com pacote instalado e fixtures.
12. Consolidar evidências, limitações e diff; parar antes da Fase 1.

## Fixtures e contratos

O diretório [v02](../../tests/fixtures/v02/README.md) contém cadastro de oito
ocorrências, sete perfis distintos e três elegíveis; relatório temático com
ausência estrutural e listas; vazio válido; alteração de conteúdo; origens e CEP
preparado; oito vértices e dez arestas. A fixture de qualidade tem 4/2/50%.

A rede protege A→D shortest 200 m, fastest 300 m/20 s; D→A 350 m/70 s;
A→U inalcançável. Não representa geografia observada. Mesmos custos são usados
para testar interfaces modais, sem escolher modalidade científica principal.

Contratos: IDs legados sob ambiente declarado, cinco métricas, unidades,
raio OU top-k, desempate, fastest por tempo, sentidos, conectores e snapping,
CEPs locais, batch/retomada, resultados síncronos versus progressivos,
falhas/cancelamento, exportações e ausência de HTTP conhecido em análise offline.

Expectativas não fixam timestamps, caminhos, IDs aleatórios de jobs ou bytes de
HTML/Parquet. Valores numéricos usam `1e-8`, conforme o contrato existente.
Novas diferenças exigem diagnóstico, não atualização automática do baseline.

A captura aceita destino absoluto ou relativo, novo ou existente vazio, sempre
fora de `tests/fixtures/v02`. Resolve o ancestral existente e os symlinks antes
da checagem; o próprio diretório protegido e seus descendentes são recusados.
Diretórios com conteúdo e arquivos existentes nunca são sobrescritos.

## Correção localizada

`R/app.R` conserva o inventário completo filtrado, separado de
`selected_equipment()`, e fixa grupos, acessibilidade, snapshot e total global
ao iniciar a consulta. Downloads não releem os filtros correntes.

`render_proximity_report()` recebe `quality_context = NULL` ao fim da assinatura.
As chamadas posicionais existentes continuam válidas. Sem contexto, o template
declara somente o inventário fornecido. A qualidade conserva inelegíveis;
distâncias e mapas mantêm o subconjunto elegível. A tabela global da interface
continua global. Não se introduz `has_coordinates` nem um relatório espacial vazio.

## CI e reprodução local

CORE: `.github/workflows/ci-core.yml`, em PR, push e acionamento manual.
Instala R 4.6.1, bibliotecas de sistema e Pandoc; restaura o lockfile sem atualizar
versões; depois executa testes e check em cópia isolada sem dados reais.
Não roda targets, coleta, geocodificação online ou validação real.
Um perfil R temporário define `repos = character()` durante o check para impedir
consulta automática ao índice CRAN; dependências já instaladas continuam sendo
verificadas. A verificação remota de ciclos/metadados CRAN não é um gate offline.

```sh
R_PROFILE_USER=/dev/null Rscript scripts/ci/run-core.R /tmp/core-NOVO
bash scripts/ci/run-offline.sh /tmp/rede-NOVO Rscript scripts/ci/run-core.R /tmp/core-NOVO
```

O segundo comando acrescenta observação de chamadas de rede com `strace`, quando
permitido. O modo observado ou limitado fica em `enforcement.txt`. Não é um
sandbox de segurança nem promessa de impossibilidade de acesso externo.
Sem ptrace, continuam os mocks HTTP e os testes negativos; a cobertura dos
processos filhos/bibliotecas é explicitamente limitada. O parser rejeita
endereços externos observados, inclusive tentativas que falham.

BROWSER: `.github/workflows/ci-browser.yml`, somente `workflow_dispatch`.
Usa Python/Playwright fixado, Chromium e pacote candidato instalado; servidor
sintético, CEP/coordenadas, rede pequena, HTML/CSV/ZIP, abas e erros JavaScript.
Requisições externas do navegador são bloqueadas. Isso não certifica o tráfego
do processo R. Os E2E reais existentes não foram substituídos.

## Benchmark

```sh
R_PROFILE_USER=/dev/null Rscript scripts/benchmark_controlled.R --smoke /tmp/bench-NOVO
# Matriz completa, manual e potencialmente demorada:
R_PROFILE_USER=/dev/null Rscript scripts/benchmark_controlled.R /tmp/bench-completo-NOVO
```

Rede sintética determinística 20×20. Matriz: 1/10/100 origens, 25/100/400
destinos, origens distintas/repetidas, três modos e ambos os sentidos/objetivos.
Processo novo por cenário; primeira passagem registrada como aquecimento e cinco
repetições aquecidas (smoke: um cenário e uma repetição).

Mede leitura, validação, vértices, snapping de destinos/origens, geometria,
shortest/fastest e ida/volta, execução síncrona, submissão/início/leitura/total do
web-job e primeira parte. Registra tempos, memória disponível, hashes, dimensões,
parâmetros e ambiente. RSS é máximo da vida do processo, não pico exclusivo da
etapa nem soma de pai/filho. Não limpa cache do SO. Não impõe metas de desempenho.

### Definição das medições após o segundo review

Tempos em segundos; as etapas de rede têm colunas de modo, objetivo e sentido.

| Métrica | Intervalo ou trabalho medido |
|---|---|
| `graph_read` | Leitura e desserialização do RDS sintético já preparado |
| `destination_validation` | Validação e obtenção dos destinos elegíveis |
| `vertices` | Extração da tabela de vértices do grafo |
| `destination_snapping` | Associação dos destinos aos vértices |
| `origin_snapping` | Associação das origens já resolvidas aos vértices |
| `geometry` | Cálculo das cinco métricas geométricas para as origens |
| `network_cost` | `route_one_direction`, com snapping previamente fornecido; shortest/fastest e ida/volta separados |
| `synchronous_complete` | Resolução das origens e chamada completa de `calculate_proximity`, incluindo o trabalho repetido pelo motor atual |
| `web_submit` | Submissão e serialização da requisição, com pool previamente criado |
| `web_launch` | Primeira chamada do controlador que inicia o worker; não mede prontidão do worker |
| `web_first_part` | Início da submissão até observar a primeira parte publicada; não é renderização da interface; NA se nenhuma parte for observada |
| `web_completion` | Início da submissão até observar estado `completed`, antes da leitura funcional final |
| `web_result_read` | Leitura e montagem funcional dos resultados por `web_job_results` |
| `web_total` | Início da submissão até o retorno dos resultados funcionais, incluindo startup, polling e leitura |

O polling de 20 ms faz parte da latência observada pelo controlador; completion
e first_part não são timestamps exatos de publicação no processo filho. As
métricas web são intervalos sobrepostos: não devem ser somadas.

GC forçado de preparação ocorre antes do cronômetro web; coleta de memória,
montagem das linhas, projeções, ordenação, equivalência e hashes do benchmark
ocorrem depois de congelar seu fim. A equivalência continua obrigatória e uma
divergência reprova o cenário. GC automático durante a execução funcional
permanece no tempo observado, tanto no síncrono quanto no web.

Memória web é registrada somente em `web_total`; componentes recebem NA para
não atribuir o pico global a uma etapa. CPU registra somente o processo pai;
RSS continua sendo o máximo da vida do processo. A instrumentação anterior de
`web_total` incluía GC forçado e verificação: seus valores históricos não são
comparáveis diretamente com os corrigidos e não evidenciam melhoria do motor.

`scripts/ci/test-phase0-tools.R`, também executado pelo CORE, usa relógio
simulado para provar que acrescentar custos de GC/verificação não muda as
latências e que resultados divergentes ainda falham. Testa também containment,
aliases e não sobrescrita da captura em diretórios inteiramente sintéticos.

## Gate real separado

`scripts/validate_real_data.R` permanece intacto e não é invocado por CORE,
BROWSER ou benchmark. Para release, usar cópia isolada do código candidato,
fontes e grafos reais montados somente para leitura, ambiente preparado e
diretório novo de outputs. O script escreve em caminho fixo relativo ao projeto:
nunca executá-lo contra outputs históricos para produzir uma evidência nova.

Verificar hashes dos 29 arquivos e três grafos, consolidar os três modos sem
argumentos ao final, exigir 11 métricas e `passed: true`, conferir relatórios e
E2E reais aplicáveis. Registrar código/ambiente/comandos; execução de um modo
isolado não aprova a consolidação. Não confundir funcionamento com acurácia ou
representatividade. Dados reais não são fixtures públicas.

## Aceitação e riscos

- Fixtures abaixo de 1 MiB e duas execuções equivalentes nos campos estáveis.
- Oráculos, seleção, ranking, CEP, estados e equivalência batch/progressivo passam.
- Relatório mostra 4/2/50%; alteração posterior de filtros não muda sua qualidade.
- Testes existentes preservados; nenhuma mudança nos motores para passar testes.
- CORE passa sem erros/warnings; dependências de testes obrigatórios presentes.
- BROWSER manual e benchmark smoke têm evidência própria; workflow remoto só
  será declarado aprovado depois de realmente executar no GitHub.
- `.atomic-*` têm diagnóstico ou inconclusão explícita, sem qualquer descarte.
- Diff restrito ao escopo, ativos reais preservados, sem operações de Git proibidas.

Riscos: locale dos IDs legados; diferenças de bibliotecas espaciais; cobertura
limitada de mocks; flutuação de tempo/memória; testes sintéticos não representarem
escala real; sobrescrita de validações; inspeção de RDS grandes. Mitigações e
resultados estão em [PHASE0_BASELINE.md](PHASE0_BASELINE.md) e
[PHASE0_ARTIFACTS.md](PHASE0_ARTIFACTS.md).
