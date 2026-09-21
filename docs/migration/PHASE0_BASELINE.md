# Fase 0 — Estado protegido e evidências

Base: `c751eccbfbfa38a522e50c828be4278cdcda43d9`.
Branch preservada: `refactor/scientific-platform-v0.3`.
Árvore limpa antes da implementação. Nenhum commit, push, tag ou troca de branch.

## Referência real preservada

A referência histórica é o snapshot `20260914T011240Z`: 14 pares CSV/JSON,
catálogo, 4.238 ocorrências, 71 duplicatas exatas removidas, 4.167 perfis e
3.321 elegíveis. Os hashes permanecem nos manifestos e no inventário existentes.
Essas contagens pertencem a esse snapshot, não são constantes para novos dados.

As evidências descritas em [VALIDACAO_REAL.md](../VALIDACAO_REAL.md) continuam
históricas. A Fase 0 não reexecutou a validação pesada nem sobrescreveu seus outputs.
O gate futuro está em [PHASE0_PLAN.md](PHASE0_PLAN.md).

## Baseline sintético

Os dados e expectativas estão em [tests/fixtures/v02](../../tests/fixtures/v02/README.md).
O manifesto fixa commit, snapshot sintético, hashes dos insumos, R, pacotes,
bibliotecas espaciais, contagens e tolerância `1e-8`. A captura foi feita antes
de alterar `R/app.R` e `R/reports.R`.

Foram conferidos independentemente 8/7/3 registros e os custos A→D 200 m
shortest, 300 m/20 s fastest, D→A 350 m/70 s e componente desconectado.
`records.csv`, `proximity.csv`, `routing.csv` e `batch.json` conservam somente
campos estáveis. O script de captura exige destino novo fora das expectativas
aprovadas e nunca é chamado pelos testes.

### Achado preexistente: locale e identidade legada

A v0.2 aplica `sort(names(payload))` antes do hash. Com nomes de campo acentuados,
`LC_COLLATE=C.UTF-8` e `LC_COLLATE=C` produziram IDs diferentes sem qualquer
mudança de conteúdo ou do normalizador. O primeiro perfil sintético produziu
`03076029d7c50c0aa399a859` em C.UTF-8 e `5bd99a762ef49fe0b74c1695` em C.

O testthat usa ambiente de comparação reproduzível com collation C. A captura
aprovada e o carregador de fixtures fixam C explicitamente. Comparar as duas
capturas mostrou mudança apenas em `equipment_id` e `record_version_id`;
projeções espaciais, diagnósticos e batch eram idênticos byte a byte.

Classificação: **preexisting**, com manifestação dependente do ambiente.
Não foi corrigido nem reinterpretado como identidade temporal; normalizador e
IDs reais permanecem intactos. Migrações futuras precisam considerar essa condição.

## Única correção funcional

O download da interface transmitia `selected_equipment()`, excluindo perfis
sem coordenadas do denominador. Agora transmite inventário filtrado completo
e contexto capturado ao iniciar a consulta. A análise espacial não mudou.

Testes verificam 4 perfis, 2 elegíveis, 50%, ausência de distâncias para
inelegíveis, contexto depois de editar filtros, substituição por nova consulta,
chamada posicional legada, HTML completo/parcial e ausência de inventário elegível.
O resumo global permanece separado do inventário filtrado do relatório.

## Execuções e limitações

Verificação final em 18/09/2026, após retomar a sessão interrompida. Branch,
HEAD e alterações existentes foram conferidos antes de qualquer edição. O
resultado da execução CORE interrompida não foi presumido: seus artefatos em
`/tmp` não estavam disponíveis. As execuções abaixo geraram diretórios novos em
`outputs/phase0/`, ignorados pelo Git, sem substituir evidências históricas.

Ambiente local: Ubuntu 22.04.5, R 4.6.1, Pandoc 3.8, Playwright 1.62.0 e Google
Chrome instalado. Versões dos pacotes e bibliotecas espaciais estão nos
manifestos e `session-info.txt` das execuções. O workflow usa Ubuntu 24.04;
restauração limpa do lockfile e execução remota no GitHub ainda não foram
demonstradas nesta entrega, que não fez commit ou push.

