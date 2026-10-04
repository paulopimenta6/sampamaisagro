# Fase 1 — entrega incremental, checkpoint 1A e checkpoint 1B, Passo I

Base confirmada antes de editar: `3cbf004`,
`test: protect v0.2 behavior before v0.3 refactor`, branch
`refactor/scientific-platform-v0.3`, working tree inicialmente limpo.

O plano read-only da Fase 1 foi aprovado com ajustes posteriores. Esta entrega
implementa SOMENTE registry, contratos, validação/perfil estrutural,
fingerprint/drift e consistência CSV/JSON, com fixtures e testes offline.
Não representa conclusão da Fase 1 completa. As instruções deste checkpoint
substituem propostas anteriores de antecipar fontes auxiliares ou integração.

## Ajustes incorporados

- source_id é interno, estável e separado do nome; não se inventa report_id.
- catalog_slug vem do basename JSON inequívoco fornecido pelo catálogo antes
  do download. JSON e CSV pertencem à mesma fonte e seus slugs precisam coincidir.
- URLs efetivas dos relatórios são descobertas no catálogo. Não estão fixadas
  nas entradas de relatórios como identidade eterna.
- O payload pode conter slug, mas ele não é necessário para reconciliar o catálogo.
- Registry executável restrito a catálogo, 14 relatórios e termos.
- Sem alteração da semântica de snapshots parciais ou da coleta atual.
- Não existe campo snapshot_should_be_created; o checker futuro não decidirá
  criação de snapshot. Coleta explicitamente solicitada e check são separados.

## Implementado em 1A

1. Assets locais versionados em inst/sources, distribuídos pelo pacote.
2. R/source-registry.R: carregamento/validação e reconciliação pura do catálogo.
3. R/source-schema.R: leitura local, validação do contrato/payload, perfil,
   fingerprint canônico, drift explicável e comparação da projeção CSV/JSON.
4. Fixtures inteiramente sintéticas e testes aditivos em tests/fixtures/phase1
   e test-phase1-*.R. Nenhuma expectativa anterior foi recalculada.
5. [SOURCE_LAYER.md](../architecture/SOURCE_LAYER.md): decisões, interfaces
   internas, regra de identidade, contratos, evidência parcial e limites.

Nenhum símbolo novo é exportado. Não houve mudança de dependência, configuração
da aplicação, NAMESPACE, DESCRIPTION, renv.lock ou workflow.

## Checkpoints seguintes — não implementados

- Source State: estado operacional mutável por fonte/representação.
- Transporte/validators/update checking: verificações remotas explícitas.
- Integração compatível de collect_sampa_data e proveniência dos novos snapshots.
- Inspeção/recuperação explícita e gate mínimo de entrada na preparação.

Cada etapa exige autorização própria. Não foram criados módulos vazios,
scripts, estado persistente ou pontos de chamada para essas entregas.
Source Registry (configuração), Source State (estado futuro) e Snapshot
Provenance (evidência histórica futura) continuam conceitos separados.
A Fase 2 não foi iniciada.

## Validação e critérios de aceite de 1A

- Registry padrão contém uma complete_base habilitada e 13 thematic_subset.
- Duplicatas de identidade, cobertura e URLs inadequadas geram diagnóstico.
- Mudanças de apresentação/URL compatível não mudam source_id.
- Contratos rejeitam envelope/itens/tipos incompatíveis; adições são permitidas.
- Vazio, null e arrays sem itens mantêm evidência insuficiente explícita.
- Fingerprint ignora valores, ordem e frequências; mudança nested é detectável.
- CSV/JSON respeitam quoting, BOM, null, booleanos, listas e duplicatas.
- Pares com contagens iguais e conteúdos diferentes falham.
- Funções são locais e puras quanto a rede/escrita; contratos não se autocorrigem.
- Proteção da Fase 0 preservada, testthat e CORE/build/check/smoke aprovados.

Comandos de referência (usar diretórios de evidência novos):

```sh
R_PROFILE_USER=/dev/null Rscript -e 'testthat::test_local(filter="phase1")'
R_PROFILE_USER=/dev/null Rscript -e 'testthat::test_local()'
bash scripts/ci/run-offline.sh /tmp/phase1a-network-NOVO \
  Rscript scripts/ci/run-core.R /tmp/phase1a-core-NOVO
git diff --check
git status --short
git diff --stat
```

O CORE aprovado executa testthat, build, R CMD check do pacote construído e
benchmark smoke. Não executar targets, coleta ou validação real. O modo de
observação de rede fica em enforcement.txt: strace observa quando disponível;
o fallback aos mocks não é apresentado como isolamento completo de rede.

Falhas encontradas durante desenvolvimento do 1A: percent-encoding era
decodificado antes da política de URL, e uma comparação com referência gerava
aviso de remoção para relatório vazio. Ambos foram corrigidos nos módulos novos,
sem mudar expectativas aprovadas ou componentes da v0.2.

