# Camada de fontes — checkpoint 1A e checkpoint 1B, Passo I

Referência protegida: `3cbf004`, branch `refactor/scientific-platform-v0.3`.
Este checkpoint acrescenta funções **internas**, dados declarativos e testes.
Nenhuma API pública existente ou caminho de execução da aplicação foi alterado.

## Separação de responsabilidades

- **Source Registry** é configuração versionada: fontes, identidade de catálogo,
  representações, contratos e política de URLs. Está implementado neste checkpoint.
- **Source State** tem infraestrutura operacional local implementada no Passo I
  do checkpoint 1B, descrita ao final. Não há política HTTP ou checker.
- **Snapshot Provenance** será evidência histórica imutável de uma captura. Não
  foi implementada nem acrescentada aos snapshots existentes.

Esses conceitos não são equivalentes. Não há checker, transporte HTTP novo,
integração com coleta, gate analítico, recuperação nova ou componente da Fase 2.
OSM, CEP e IBGE continuam integrações externas existentes, sem contratos executáveis
ou novas operações neste registry 1A.

## Registry e identidade

[registry.yml](../../inst/sources/registry.yml) contém revisão `1.0.0`: 14 fontes
lógicas de relatórios, catálogo e termos. Cada relatório possui representações
JSON e CSV; elas não são duas fontes independentes. A única base completa
habilitada é `sampa.complete`; os 13 recortes declaram sobreposição com ela.
Isso é metadata semântica, não uma nova regra de junção ou reconciliação de perfis.

O catálogo local de referência `20260914T011240Z/data_reports.json` foi inspecionado
somente para verificar a estrutura da metadata: 14 basenames JSON únicos e 14
CSV correspondentes, no host oficial e com as extensões esperadas. Nenhuma API
foi consultada e nenhum registro real foi copiado para fixtures. O campo `kind`
do catálogo não foi convertido automaticamente em contrato de tipos.

| source_id interno | catalog_slug disponível antes do download |
|---|---|
| sampa.complete | base-completa-sampa-rural |
| sampa.agricultores_contato | agricultores-com-contato-sisrural |
| sampa.agricultores_sp | agricultores-na-cidade-de-sao-paulo-sisrural |
| sampa.agricultores_vivencia | agricultores-receptivos-em-vivencia-rural-sampa-rural |
| sampa.hortas | hortas-urbanas-e-hortas-em-equipamentos-publicos-sampa-rural |
| sampa.aldeias | aldeias-indigenas-guarani-sampa-rural |
| sampa.parceiros | parceiros-da-producao-local-sampa-rural |
| sampa.feiras_organicas | mapa-de-feiras-organicas-idec |
| sampa.feiras_livres | feiras-livres-municipais-geosampa-secretaria-municipal-de-desenvolvimento-urbano |
| sampa.mercados | restaurantes-organicos-entregas-de-organicos-e-outras-bases-de-mercados-sampa-rural |
| sampa.servicos | servicos-para-agricultura-sampa-rural |
| sampa.atrativos | atrativos-turisticos-dos-polos-de-ecoturismo-secretaria-municipal-de-turismo |
| sampa.iniciativas | iniciativas-e-politicas-publicas-sampa-rural |
| sampa.doacoes | pontos-de-doacao-sp-cidade-solidaria |

`sampa.catalog` e `sampa.terms` não possuem `catalog_slug`. Seus endpoints de
bootstrap referenciam `catalog_url`/`terms_url` e registram defaults oficiais.
O módulo não efetua requisições nem altera a configuração atual.

`source_id` é uma decisão interna versionada; não é `report_id` oficial nem
identidade de estabelecimento. Não existe campo `report_id` inventado.
O nome de apresentação não participa do matching. O `slug` eventualmente
presente no payload é campo opcional conhecido; não é a chave da reconciliação
pré-download nem recebe validação de igualdade com a fonte neste checkpoint.

`reconcile_source_catalog(registry, catalog)` é pura: recebe uma lista JSON
fornecida pelo chamador e devolve `mapping`, `issues`, `classification` e
`decision`. Cada linha do mapping associa source_id, representação, índice do
catálogo, URL efetiva e filename esperado. Não escreve nem modifica o registry.

Regras de resolução:

1. URL absoluta, esquema/host/porta explicitamente permitidos.
2. Sem credenciais, fragmentos, espaços, backslashes, traversal ou caminhos
   percent-encoded ambíguos; query strings são permitidas pela política padrão.
