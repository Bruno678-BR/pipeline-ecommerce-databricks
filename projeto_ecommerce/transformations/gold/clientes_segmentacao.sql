-- =============================================================================
-- Gold: clientes_segmentacao
-- Catálogo: projetoaovivo | Schema: gold
-- =============================================================================
--
-- PORQUÊ DAS REGRAS:
--
-- 1. LEFT JOIN a partir de silver.clientes (não de silver.vendas):
--    A diretoria de CS quer ver TODOS os clientes, inclusive quem nunca comprou.
--    Esses clientes aparecem com receita = 0 e são justamente os que o time
--    precisa ativar. Se usássemos INNER JOIN, eles sumiriam do relatório.
--
-- 2. COALESCE(SUM(v.receita), 0) → receita nunca é NULL:
--    Para clientes sem compra, SUM retorna NULL. Forçamos zero para que
--    agregações no dashboard e no Genie funcionem sem tratar nulos.
--
-- 3. Por que os limites antigos (R$ 10.000 / R$ 5.000) não servem:
--    Com R$ 10.000 como piso de VIP e R$ 5.000 como piso de TOP_TIER,
--    praticamente toda a base ativa viraria VIP ou TOP_TIER, esvaziando
--    o sentido do segmento premium. A diretora revisou a distribuição
--    real (período 13/12/2025–11/01/2026) e definiu novos limiares
--    calibrados para que VIP seja realmente o top ~20% da carteira:
--      VIP      >= R$ 22.000  → clientes de altíssimo valor
--      TOP_TIER >= R$ 17.000  → clientes de alto valor
--      REGULAR  < R$ 17.000  → demais clientes (incluindo inativos)
--
-- 4. Todas as vendas entram na receita (inclusive produto não cadastrado):
--    A silver.vendas já marca produto_cadastrado = false nesses casos, mas
--    a receita foi realizada. Excluir essas vendas subnotificaria o faturamento.
--
-- 5. ROW_NUMBER() por receita DESC:
--    Gera o ranking de melhores clientes sem empates (garante ordem total),
--    permitindo que o Genie responda "quem é o 1º, 2º, 3º cliente?" sem ambiguidade.
--
-- =============================================================================

CREATE OR REFRESH MATERIALIZED VIEW gold.clientes_segmentacao
(
  id_cliente       STRING        COMMENT 'Identificador único do cliente. Chave primária desta tabela.',
  nome_cliente     STRING        COMMENT 'Nome do cliente sem pronome de tratamento (Sr., Sra., Dr. etc. já removidos na camada Silver).',
  estado           STRING        COMMENT 'Sigla da Unidade Federativa do cliente (ex.: SP, MG, RJ). Dois caracteres maiúsculos.',
  nome_estado      STRING        COMMENT 'Nome completo do estado (ex.: São Paulo, Minas Gerais). Fonte: mapeamento IBGE das 27 UFs.',
  regiao           STRING        COMMENT 'Região geográfica do IBGE: Norte, Nordeste, Centro-Oeste, Sudeste ou Sul.',
  total_compras    BIGINT        COMMENT 'Quantidade de pedidos realizados pelo cliente no período (13/12/2025 a 11/01/2026). Zero para clientes que nunca compraram.',
  receita          DECIMAL(10,2) COMMENT 'Receita total em R$ gerada pelo cliente no período (quantidade x preco_unitario). Inclui vendas de produto não cadastrado. Zero para clientes sem compras — nunca nulo.',
  ticket_medio     DECIMAL(11,2) COMMENT 'Ticket médio em R$ por pedido: média aritmética da receita de cada venda (ROUND de AVG, precisão 11,2 conforme inferência do Spark). NULL para clientes sem compras (não existe ticket sem venda).',
  primeira_compra  DATE          COMMENT 'Data da compra mais antiga do cliente no período. NULL para clientes sem compras.',
  ultima_compra    DATE          COMMENT 'Data da compra mais recente do cliente no período. NULL para clientes sem compras.',
  segmento_cliente STRING        COMMENT 'Segmento de valor do cliente: VIP (receita >= R$ 22.000), TOP_TIER (R$ 17.000 a R$ 21.999,99) ou REGULAR (abaixo de R$ 17.000, inclusive inativos com receita zero). Limites calibrados com a diretoria sobre a distribuição real do período.',
  ranking_receita  INT           COMMENT 'Posição do cliente no ranking geral por receita decrescente (1 = maior cliente). Sem empates: em caso de receita igual, a ordem é arbitrária mas estável. Use para responder qual é o N-ésimo melhor cliente.'
)
COMMENT 'Tabela da Diretoria de Customer Success. Use para identificar os melhores clientes, analisar distribuição geográfica (estado, região) e segmentar a carteira em VIP / TOP_TIER / REGULAR. Inclui TODOS os clientes cadastrados, mesmo os que nunca compraram (receita = 0) — esses são os alvos prioritários de ativação pelo time de CS. Período dos dados: 13/12/2025 a 11/01/2026.'
AS
SELECT
  c.id_cliente,
  c.nome_cliente,
  c.estado,
  c.nome_estado,
  c.regiao,
  COUNT(v.id_venda)                                                          AS total_compras,
  COALESCE(CAST(SUM(v.receita) AS DECIMAL(10,2)), CAST(0 AS DECIMAL(10,2))) AS receita,
  ROUND(AVG(v.receita), 2)                                                   AS ticket_medio,
  MIN(v.data)                                                                AS primeira_compra,
  MAX(v.data)                                                                AS ultima_compra,
  CASE
    WHEN COALESCE(SUM(v.receita), 0) >= 22000 THEN 'VIP'
    WHEN COALESCE(SUM(v.receita), 0) >= 17000 THEN 'TOP_TIER'
    ELSE 'REGULAR'
  END                                                                        AS segmento_cliente,
  ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(v.receita), 0) DESC)             AS ranking_receita
FROM silver.clientes  c
LEFT JOIN silver.vendas v ON c.id_cliente = v.id_cliente
GROUP BY
  c.id_cliente,
  c.nome_cliente,
  c.estado,
  c.nome_estado,
  c.regiao
