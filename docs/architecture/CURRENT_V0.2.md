# Arquitetura atual — SampaMaisAgro v0.2

Data de referência: 17/09/2026. Estado: documentação do sistema existente.

Este documento descreve a implementação auditada. Não anuncia funcionalidades
novas nem certifica uma nova execução dos testes. A formalização da migração não
altera código, dados, testes ou ambiente.

## 1. Papel da aplicação e limites científicos

O pacote R `sampamaisrural`, versão 0.2.0, sustenta a aplicação Shiny
SampaMaisAgro. Ele consulta perfis do Sampa+Rural próximos de origens fornecidas
por coordenadas ou CEP previamente preparado, com processamento individual e
em lote, mapas locais e relatórios HTML/PDF.

A unidade cadastral é o perfil publicado, não um estabelecimento físico único.
A análise descreve o cadastro observado e suas limitações. Proximidade não mede,
por si só, acesso efetivo, capacidade, utilização, equidade ou efeito causal.
Nenhuma modalidade de transporte será estabelecida como principal pela
arquitetura da v0.3: essa decisão pertence ao protocolo de pesquisa.

## 2. Componentes e fluxo atual

| Componente | Responsabilidade atual |
|---|---|
| [collect.R](../../R/collect.R) | Coletar catálogo e relatórios, preservar arquivos e manifestos com hashes |
| [normalize.R](../../R/normalize.R) | Normalizar campos conhecidos, gerar identificadores e carregar a base processada |
| [catalog.R](../../R/catalog.R) | Conciliar relatórios, classificar grupos e publicar equipamentos e indicadores |
| [validate.R](../../R/validate.R) | Classificar coordenadas, elegibilidade, quarentena e completude por categoria |
| [distance.R](../../R/distance.R) | Calcular métricas, conectores, ranking, raio OU top-k e diagnósticos |
| [network.R](../../R/network.R) | Construir e carregar grafos por modalidade |
| [offline.R](../../R/offline.R) | Preparar vias e limite local, grafos e contexto cartográfico |
| [web-jobs.R](../../R/web-jobs.R) | Executar consultas em processo supervisionado e publicar resultados progressivos |
| [batch.R](../../R/batch.R), [queue.R](../../R/queue.R) | Partições, checkpoints, retomada e fila persistente SQLite |
| [stats.R](../../R/stats.R) | Grade hexagonal, concordância e modelos exploratórios de contagem |
| [maps.R](../../R/maps.R), [reports.R](../../R/reports.R) | Mapas vetoriais offline e relatórios |
| [app.R](../../R/app.R) | Interface, acompanhamento e apresentação dos resultados |

```mermaid
flowchart LR
    A[Coleta explícita] --> B[Snapshots CSV e JSON]
    B --> C[Normalização e conciliação]
    C --> D[Classificação e validação]
    D --> E[Base equipment]
    F[CEPs locais e grafos OSM] --> G[Motor de proximidade]
    E --> G
    G --> H[Shiny progressivo ou batch]
    H --> I[Mapas, tabelas e relatórios]
```

Os produtos `equipment.csv`, `equipment.json`, `equipment.parquet` e
`equipment.rds` ficam em `data/processed`. O carregador prioriza RDS. Fontes
brutas, CEPs, vias, grafos e resultados locais não acompanham automaticamente o
código distribuído pelo Git.

## 3. Estado dos dados e evidências preexistentes

| Item | Evidência local consultada na auditoria |
|---|---|
| Snapshot cadastral | `20260914T011240Z`; um snapshot local identificado |
| Fontes oficiais | 14 relatórios em CSV e JSON, mais catálogo: 29 arquivos |
| Base completa | 4.238 ocorrências brutas |
| Deduplicação | 71 repetições exatas removidas; zero perfis adicionais dos temáticos |
| Base analítica | 4.167 perfis distintos por conteúdo |
| Coordenadas | 3.321 elegíveis, 844 ausentes e 2 fora do retângulo |
| Doações | Relatório presente e vazio, conforme a fonte |
| Conciliação | 98 chaves auxiliares compartilhadas por 328 perfis distintos |
| Rede | 331.135 vias; data-base OSM registrada como 24/07/2026 |
| Ambiente | `renv.lock` registra R 4.6.1 e 169 pacotes; `dodgr` 0.5.0 |
| Verificação do pacote | Log preexistente com `Status: OK` e 127 verificações aprovadas |
| Validação real | Consolidação arquivada com 11 métricas e `passed: true` |

Os hashes dos 29 arquivos do inventário e dos arquivos-fonte OSM/IBGE foram
conferidos na auditoria anterior. A existência dessas evidências não equivale a
uma nova execução contra qualquer alteração futura.

O manifesto cadastral declara recuperação por auditoria e
`timestamp_basis = local_file_mtime`. Esse horário não deve ser reinterpretado
como data comprovada de requisição HTTP ou data de atualização do cadastro.

As evidências estão descritas em [VALIDACAO_REAL.md](../VALIDACAO_REAL.md).
Os artefatos históricos de demonstração não substituem a validação real.

## 4. Contratos funcionais a preservar

