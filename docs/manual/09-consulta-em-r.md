# 9. Reproduzir uma consulta em R

**Sua tarefa:** gerar uma tabela que outra pessoa consiga obter com as mesmas entradas. Você precisa do ambiente R do [capítulo 8](08-instalacao.md). A primeira parte usa a base sintética incluída para ensino. Um **script** é um arquivo de texto com instruções R, geralmente com extensão `.R`. No RStudio, abra um novo *R Script*, cole os blocos em ordem e envie cada linha ao console com o comando **Run**. `<-` guarda o resultado em um nome. `$` escolhe uma parte do resultado.

## Uma consulta que funciona com dados de ensino

No **R**, com a pasta do projeto como diretório de trabalho:

~~~r
pkgload::load_all(".")
cfg <- read_sampa_config()
base <- demo_equipment()
checagem <- validate_equipment(base, cfg)
checagem$summary
list_equipment_groups(base, cfg)
~~~

`base` contém 12 perfis fictícios com snapshot `demo`. Compare `nrow(base)` com `nrow(checagem$eligible)` para distinguir cadastro e elegibilidade. `checagem$quarantine` guarda os registros excluídos espacialmente. `checagem$issues` traz contagens de problemas. Para reconstruir o resumo por categoria a partir da tabela anotada, use `data_quality_summary(checagem$data)`.

~~~r
entrada <- data.frame(query_id = "consulta-1", latitude = -23.55008,
                      longitude = -46.63408, k = 5L, radius_m = 2000)
origens <- resolve_origins(entrada, cfg)
origens$errors
stopifnot(nrow(origens$valid) == 1L)
resultado <- calculate_proximity(origens$valid, base, config = cfg,
                                 modes = character())
resumo <- proximity_summary(resultado)
resumo[, c("origin_id", "metric_id", "direction", "pares_retidos",
           "pares_distancia_valida", "no_raio", "mediana_m")]
~~~

`modes = character()` pede só geometria. Você deve obter cinco linhas no resumo, uma por métrica, para a mesma origem e o sentido `symmetric`. Os cinco estratos podem selecionar equipamentos diferentes. Para ler um deles, gerar um mapa estático e conferir o denominador:

~~~r
karney <- subset(resultado, metric_id == "geodesic_karney")
karney[order(karney$rank), c("equipment_id", "rank", "distance_m", "within_radius")]
sum(is.finite(karney$distance_m))
mapa <- create_static_map(resultado, "geodesic_karney")
print(mapa)
~~~

A tabela ordenada oferece uma leitura textual do mapa. Para guardar os arquivos, continue na mesma sessão. A saída irá para `outputs/manual-demo`. Use outra pasta para estudos com o cadastro real.

~~~r
pasta <- file.path("outputs", "manual-demo")
dir.create(pasta, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(resultado, file.path(pasta, "pares.csv"))
readr::write_csv(resumo, file.path(pasta, "resumo.csv"))
ggplot2::ggsave(file.path(pasta, "mapa.png"), mapa, width = 7, height = 5)
render_proximity_report(resultado, file.path(pasta, "relatorio.html"),
                        origens$valid, base, cfg)
~~~

O HTML requer R Markdown e Pandoc. Para gerar PDF, use o mesmo comando de relatório trocando a extensão de saída por `.pdf` numa instalação com LaTeX. Se não houver resultados, examine `origens$errors`, o grupo escolhido e a elegibilidade antes de gerar o relatório.

## Conferir a mesma consulta da tela

Em **Explorar**, use as coordenadas, k e raio de `entrada`, todos os tipos, acessibilidade **Todos**, apenas geometria. Espere a conclusão e baixe **Resultados CSV**. No **R**, carregue `base_real <- load_equipment_data(cfg)` e repita `calculate_proximity(origens$valid, base_real, modes = character(), config = cfg)`. Compare com a tela primeiro em `geodesic_karney` e `symmetric`. Confira snapshot, IDs selecionados, `no_raio` e mediana em metros. Use o CSV para comparar valores antes do arredondamento da tabela. Em um relatório que pretende descrever a qualidade de toda a base, passe `base_real` no argumento `equipment`.

Para fazer essa conferência no RStudio, continue com os objetos da sessão e selecione o CSV baixado quando a janela de arquivos abrir:

~~~r
base_real <- load_equipment_data(cfg)
via_r <- calculate_proximity(origens$valid, base_real, config = cfg, modes = character())
via_tela <- readr::read_csv(file.choose(), show_col_types = FALSE)
linha <- function(x) subset(x, origin_id == "consulta-1" &
                              metric_id == "geodesic_karney" & direction == "symmetric")
r <- linha(via_r)
tela <- linha(via_tela)
stopifnot(nrow(r) > 0, nrow(r) == nrow(tela),
          setequal(r$equipment_id, tela$equipment_id))
rbind(via_R = c(no_raio = sum(r$within_radius), mediana_m = median(r$distance_m)),
      via_tela = c(no_raio = sum(tela$within_radius), mediana_m = median(tela$distance_m)))
~~~

Espere duas linhas com os mesmos valores. Se a conferência parar, confira se o CSV veio da consulta individual concluída e se você usou o cadastro real em ambas as consultas. Uma troca por `demo_equipment()` em apenas uma delas já basta para mudar os equipamentos.

**Para repetir um filtro de grupo.** A tela usa **grupos derivados**. O argumento `categories` de `calculate_proximity()` filtra a coluna de categoria da fonte. Para reproduzir, por exemplo, o grupo de hortas da tela, use a base processada com `groups`. Divida essa coluna no separador literal e procure o identificador completo:

~~~r
base_real <- load_equipment_data(cfg)
hortas <- vapply(strsplit(base_real$groups, "|", fixed = TRUE),
                 function(ids) "hortas" %in% ids, logical(1))
resultado_hortas <- calculate_proximity(origens$valid, base_real[hortas, ],
                                        modes = character(), config = cfg)
~~~

**Exercício.** Uma pessoa encontra cinco linhas no resumo e diz que a amostra tem cinco origens. Como conferir? **Gabarito:** examine `unique(resumo$origin_id)` e `unique(resumo$metric_id)`. Neste exercício há uma origem e cinco definições de distância. O tamanho observacional de cada resumo é `pares_distancia_valida` na sua própria linha.

[Índice do manual](README.md) · [Capítulo anterior](08-instalacao.md) · [Próximo capítulo](10-comparar-metricas.md)