## Evidência da entrega 1A — 21/09/2026

| Verificação | Resultado |
|---|---|
| Testes direcionados | 17 testes, 166 verificações, sem falhas/warnings/skips |
| testthat completo | 475 verificações: 309 preservadas + 166 novas; sem falhas/warnings/skips |
| CORE isolado | Concluído com exit 0; testes locais e do pacote instalado aprovados |
| Build + R CMD check | Pacote construído; `Status: OK` |
| Benchmark smoke | Concluído; equivalência funcional conferida pelo script aprovado |
| Metadata local do catálogo de referência | Reconciliação pura: 14 fontes, 28 representações, valid; nenhuma requisição |
| Arquivos protegidos em data/ | 93 arquivos com tamanho e mtime preservados; sem leitura integral de grafos/.atomic-* |

Evidências locais desta execução: `/tmp/phase1a-testthat.log`,
`/tmp/phase1a-targeted-results.rds`, `/tmp/phase1a-core.log`,
`/tmp/phase1a-final-core-3cbf004/` (build/check/testthat/benchmark) e
`/tmp/phase1a-final-network-3cbf004/enforcement.txt`.
São artefatos locais de validação, não arquivos necessários ao pacote.

O sandbox recusou ptrace: o runner utilizou o fallback aprovado de mocks HTTP.
Não houve observação completa de syscalls e não se afirma isolamento de rede
pelo kernel. Browser E2E, coleta e validação real não foram executados neste
checkpoint; aplicação e motores permanecem intactos. Nenhuma execução remota de
GitHub Actions desta mudança foi anunciada: não houve commit ou push.

## Autorização posterior — checkpoint 1B, Passo I

Base confirmada: `248a9cf`, `feat: add source registry and schema contracts`,
branch `refactor/scientific-platform-v0.3`, working tree inicialmente limpo.
As seções e evidências anteriores descrevem a entrega histórica do 1A; seu
estado aprovado atual protege 790 verificações. Não se reescreve esse histórico.

O Passo I implementa somente identidade de requisição, Canonical JSON v1, estado
operacional, revisões imutáveis/checksum chain, escrita atômica, lock por fonte,
cache de bytes por SHA-256 e transições explícitas candidate/validated. As
interfaces internas e limitações estão em [SOURCE_LAYER.md](../architecture/SOURCE_LAYER.md).

Criados R/source-state.R, R/source-http.R, dois arquivos de testes e helper
sintético. R/source-http.R é puro e não faz HTTP. Sem fixtures reais, exports,
dependências, alteração do registry/contratos, configuração ou código legado.
Testes usam diretórios temporários próprios, bytes inventados e falhas injetadas.
O teste de concorrência usa dois processos locais com uma barreira controlada.

Gates: testes direcionados, todos os phase1, suíte completa, CORE offline
aprovado com build/R CMD check e benchmark smoke. Não executar browser, targets,
GitHub Actions, coleta ou serviços externos. Evidências ficam somente em /tmp.

Não estão implementados HTTP/validators/Conditional GET, checker público ou
integração com collect. Não há decisão de snapshot nem mudança em raw, processed,
manifestos ou snapshots parciais. Não iniciar checkpoint 1C ou Fase 2.

### Evidências do Passo I — 30/09/2026

| Verificação | Resultado |
|---|---|
| Testes novos direcionados | 17 testes, 293 verificações, sem falhas/warnings/skips |
| Todos os phase1 | 774 verificações aprovadas |
| testthat completo | 1.083 verificações: 790 anteriores + 293 novas; sem falhas/warnings/skips |
| Concorrência local | Dois processos reais; exatamente um adquiriu o lock |
| CORE offline isolado | Exit 0; testes locais e do pacote instalado aprovados |
| Build + R CMD check | Pacote construído; Status: OK |
| Benchmark smoke | Concluído pelo runner aprovado, sem alteração de engines |

Logs/artefatos: `/tmp/phase1b-step1-final-directed-phase1.log`, resultados RDS
direcionados/phase1, `/tmp/phase1b-step1-testthat.log`,
`/tmp/phase1b-step1-core.log`, `/tmp/phase1b-step1-core/` e
`/tmp/phase1b-step1-network/enforcement.txt`. Nenhuma evidência histórica foi
sobrescrita. O sandbox bloqueou strace: enforcement LIMITED, com mocks HTTP
conhecidos, sem afirmar isolamento completo de rede ou observação de syscalls.

A primeira rodada direcionada identificou referência não qualificada a
file_test no ambiente isolado dos processos filhos. Foi corrigida no módulo
novo usando utils::file_test, mantendo as expectativas de concorrência.
Não houve coleta, API externa, browser E2E, targets ou GitHub Actions.