- Após preparação, consultas, mapas e downloads funcionam offline. Um CEP
  desconhecido gera erro explicativo; não recebe localização inventada.
- A base real é obrigatória no fluxo padrão. Dados sintéticos exigem opt-in.
- São calculadas cinco métricas geométricas. Redes podem acrescentar caminhada,
  bicicleta e automóvel, com objetivos `shortest` e `fastest`.
- As redes permitem ida, volta ou ambas e avaliam todos os destinos elegíveis.
- A seleção é raio **OU** top-k por origem, métrica e sentido. Fastest é
  ordenado por minutos; o raio existente continua expresso em metros.
- Conectores estimados entram nos custos. Snapping acima de 250 m recebe
  alerta e acima de 1.000 m é excluído, conforme configuração atual.
- Resultados parciais são identificados. Cancelar encerra o processo de cálculo
  e preserva as partições concluídas.
- Shiny mantém um processo pesado ativo por instância e carrega uma rede por
  vez no fluxo progressivo. A fila SQLite é um mecanismo separado.
- Batch valida IDs globalmente, preserva erros por linha e impede retomada
  quando os insumos cobertos pelo fingerprint mudam.
- Contatos diretos não são promovidos às exportações analíticas atuais.

## 5. Lacunas observadas

### Fontes e modelo de dados

Não existem registry unificado, verificação independente de atualização, schema
drift, identidade longitudinal ou snapshot diff. O ETag é associado ao destino
do download e não é normalmente reaproveitado entre novos diretórios de snapshot.

`equipment_id` é hash de conteúdo; `record_version_id` também incorpora o
snapshot. `source_key`, composto por nome, categoria, fonte e endereço, é uma
chave de conciliação potencialmente ambígua. A deduplicação dos adicionais por
essa chave pode descartar conteúdos diferentes em snapshots futuros.

Os relatórios têm 37 campos distintos no conjunto; a base completa contém 32.
Agricultura familiar, DAP, certificados e áreas em hectares aparecem em temáticos.
Há listas, booleanos, faixas textuais e sentinelas de ausência que não são
plenamente representados no modelo analítico plano.

### Qualidade e estatística

O relatório emitido pela interface recebe `selected_equipment()`, composto por
elegíveis. Sua tabela de qualidade pode perder os registros sem coordenadas do
denominador. A correção e seu teste são obrigatórios na Fase 0 futura; esta
formalização não corrige o código.

A qualidade é resumida principalmente por categoria. A análise de disponibilidade
de coordenadas, seus estratos e seus possíveis mecanismos ainda não existe.
No grupo derivado de agricultores, 68 de 875 perfis são mapeáveis; os grupos
se sobrepõem e seus totais não podem ser somados.

A API estatística possui GLMs com diagnóstico espacial residual, não um modelo
espacial completo por definição. Faltam validação rigorosa dos insumos,
tratamento explícito das falhas e a maioria das capacidades científicas
candidatas descritas em [SCIENTIFIC_METHODS.md](SCIENTIFIC_METHODS.md).

### Desempenho e reprodução

- Vértices e snapping dos destinos são refeitos entre origens; já há reuso
  entre objetivos/sentidos de uma mesma origem e modalidade.
- Transformações de CRS, classificações e validações são repetidas.
- Etapas de rede recalculam resultados geométricos depois descartados.
- A interface relê as partições acumuladas quando recebe novas partes.
- O batch calcula fingerprint do conteúdo integral dos grafos; o worker CLI
  carrega todos os modos, com custo de memória.
- Os diagnósticos de roteamento não incluem direção na agregação.
- Mapas mostram pontos e vias de contexto; não há geometria dos trajetos.
- A publicação dos vários arquivos processados não é atômica como conjunto.
- A limpeza da fila SQLite não cobre os diretórios de jobs web.
- `_targets.R` força coleta e não declara corretamente todas as dependências
  dos arquivos produzidos; não reconstrói toda a análise offline.
- Não há CI versionada. O benchmark atual não representa adequadamente lotes
  de origens distintas com todas as redes.

## 6. Leitura conjunta e precedência

Preservar [PROTOCOL.md](../../PROTOCOL.md), [CODEBOOK.md](../../CODEBOOK.md),
[README.md](../../README.md) e os testes como referências existentes.
`PLANEJAMENTO_PROJETO.txt` registra intenções históricas, não o estado implementado.

As decisões aprovadas de migração estão em [TARGET_V0.3.md](TARGET_V0.3.md) e no
[plano de migração](../migration/V0.3_PLAN.md). Em particular, uma indicação
histórica de modalidade principal não constitui decisão arquitetural da v0.3.

## 7. Proteção da v0.2 — Fase 0

A descrição anterior registra o estado auditado antes da implementação da
proteção. A Fase 0 acrescenta fixtures, contratos, CI e benchmark sintéticos.
Corrige somente a qualidade do relatório: inventário filtrado completo e contexto
fixado no início da consulta, preservando o subconjunto espacial e os motores.
Evidências e limites: [PHASE0_BASELINE.md](../migration/PHASE0_BASELINE.md).
Não houve implementação da Fase 1 ou das capacidades científicas da v0.3.