| Verificação | Resultado | Evidência local, relativa a `outputs/phase0/` |
|---|---|---|
| `testthat::test_local()` em cópia isolada | 46 casos; 276 verificações aprovadas; zero falhas, avisos e skips | `resume-20260918-core/testthat-results.rds` |
| Testes aditivos da Fase 0 | 14 casos; 149 verificações aprovadas; as 127 existentes continuam aprovadas | Mesmo RDS, arquivos `test-phase0-*` |
| `R CMD build` e check do pacote construído | `Status: OK`; pacote instalado repete 276 verificações aprovadas | `resume-20260918-core/build.log`, `check.log`, `sampamaisrural.Rcheck/tests/testthat.Rout` |
| CORE com observação de processos descendentes | Exit 0; nenhuma operação IP externa observada | `resume-20260918-network/network.trace`, `enforcement.txt` |
| Benchmark smoke | Concluído; 400 vértices, 1.520 arestas, 1 origem, 25 destinos, 32 medições em 13 etapas | `resume-20260918-core/benchmark-smoke/` |
| BROWSER sintético, pacote candidato instalado | Aprovado; zero erros JavaScript e zero requisições externas observadas no navegador | `resume-20260918-browser/evidence.json`, CSV, HTML e ZIP |
| Recaptura independente do baseline | `records.csv`, `proximity.csv`, `routing.csv` e `batch.json` idênticos às projeções aprovadas | `resume-20260918-baseline/`; expectativas não sobrescritas |
| Check direto da pasta, atual e commit-base | Mesmo erro de metadados em ambos; classificado abaixo | `resume-20260918-source-checks/comparison.json` |

Comando do CORE executado na raiz, com caminhos absolutos para os dois
diretórios novos:

```sh
bash scripts/ci/run-offline.sh "$REPO/outputs/phase0/resume-20260918-network" \
  Rscript scripts/ci/run-core.R "$REPO/outputs/phase0/resume-20260918-core"
```

`REPO` representa a raiz local do checkout. O runner define
`R_PROFILE_USER=/dev/null` e executa testthat, build, check e smoke. Novas
execuções devem escolher outros destinos: os scripts recusam sobrescrita.

O sandbox local recusou ptrace/strace (**environmental**). Após autorização,
o CORE foi executado fora desse sandbox com observação por `strace` dos
processos descendentes. O parser passou seus controles positivos/negativos e
não encontrou operações IP externas na execução final. Trata-se de observação
desta execução, não de isolamento de rede pelo kernel. Sem ptrace, o runner
declara explicitamente o fallback limitado aos mocks HTTP conhecidos.

Uma execução anterior identificou tentativa de consulta ao índice CRAN pelo
próprio `R CMD check`, mesmo com incoming remoto desativado. A infraestrutura
CORE foi corrigida para usar perfil R temporário com `repos = character()`.
Dependências instaladas continuam verificadas; metadados remotos do CRAN não
são parte desse gate offline. A execução final passou com essa configuração.
O bloqueio do navegador é separado e não certifica o tráfego do processo R.

`R CMD check . --no-manual` falha neste ambiente por ausência dos campos
`Author` e `Maintainer`, tanto na cópia atual quanto numa extração de
`c751ecc` por `git archive`. Classificação: **preexisting**, confirmada sob o
mesmo ambiente. `DESCRIPTION` permanece intacto. `R CMD build` deriva os
metadados de `Authors@R`; o check desse pacote construído passa integralmente.

Erros durante construção do harness (setup de mocks antes do ambiente de
teardown, passagem incorreta de argumentos ao testServer e comparação de
origens resolvidas versus não resolvidas no benchmark, interação com Selectize
e preparação do inventário sintético do navegador) são classificados como
**introduced by this phase** na infraestrutura de testes, corrigidos sem
alterar os motores. Não justificaram afrouxar tolerâncias ou recalcular custos
esperados. O smoke do navegador representa uma instalação offline preparada;
não certifica a interface com inventário ausente. A montagem incompleta havia
exposto erro de renderização da tabela de inventário, fora da correção funcional
autorizada nesta fase.

O smoke executado sob strace comprova funcionamento do benchmark, não estabelece
um patamar de desempenho. A matriz completa, comparações de velocidade sem
instrumentação e a validação real pesada não foram executadas. RSS representa
o máximo da vida do processo, conforme documentado pelo benchmark.

## Conferência do escopo protegido

- Fixtures totalizam 29.985 bytes; hashes dos insumos coincidem com o manifesto.
- Entre os módulos R, somente `app.R` e `reports.R` diferem dos hashes-base.
  Os testes preexistentes, motores, `_targets.R`, `DESCRIPTION`, `NAMESPACE`,
  `renv.lock` e `scripts/validate_real_data.R` permanecem inalterados.
- Os 180 arquivos preexistentes em `data/` e `outputs/` mantiveram tamanho e
  mtime na retomada. Essa conferência de metadados não substitui hashes de
  conteúdo; grafos e `.atomic-*` grandes não foram lidos integralmente.
- `git diff --check` passou. Não houve limpeza, commit, push ou troca de branch.
- A implementação permanece limitada à Fase 0. A Fase 1 não foi iniciada.
