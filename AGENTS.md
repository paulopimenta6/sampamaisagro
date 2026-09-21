# Regras de trabalho — SampaMaisAgro

- Preserve as funcionalidades validadas da v0.2: offline, 14 relatórios,
  normalização, validação, distâncias, redes, mapas, Shiny, batch e jobs progressivos.
- Snapshots raw são imutáveis. Preserve grafos reais e evidências históricas.
- Dados reais não entram em fixtures públicas. Use somente dados sintéticos,
  identificados como tais. Dados sensíveis/protegidos não pertencem ao repositório público.
- Nenhuma limpeza de arquivos sem autorização explícita. O nome `.atomic-*`
  não prova que um arquivo pode ser descartado.
- Codex não deve fazer commit, push, criar ou trocar branch, criar tags,
  merge, rebase, `reset --hard`, `git clean` ou force push.
- Mantenha alterações no escopo da fase autorizada. Não inicie a próxima fase.
- Funcionalidades existentes não devem ser removidas silenciosamente.
- Testes de regressão precedem futuras refatorações. Não altere expectativas
  apenas para tornar testes verdes; investigue divergências.
- Cálculos científicos não devem mudar apenas para otimizar desempenho.
  Mudanças metodológicas precisam ser explícitas e justificadas.
- A modalidade científica principal será definida pelo protocolo de pesquisa,
  não pelas decisões de arquitetura ou pelos exemplos dos testes.
- Testes usam diretórios isolados. Não sobrescreva dados ou validações reais.
- Ao final de cada fase, mostre arquivos criados/modificados, `git status --short`,
  `git diff --stat`, testes, resultados e limitações.

Na Fase 0, a única correção funcional autorizada é o denominador de qualidade
do relatório e a preservação do contexto da consulta. Os motores permanecem intactos.
