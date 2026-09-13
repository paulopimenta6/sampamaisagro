# Dicionário de dados

## Equipamentos processados

| Campo | Tipo | Definição |
|---|---|---|
| `equipment_id` | texto | Hash estável do registro sem a data do snapshot. Não é identificador oficial. |
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

Telefones, e-mails e redes sociais podem existir na fonte bruta, mas são deliberadamente excluídos de `equipment.parquet` e de toda saída da aplicação.

## Origens

| Campo | Tipo | Regra |
|---|---|---|
| `query_id` | texto | Obrigatório e único no arquivo. |
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
| `origin_snap_m`, `equipment_snap_m` | número | Distância em linha reta até o vértice de rede usado. |
| `routing_status` | categoria | `not_applicable`, `ok`, `snap_warning`, `snap_excluded` ou `unreachable`. |

As métricas `network_*_fastest` armazenam tanto a distância percorrida no trajeto de menor tempo quanto sua duração. Elas não devem ser confundidas com `network_*_shortest`.
