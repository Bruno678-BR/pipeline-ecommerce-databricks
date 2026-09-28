-- =============================================================================
-- Gold: vendas_produtos
-- Catálogo: projetoaovivo | Schema: gold
-- =============================================================================
--
-- PORQUÊ DAS REGRAS:
--
-- 1. LEFT JOIN de silver.vendas para silver.produtos (e não ao contrário):
--    Começamos pelas vendas porque queremos garantir que TODA receita
--    realizada apareça na tabela — inclusive as 20 vendas de produtos não
--    cadastrados (R$ 4.240,01). Um INNER JOIN ou RIGHT JOIN a partir de
--    produtos excluiria essas vendas e subnotificaria o faturamento.
--
-- 2. COALESCE para "Produto não cadastrado" / "Não cadastrado":
--    Quando o produto não existe em silver.produtos, o LEFT JOIN retorna
--    NULL em nome_produto, categoria, marca e faixa_preco. O COALESCE
--    substitui esses NULLs por textos informativos, tornando a tabela
--    autoexplicativa para o Genie e para o dashboard.
--
-- 3. ranking_receita e ranking_na_categoria com ROW_NUMBER():
--    Dois rankings distintos: um global (qual produto mais vendeu em R$
--    no período) e um por categoria (qual produto lidera dentro de cada
--    segmento). Ambos usam ROW_NUMBER() que retorna INT no Databricks SQL.
--
-- 4. DECIMAL(11,2) em ticket_medio:
--    ROUND(AVG(receita), 2) sobre um DECIMAL(10,2) produz DECIMAL(11,2)
--    por inferência do Spark (precisão expandida para a média). Declaramos
--    o tipo correto para evitar incompatibilidade de schema no pipeline.
--
-- 5. DECIMAL(12,2) em receita:
--    SUM de valores individuais (DECIMAL(10,2)) precisa de margem extra
--    de dígitos ao agregar por produto no período inteiro.
--
-- =============================================================================

CREATE OR REFRESH MATERIALIZED VIEW gold.vendas_produtos
(
  id_produto            STRING        COMMENT 'Identificador do produto (chave). Chave primária desta tabela. Use sempre id_produto para agrupar ou filtrar — produtos diferentes podem ter o mesmo nome.',
  nome_produto          STRING        COMMENT 'Nome do produto. Valor "Produto não cadastrado" indica vendas de um id_produto que não existe em silver.produtos. ⚠️ Produtos diferentes podem ter o mesmo nome: use id_produto para análises precisas, não nome_produto.',
  categoria             STRING        COMMENT 'Categoria do produto (ex.: Eletrônicos, Vestuário). Valor "Não cadastrado" quando o produto não existe em silver.produtos.',
  marca                 STRING        COMMENT 'Marca do produto. Valor "Não cadastrado" quando o produto não existe em silver.produtos.',
  faixa_preco           STRING        COMMENT 'Faixa de preço do produto: PREMIUM (> R$ 1.000), MEDIO (R$ 500 a R$ 1.000) ou BASICO (até R$ 500). Valor "Não cadastrado" quando o produto não existe em silver.produtos.',
  produto_cadastrado    BOOLEAN       COMMENT 'Indica se o produto existe em silver.produtos (true) ou não (false). Produtos não cadastrados ainda geram receita e devem aparecer nos relatórios.',
  total_vendas          BIGINT        COMMENT 'Quantidade de pedidos (transações) que incluíram este produto no período (13/12/2025 a 11/01/2026).',
  itens_vendidos        BIGINT        COMMENT 'Total de unidades deste produto vendidas no período.',
  receita               DECIMAL(12,2) COMMENT 'Receita total em R$ gerada por este produto no período (soma de quantidade × preco_unitario).',
  ticket_medio          DECIMAL(11,2) COMMENT 'Ticket médio em R$ por pedido deste produto: média aritmética da receita de cada venda (ROUND de AVG, precisão 11,2 conforme inferência do Spark).',
  ranking_receita       INT           COMMENT 'Posição do produto no ranking geral por receita decrescente (1 = produto que mais gerou receita no período). Calculado com ROW_NUMBER(), sem empates.',
  ranking_na_categoria  INT           COMMENT 'Posição do produto dentro da sua categoria por receita decrescente (1 = líder da categoria). Permite comparar produtos entre si dentro de um mesmo segmento.'
)
COMMENT 'Tabela da Diretoria Comercial para análise do portfolio de produtos. Use para responder: quais produtos mais vendem, qual a receita por categoria, quais marcas lideram, como os produtos se posicionam por faixa de preço. Inclui TODOS os produtos que geraram receita, inclusive os não cadastrados. Período dos dados: 13/12/2025 a 11/01/2026. Uma linha por id_produto.'
AS
SELECT
  v.id_produto,
  COALESCE(p.nome_produto, 'Produto não cadastrado')  AS nome_produto,
  COALESCE(p.categoria,    'Não cadastrado')           AS categoria,
  COALESCE(p.marca,        'Não cadastrado')           AS marca,
  COALESCE(p.faixa_preco,  'Não cadastrado')           AS faixa_preco,
  MAX(v.produto_cadastrado)                            AS produto_cadastrado,
  COUNT(v.id_venda)                                    AS total_vendas,
  SUM(v.quantidade)                                    AS itens_vendidos,
  CAST(SUM(v.receita) AS DECIMAL(12,2))               AS receita,
  ROUND(AVG(v.receita), 2)                             AS ticket_medio,
  ROW_NUMBER() OVER (
    ORDER BY SUM(v.receita) DESC
  )                                                    AS ranking_receita,
  ROW_NUMBER() OVER (
    PARTITION BY COALESCE(p.categoria, 'Não cadastrado')
    ORDER BY SUM(v.receita) DESC
  )                                                    AS ranking_na_categoria
FROM silver.vendas v
LEFT JOIN silver.produtos p ON v.id_produto = p.id_produto
GROUP BY
  v.id_produto,
  COALESCE(p.nome_produto, 'Produto não cadastrado'),
  COALESCE(p.categoria,    'Não cadastrado'),
  COALESCE(p.marca,        'Não cadastrado'),
  COALESCE(p.faixa_preco,  'Não cadastrado')