3. Basename literal com slug `[a-z0-9]+(-[a-z0-9]+)*` e extensão `.json`/`.csv`.
4. JSON e CSV devem fornecer o mesmo slug; JSON identifica a entrada antes da
   leitura de qualquer payload de relatório.
5. URL pode mudar de diretório/query ou para outro host explicitamente permitido,
   mantendo o mesmo source_id se o slug permanecer. URLs efetivas não ficam
   congeladas nas entradas de relatórios do registry.
6. Slug novo não ganha source_id automaticamente. Mudança do próprio slug exige
   revisão deliberada; aliases não são inferidos.

Fonte adicional gera `coverage_drift`/`review`; ausência de fonte habilitada,
duplicidade, representação ausente, URL inválida ou incompatibilidade JSON/CSV
gera `breaking`/`block`. Esses resultados não acionam coleta ou publicação.
Fontes desabilitadas conhecidas continuam identificáveis, com `enabled = false`.
`complete_slug` continua na configuração; seu valor coincide com catalog_slug
da base de referência. A seleção legada por filename permanece intacta.

## Contratos executáveis

Os assets ficam em `inst/sources`, disponíveis no checkout via pkgload e no
pacote instalado via `system.file()`. `load_source_registry()` também verifica
as referências locais e a compatibilidade das representações com os contratos.
Não há alterações em DESCRIPTION, NAMESPACE ou renv.lock.

- `catalog-v1.yml`: array não vazio de objetos; nome e URLs JSON/CSV obrigatórios;
  atributos conhecidos como lista de objetos com label. Política de URLs e
  cobertura são verificadas separadamente pela reconciliação.
- `reports-v1.yml`: objeto com `/partners` obrigatório, array de objetos, vazio
  permitido; quatro campos cadastrais obrigatórios e nullable; 37 campos públicos
  conhecidos no total, com strings, booleanos, números e arrays de strings.
- `terms-v1.yml`: string não vazia com envelope HTML de abertura/fechamento.
  É uma verificação mínima do documento, não um parser DOM nem análise jurídica.

Os quatro campos obrigatórios são Nome do Perfil, Categoria, Fonte e Endereço
comercial. Coordenadas são opcionais e nullable: recortes sem coordenadas não
falham. Coordenadas como texto são compatíveis, mas geram aviso de variação de
tipo; não são convertidas ou corrigidas. Não se avalia limite espacial aqui.
Campos de área permanecem strings. Campos novos não são promovidos para equipment.

O contrato comum permite ausência de campos opcionais; não presume que todos os
14 recortes exponham os mesmos campos. Não foi criada uma restrição por perfil
que exija coordenadas de recortes estruturalmente sem elas.

`load_schema_contract()` valida o próprio vocabulário declarativo: versão,
tipos, flags, records path, objetos/propriedades, arrays/itens, mínimos, padrões
e projeção CSV. Erros de configuração falham explicitamente, inclusive opções
desconhecidas; contratos não são aprendidos ou reescritos a partir dos dados.
O vocabulário é deliberadamente menor que JSON Schema; não implementa toda essa
especificação. Objetos aninhados são suportados por properties e items.

`read_source_payload(path, representation)` exige arquivo local. Usa parse_json
sem simplificação para distinguir `{}` de `[]`; não permite que uma string seja
interpretada como URL. Erros de parsing são sanitizados, sem reproduzir payload.
`validate_source_payload()` recebe o objeto, contrato, source_id opcional,
representação e perfil de referência opcional. Não modifica o objeto fornecido.

## Perfil, fingerprint e drift

`profile_source_schema()` observa caminhos, famílias de tipos, observações e
nulos. Os caminhos começam em `$`, usam `/` entre campos e `/*` para itens;
`~0`, `~1`, `~2` escapam respectivamente `~`, `/` e `*` em nomes de campos.
O perfil não armazena valores dos registros. Integer/double são `number`.

`schema_fingerprint()` devolve a representação canônica inspecionável, SHA-256,
qualidade da evidência e caminhos sem tipo observado. Ordena campos/tipos em
ordem radix UTF-8, excluindo contagens, valores, frequência, timestamps e frações
de nulos. Reordenar registros/campos ou variar valores com a mesma estrutura
observável não altera o fingerprint.

