# 8. Preparar uma máquina e trabalhar offline

**Sua tarefa:** abrir o aplicativo em uma máquina preparada e identificar qual fotografia dos dados está sendo usada. Reserve internet para a instalação e preparação inicial. O arquivo `renv.lock` registra as versões dos pacotes R. Os dados e grafos ocupam espaço separado do código. Consulte as condições e os recursos da máquina usada na [validação histórica](../VALIDACAO_REAL.md) como referência para dimensionar o trabalho.

## Primeira instalação

1. Disponha de R 4.3 ou superior, RStudio se desejar a interface gráfica e uma cópia completa do projeto. A **raiz do projeto** é a pasta com `DESCRIPTION`, `app.R`, `config.yml` e `renv.lock`. Abra `sampamaisrural.Rproj`. No **console do R**, execute uma linha de cada vez:

~~~r
getwd()
file.exists("DESCRIPTION", "renv.lock", "scripts/prepare_offline.R")
renv::restore()
~~~

Os três valores de `file.exists` devem ser `TRUE` antes de restaurar. Se a sessão pedir para instalar ou inicializar `renv`, faça isso nessa máquina com internet. Se um pacote geográfico não instalar, leia o primeiro erro. Bibliotecas do sistema como GDAL, GEOS e PROJ podem precisar de instalação pela pessoa responsável pela máquina.

2. Abra o **terminal** nessa mesma pasta. O terminal entende o comando `Rscript`. O console do R entende expressões como `getwd()`. No terminal, rode:

~~~bash
Rscript scripts/prepare_offline.R
~~~

O script prepara a base quando ela falta, tenta preparar os CEPs de exemplo e prepara mapas e redes quando falta o manifesto de rede. Guarde as mensagens e confira os arquivos ao final. Se houve uma interrupção, verifique qual componente falta antes de repetir uma preparação longa.

3. Abra `app.R` e selecione **Run App** no RStudio. Outra opção, no **console do R** da raiz:

~~~r
pkgload::load_all(".")
run_app()
~~~

4. Em **Banco offline**, confira o inventário, os CEPs disponíveis, os modos de rede e a identificação da base em **Explorar**. Sem precisar de conexão externa para a consulta, repita uma busca por coordenadas e outra por um CEP preparado. Registre o snapshot e a situação de ambas. Para um novo CEP ainda ausente, siga a linha correspondente abaixo.

## O que preparar ou atualizar

Execute os comandos no **terminal**, na raiz. Para uma alteração da base em uso, encerre primeiro a aplicação e preserve a identificação da cópia anterior. Use caminhos relativos à sua máquina.

| Necessidade | Comando | Como conferir |
|---|---|---|
| Incluir um novo CEP com internet | `Rscript scripts/prepare_ceps.R 01311000` | Conferir a resposta e sua situação. Reabrir o aplicativo e procurar o código na lista de CEPs. |
| Buscar uma nova publicação do cadastro | `Rscript scripts/update_data.R` | Conferir a nova pasta em `data/raw` e o processamento. Reiniciar o R que serve a aplicação e conferir o snapshot. |
| Reprocessar uma coleta que já existe, offline | `Rscript scripts/update_data.R data/raw/ID_DO_SNAPSHOT` | Substituir `ID_DO_SNAPSHOT` por uma pasta real do inventário. Conferir `data/processed`. |
| Preparar mapas e redes a partir dos insumos locais existentes | `Rscript scripts/prepare_network.R --offline` | Conferir os arquivos `network_*.rds` e os modos oferecidos após reiniciar. Insumos ausentes exigem preparação prévia. |
| Reconstruir só a rede de bicicleta a partir do cache já processado | `Rscript scripts/rebuild_graphs.R bicycle` | Exige `processed/osm_lines.rds` e o manifesto de rede dentro da pasta de dados. Conferir o modo no aplicativo. |

**Onde estão os dados?** Por padrão, `data/raw` contém fontes e manifestos por snapshot. `data/processed` contém a base consolidada, o inventário e os grafos. `data/cache/cep` guarda pontos e respostas de CEP. `data/osm` contém vias e limite cartográfico. Os caminhos podem ser configurados em `config.yml`. Copiar o repositório sozinho deixa esses dados para trás. Para transportar uma instalação offline, copie a pasta de dados por meio autorizado, confira o inventário e garanta que o ambiente R de destino tem as dependências.

**Exercício.** Os CEPs conhecidos funcionam, uma busca por coordenadas funciona, mas o modo bicicleta não aparece. O que preparar? **Gabarito:** verifique em **Banco offline** o modo instalado e a presença do grafo de bicicleta. Cuide dos insumos de rede e reinicie a aplicação. Atualizar o cadastro de equipamentos ou editar um CSV não instala esse grafo. [Acesso remoto, Docker e fila](operacao.md)

[Índice do manual](README.md) · [Capítulo anterior](07-lotes.md) · [Próximo capítulo](09-consulta-em-r.md)
