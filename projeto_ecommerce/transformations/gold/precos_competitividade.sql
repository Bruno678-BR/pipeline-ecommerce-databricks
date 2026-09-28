CREATE OR REFRESH MATERIALIZED VIEW gold.precos_competitividade
COMMENT 'Diretoria de Pricing: compara nosso preço com a concorrência (Mercado Livre, Amazon, Magalu, Shopee) para decidir em quais produtos agir. A coluna possui_preco_suspeito apenas sinaliza que o preço do concorrente precisa ser confirmado (pode ser promoção relâmpago) antes de qualquer decisão — o produto continua em todas as contas normalmente.'
AS
WITH concorrentes_agregado AS (
  SELECT
    id_produto,
    ROUND(AVG(preco_concorrente), 2) AS preco_medio_concorrentes,
    MIN(preco_concorrente) AS preco_minimo_concorrentes,
    MAX(preco_concorrente) AS preco_maximo_concorrentes,
    COUNT(*) AS total_concorrentes,
    MAX(preco_suspeito) AS possui_preco_suspeito
  FROM silver.preco_competidores
  GROUP BY id_produto
),
vendas_agregado AS (
  SELECT
    id_produto,
    SUM(receita) AS receita,
    SUM(quantidade) AS itens_vendidos
  FROM silver.vendas
  GROUP BY id_produto
)
SELECT
  p.id_produto,
  p.nome_produto,
  p.categoria,
  p.marca,
  p.preco_atual AS nosso_preco,
  c.preco_medio_concorrentes,
  c.preco_minimo_concorrentes,
  c.preco_maximo_concorrentes,
  c.total_concorrentes,
  ROUND((p.preco_atual - c.preco_medio_concorrentes) / c.preco_medio_concorrentes * 100, 2) AS diferenca_pct_vs_media,
  ROUND((p.preco_atual - c.preco_minimo_concorrentes) / c.preco_minimo_concorrentes * 100, 2) AS diferenca_pct_vs_minimo,
  CASE
    WHEN p.preco_atual > c.preco_maximo_concorrentes THEN 'MAIS_CARO_QUE_TODOS'
    WHEN p.preco_atual < c.preco_minimo_concorrentes THEN 'MAIS_BARATO_QUE_TODOS'
    WHEN p.preco_atual > c.preco_medio_concorrentes THEN 'ACIMA_DA_MEDIA'
    WHEN p.preco_atual < c.preco_medio_concorrentes THEN 'ABAIXO_DA_MEDIA'
    ELSE 'NA_MEDIA'
  END AS classificacao_preco,
  c.possui_preco_suspeito,
  COALESCE(v.receita, 0) AS receita,
  COALESCE(v.itens_vendidos, 0) AS itens_vendidos
FROM silver.produtos p
INNER JOIN concorrentes_agregado c ON p.id_produto = c.id_produto
LEFT JOIN vendas_agregado v ON p.id_produto = v.id_produto;