# Dicionário de dados

## Equipamentos processados

| Campo | Tipo | Definição |
|---|---|---|
| `equipment_id` | texto | Hash do conteúdo da fonte, sem a data do snapshot; muda se o conteúdo muda. Não é identificador oficial nem permanente do estabelecimento. |
| `record_version_id` | texto | Hash da versão do registro, incluindo o snapshot. |
| `equipment_name` | texto | Nome público no cadastro. |
| `category`, `subcategory` | texto | Classificações declaradas pela fonte. |
| `source_name`, `source_database` | texto | Proveniência declarada. |
| `address`, `neighborhood`, `district`, `zone`, `postal_code` | texto | Componentes públicos de localização. |
| `latitude`, `longitude` | número | WGS 84, graus decimais. |
| `coordinate_origin` | texto | `source`, `synthetic` ou outra origem documentada. |
| `coordinate_status` | categoria | `valid_source_coordinate`, `missing_coordinate`, `incomplete_coordinate`, `invalid_coordinate`, `outside_study_area` ou `derived_geocode`. |
| `quality_flags` | texto | Alertas separados por `|`. |
| `snapshot_date` | data/texto | Identificador temporal do snapshot. |
| `source_key` | texto | Chave auxiliar de conciliação dos relatórios temáticos por nome, categoria, fonte e endereço; não distingue instalações físicas com segurança. |
| `source_reports` | texto | Relatórios em que o perfil foi conciliado. |
| `groups` | texto | Rótulos analíticos separados por barra vertical; podem se sobrepor. |
| `primary_group` | texto | Primeiro grupo pela prioridade explícita de R/catalog.R; usado na cor do mapa. |
| `accessibility_reported` | texto | Resposta original da fonte para facilidades a pessoas com necessidades especiais. |
| `accessibility` | texto | Informada: sim / Informada: não / Não informada; não é uma avaliação de rota acessível. |
| `within_municipality` | lógico | Interseção com a malha simplificada IBGE, quando disponível; calculada na validação espacial. |

Telefones, e-mails e redes sociais podem existir na fonte bruta, mas são deliberadamente excluídos de `equipment.parquet` e de toda saída da aplicação.

## Origens

| Campo | Tipo | Regra |
|---|---|---|
| `query_id` | texto | Único no arquivo; gerado sequencialmente se a coluna estiver ausente. Valores vazios em coluna fornecida são erros. |
| `cep` | texto | Oito dígitos; mutuamente exclusivo com coordenadas. |
| `latitude`, `longitude` | número | Devem ser informadas juntas; WGS 84. |
| `k` | inteiro | 1–1000. |
| `radius_m` | número | Maior que zero e até 100.000 m. |
| `origin_method` | categoria | `cep` ou `coordinates`. |
| `origin_quality_flag` | categoria | `approximate_cep` ou `provided_coordinates`. |

## Resultado longo

| Campo | Tipo | Definição |
|---|---|---|
| `origin_id` | texto | `query_id` da origem. |
| `equipment_id` | texto | Chave do equipamento. |
| `metric_id` | categoria | Identificador computável da métrica. |
| `distance_family` | categoria | `geometric` ou `network`. |
| `mode` | categoria | `foot`, `bicycle`, `motorcar` ou ausente. |
| `path_objective` | categoria | `shortest`, `fastest` ou ausente. |
| `direction` | categoria | `symmetric`, `origin_to_equipment` ou `equipment_to_origin`. |
| `distance_m` | número | Distância total em metros. Inclui conectores de snapping na rede. |
| `duration_min` | número | Tempo em minutos para o caminho mais rápido. |
| `rank` | inteiro | Ordem entre pares alcançáveis da mesma origem/métrica/sentido. |
| `within_radius` | lógico | Distância menor ou igual ao raio solicitado. |
| `selection_k`, `selection_radius_m` | número | Parâmetros efetivamente usados para aquela origem. |
| `origin_snap_m`, `equipment_snap_m` | número | Distância em linha reta até o vértice de rede usado. |
| `routing_status` | categoria | `not_applicable`, `ok`, `snap_warning`, `snap_excluded` ou `unreachable`. |

As métricas `network_*_fastest` armazenam tanto a distância percorrida no trajeto de menor tempo quanto sua duração. Elas não devem ser confundidas com `network_*_shortest`.

O ranking fastest usa minutos; os demais usam metros. A seleção é raio OU top-k.
O atributo R routing_diagnostics contabiliza status antes da seleção; o script de
validação real o exporta separadamente. CEPs resolvidos mantêm origin_cep,
origin_longitude, origin_latitude, geocode_source, geocoded_at e a indicação de
aproximação. Esse estado interno pode conter CEP e coordenadas legitimamente;
a entrada bruta deve usar apenas um método por linha.