Null isolado e array vazio não provam tipo. Quando faltar evidência, `sha256`
completo é NA e `evidence_quality = partial`. `observed_sha256` identifica apenas
o descritor parcial: mudanças de cobertura não são prova de drift estrutural.
Não se inventa um fingerprint completo preenchendo tipos com o contrato. Assim,
perder a última observação não nula torna a evidência insuficiente, em vez de
afirmar uma nova estrutura. Inferir estrutura sem observá-la não é possível.

O resultado de validação contém source_id, representação, contrato/versão,
classificação, decisão, mudanças por caminho e qualidade/cobertura de evidência.
Se houver múltiplas condições, a precedência é breaking, suspicious, additive,
insufficient_evidence, valid; a evidência parcial continua visível separadamente.

| Classe | Decisão | Exemplos |
|---|---|---|
| valid | allow | Estrutura observada compatível e suficiente |
| additive | allow | Campo adicional, preservado e reportado |
| suspicious | warn | Tipo permitido fora do preferencial; mudança de tipo observado; campo opcional desaparecido com referência observável |
| breaking | block | Envelope/records incorretos, obrigatório ausente, tipo ou estrutura aninhada incompatível, chaves ambíguas |
| insufficient_evidence | allow | Relatório vazio, campo só null, itens nunca observados |

`compare_schema_to_contract()` compara o perfil com a configuração. A validação
completa também confere restrições por instância, como chaves duplicadas,
presença obrigatória, mínimo de itens e padrão HTML. Ausência opcional só é
tratada como desaparecimento quando uma referência fornecida sustenta isso.
Relatório vazio não gera inferência de remoção de campos da referência.
Não há diff científico nem associação longitudinal.

## Consistência CSV/JSON

`validate_source_pair(payload, csv, contract, source_id)` recebe objeto JSON e
CSV local/tabela lida pelo helper. Preserva BOM no arquivo original e remove-o
apenas na interpretação do cabeçalho; usa UTF-8, `;`, quoting, strings sem trim,
células vazias sem conversão automática para NA e diagnóstico de problemas de
parsing. Não reescreve os arquivos.

A projeção é explícita: null → vazio; boolean → Sim/Não; arrays → concatenação
com `, `, sem split reverso. Campos numéricos declarados são comparados como
números finitos na precisão double, sem arredondamento proposital/tolerância
espacial. Representações como `2`, `2.0` e `2e0` podem coincidir.
Strings fora desses campos não são normalizadas arbitrariamente.

Compara multiconjuntos, mantendo multiplicidade de duplicatas e ignorando ordem.
Contagens iguais não bastam. O sucesso chama-se `consistent_under_projection`
(consistente segundo a projeção), nunca identidade estrutural. Null e string
vazia e algumas concatenações de listas são indistinguíveis no CSV; essa perda
fica explícita. Formas adicionais que não possam ser projetadas geram evidência
insuficiente, não equivalência. Avisos da validação JSON não são apagados.

Resultados não incluem linhas, contatos ou hashes individuais. Os conteúdos
precisam ser comparados em memória, mas só diagnósticos estruturais saem da API.

## Limites e continuidade

Os testes são inteiramente sintéticos em tests/fixtures/phase1. Não existe
transporte a mockar neste módulo: o bloqueio HTTP da Fase 0 fica ativo nos testes
negativos. O CORE existente descobre estes testes e instala os assets sem mudar
workflow. Validação de escala real e revisão de novos contratos permanecem gates
separados; sucesso sintético não certifica disponibilidade das APIs oficiais.

Não foram alterados collect, normalização, validação espacial, prepare, IDs,
distâncias, redes, Shiny, batch, web jobs, targets, snapshots ou .atomic-*.

## Checkpoint 1B — Passo I: infraestrutura operacional local

Base: `248a9cf`, `feat: add source registry and schema contracts`. Somente funções
internas, testes sintéticos e esta documentação foram acrescentados. A proteção
existente tem 790 verificações. Esta entrega não conclui o checkpoint 1B inteiro.

`R/source-http.R` contém somente identidade e canonicalização puras. Não chama
HTTP. `source_request_identity()` recebe source_id, representação, URL fornecida,
registry local e headers. Reutiliza a política de URL e slug do 1A antes do
parsing. Seu descritor v1 contém fonte, representação, URL integral, método de
representação `GET`, Accept e Accept-Encoding. O marcador GET não executa GET.
Query mantém sua ordem original; variação de URL ou negociação muda a identidade.
Headers condicionais, User-Agent, revisões e contexto de execução não entram.

