# Fixtures públicas sintéticas — v0.2

Todos os conteúdos foram inventados para testes. Nenhum perfil, contato,
endereço ou coordenada foi extraído do Sampa+Rural. CEAGESP aparece somente
como token da regra de classificação existente, não como registro real.
O CEP `00000042` é um identificador de teste, sem consulta a serviços.

## Inventário e contratos

- Base completa: oito ocorrências, sete conteúdos distintos, três elegíveis.
  Há duplicata exata, dois perfis semelhantes, coordenadas ausentes,
  incompletas, inválidas e fora do retângulo, e classificação sobreposta.
- Temático: coordenadas estruturalmente ausentes e certificados multivalorados;
  não pode apagar a localização da base completa ou duplicar o perfil.
- Vazio: `partners: []`. Alterado: mudança apenas no contato fictício.
- Qualidade: posições 1, 2, 3 e 6 da base deduplicada; total 4, válidos 2, 50%.
- Origens: coordenada e CEP válidos, CEP ausente e latitude inválida.
- Rede: 8 vértices, 10 arestas direcionadas; `d` em metros e `time` em segundos.
  Coordenadas servem ao snapping; custos explícitos são oráculos sintéticos,
  não comprimentos aferidos de vias nem velocidades científicas recomendadas.

Oráculos A→D: shortest 200 m; fastest 300 m / 20 s. D→A: 350 m / 70 s.
A→U é inalcançável. B é mais perto por distância, D é mais perto por tempo.
Mesmos custos podem exercitar todos os modos sem declarar modalidade principal.
Política modal de construção é testada separadamente pelos testes existentes.

## Uso e aprovação

`load.R` só materializa dados nos caminhos temporários passados explicitamente.
Não use os diretórios reais `data/` ou `outputs/` como destino de fixtures.
`expected/` contém projeções revisadas; testes apenas as leem.

Para gerar uma proposta, na raiz do repositório:

```sh
R_PROFILE_USER=/dev/null Rscript scripts/capture_v02_baseline.R /tmp/v02-candidate-NOVO
```

O destino deve ser novo e externo às fixtures. A captura não aprova nem
substitui expectativas. Compare oráculos, invariantes e diferenças antes de
uma atualização explícita. Timestamps, caminhos, IDs de jobs e bytes de formatos
binários não são contratos. Tolerância numérica inicial: `1e-8`.

O baseline fixa `LC_COLLATE=C`: a v0.2 ordena nomes dos campos antes do hash,
e IDs de payloads com nomes acentuados dependem do locale. Isso foi confirmado
em C e C.UTF-8 antes da correção do relatório; o normalizador não foi alterado.
