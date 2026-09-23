# Fase 1 — entrega incremental, checkpoint 1A

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