O User-Agent configurado contém `sampamaisagro/0.2`; não existe evidência local
de negociação de representação por esse header. Ele foi excluído do hash para
evitar churn por versão. Headers de negociação adicionais não são aceitos
silenciosamente. Nenhuma configuração do projeto foi alterada.

### Canonical JSON v1

`source_canonical_json()` ordena recursivamente chaves de objetos por radix em
UTF-8 e preserva a ordem dos arrays. NULL vira null; logical vira true/false;
números finitos usam 17 dígitos significativos com ponto decimal explícito.
Integer/double têm a mesma representação numérica; zero negativo vira zero.
Strings preservam codepoints, sem transliteração ou normalização Unicode.
Objetos vazios e arrays vazios são distintos. NA, infinitos, atributos/classes,
raw e chaves duplicadas são rejeitados. Bytes de conteúdo usam hash diretamente,
sem essa serialização. Leitura JSON sem simplificação preserva o round-trip.

### Estado, revisão e eventos

A raiz é `<data_dir>/cache/sources/`, com `locks`, `state` e `content`. Leituras
não criam diretórios. `read_source_state()` valida toda a cadeia e a integridade
do conteúdo validado atual, sem reparar nada. Estado ausente retorna NULL.

As revisões ficam em
`state/<source_id>/<representation>/<identity_sha256>/revisions/000000000001.json`.
Cada registro contém record_schema_version, state_revision, previous_record_sha256,
record_sha256, event e state_after. O checksum usa Canonical JSON v1 sem o próprio
record_sha256; previous_record_sha256 participa. Não existe current.json.
Gap, checksum inválido, JSON corrompido, identidade divergente ou versão
incompatível bloqueiam; não há fallback silencioso para revisão antiga.

`new_source_state()` estabelece campos separados para último check, observação
HTTP, conteúdo validado, candidato, erro e mudança confirmada. Slots HTTP ficam
NULL nesta entrega. `source_state_event()` permite eventos estruturados e IDs/
relógio injetáveis, sem slots para payload, linhas, contatos ou segredos.
Eventos têm tipos e campos permitidos; códigos são identificadores restritos.

`commit_source_event()` exige a revisão atual, valida referências de blobs,
escreve temporário no mesmo diretório, fecha, relê, verifica, confirma destino
ausente, renomeia e relê o final. Revisões anteriores não são sobrescritas.
Hooks internos permitem falha antes/depois da escrita e promoção nos testes.
Temporários interrompidos ficam preservados e nunca são adotados como revisão.

### Locks, cache e promoção

`acquire_source_lock()` usa dir.create como aquisição exclusiva por source_id.
O proprietário contém token, PID, hostname e início UTC. Lock existente, órfão
ou sem metadata válida bloqueia. Só o proprietário verificado libera seu lock;
arquivos inesperados nele impedem remoção. Não há expiração ou limpeza automática.

`store_source_content()` armazena raw exatamente em
`content/<source_id>/<representation>/<sha256>.bin`, com temporário/verificação/
rename. Blob existente íntegro é reutilizado; adulteração bloqueia. Não cria
links, snapshots ou manifests. `verify_source_content()` retorna decisão e código
de diagnóstico para path, existência, arquivo regular, tamanho e SHA-256.

Paths de conteúdo devem coincidir com o caminho derivado da fonte, representação
e hash. Paths absolutos, traversal e symlinks operacionais, inclusive aliases
internos e links pendentes, são rejeitados. A raiz é derivada de configuração
local confiável; caminhos arbitrários do JSON não são adotados.

`source_state_candidate()` só muda latest_candidate. `source_state_promote()`
exige decisão explícita allow/warn; block não promove. A gravação de mudança no
conteúdo validado exige evento content_validated associado ao hash. A existência
de blob órfão não gera promoção. Metadata de validação deve conter somente
evidência estrutural fornecida pelo chamador interno, nunca o payload.

Suporte limitado a filesystem local e escritores que respeitem o lock. Não há
garantia NFS/distribuída, resistência a usuário local malicioso trocando paths
entre syscalls, durabilidade contra perda de energia ou assinatura criptográfica.
Checksums detectam corrupção, não autenticam a origem. Caches/temporários/locks
órfãos não são limpos automaticamente. Liberação do próprio lock é seu ciclo
normal; não é varredura de artefatos históricos.

Não existem transporte real, HEAD/GET executáveis, ETag/Last-Modified condicional,
304, retries, redirects, sampa_check_updates, integração com coleta/proveniência
ou Fase 2. Nenhuma API pública, dependência, registry ou contrato foi alterado.
