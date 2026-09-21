# Fase 0 — Inspeção de artefatos `.atomic-*`

Inspeção em 17/09/2026, exclusivamente de leitura. Nenhum arquivo foi apagado,
renomeado, movido, substituído ou recuperado. Não foi carregado nenhum objeto
completo em memória.

## Inventário observado

Todos os caminhos abaixo são relativos ao repositório.

| Campo | Primeiro arquivo | Segundo arquivo |
|---|---|---|
| Caminho | `data/processed/.atomic-26259040c.rds` | `data/processed/.atomic-217cd424f.rds` |
| Bytes | 515.407.872 | 479.494.144 |
| Inode | 6200819 | 6200809 |
| Proprietário/grupo | paulo/paulo | paulo/paulo |
| Permissões | `-rw-rw-r--` | `-rw-rw-r--` |
| mtime UTC | 2026-09-15 19:45:19.910592 | 2026-09-15 03:14:03.807456 |
| ctime UTC | 2026-09-15 19:45:19.910592 | 2026-09-15 03:14:03.807456 |
| Descritores abertos visíveis | Nenhum identificado | Nenhum identificado |
| Classificação | `inconclusive` | `inconclusive` |

`ctime` indica mudança de metadados, não comprova criação. A leitura pode atualizar
atime segundo a política do filesystem; atime não foi usado para inferir origem.

## Método e evidências

- `stat` por Python: tamanho, inode, permissões, proprietário, mtime e ctime.
- Varredura dos links `/proc/<pid>/fd`: nenhum descritor correspondente na visão
  disponível; zero diretórios de descritores recusados nessa varredura. A visão
  do sandbox pode não abranger processos externos; ausência não prova inatividade.
- `file` e leitura dos primeiros 32 bytes: assinatura gzip `1f8b08` em ambos.
- Leitura de somente 32 bytes descomprimidos com `gzip`: cabeçalho `X\n`, formato
  de serialização R versão 3, versão escritora codificada 4.6.1, UTF-8.
- Prefixos comprimidos e cabeçalhos iguais não demonstram conteúdo igual.
- Nenhum `readRDS()` integral, descompressão integral, teste de CRC completo ou
  comparação semântica de objetos foi realizado. Os tamanhos anunciados por
  `file` no trailer gzip, módulo 2^32, não foram tratados como tamanho validado.

## Origem possível e arquivos finais

`R/utils.R::atomic_save_rds()` cria `.atomic-*.rds` no diretório de destino,
registra remoção ao sair e renomeia o temporário após `saveRDS()`. Grafos são
publicados por esse helper. Uma morte abrupta pode deixar temporário; isso é
uma hipótese técnica, não diagnóstico desses arquivos.

| Candidato final | Bytes | mtime UTC |
|---|---:|---|
| `data/processed/network_foot.rds` | 560.725.096 | 2026-09-15 03:06:13.786558 |
| `data/processed/network_bicycle.rds` | 552.396.613 | 2026-09-15 19:59:31.006589 |
| `data/processed/network_motorcar.rds` | 486.101.020 | 2026-09-15 20:24:27.036927 |

Tamanho, diretório e proximidade temporal tornam gravações de grafos candidatas
a investigação. Não há vínculo de destino comprovado, PID original identificado
ou igualdade com um arquivo final. Também não há prova suficiente de truncamento.

## Classificação e continuidade

`active` requer evidência de escritor/atividade. `readable_unmatched` requer
leitura integral válida. `equivalent_to_final` requer comparação comprovada.
`possibly_truncated` requer evidência de falha/truncamento. Como nenhuma dessas
condições foi demonstrada, ambos permanecem `inconclusive`.

Se necessário em uma etapa explicitamente autorizada: repetir o inventário e
a inspeção de descritores na visão do host, relacionar logs/processos, verificar
estabilidade, calcular hashes em fluxo e só então considerar leitura isolada
com limite de memória/tempo. Essa investigação não autoriza limpeza. Mesmo
igualdade comprovada com um final não constitui autorização para apagar.

## Conferência na retomada — 18/09/2026

Os dois arquivos continuam presentes com os tamanhos registrados acima e
mtime preservado, respectivamente `1789501519910591966` e
`1789442043807456550` nanossegundos desde a época Unix. Nenhuma nova leitura
integral foi realizada. A classificação permanece `inconclusive`; esta
conferência não acrescenta evidência sobre processos ativos fora do sandbox.
