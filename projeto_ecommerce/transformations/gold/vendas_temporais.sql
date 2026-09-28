-- =============================================================================
-- Gold: vendas_temporais
-- Catálogo: projetoaovivo | Schema: gold
-- =============================================================================
--
-- PORQUÊ DAS REGRAS:
--
-- 1. Granularidade data × hora × canal_venda:
--    A Diretoria Comercial quer entender padrões de comportamento de compra:
--    quais horas do dia têm mais vendas, quais dias da semana performam melhor
--    e como isso se distribui entre ecommerce e loja física. A combinação
--    dessas três dimensões permite todas essas análises sem joins adicionais.
--
-- 2. DECIMAL(12,2) em receita:
--    SUM de receitas individuais (DECIMAL(10,2)) pode ultrapassar 10 dígitos
--    quando somadas por grupo. Usamos DECIMAL(12,2) para ter margem segura
--    sem perder precisão centesimal.
--
-- 3. clientes_unicos = COUNT(DISTINCT id_cliente):
--    Métrica de alcance por fatia temporal/canal. ATENÇÃO: não somar entre
--    linhas desta tabela — um mesmo cliente aparece em múltiplas combinações.
--    Para o total de clientes únicos no período, usar gold.clientes_segmentacao.
--
-- =============================================================================

CREATE OR REFRESH MATERIALIZED VIEW gold.vendas_temporais
(
  data             DATE          COMMENT 'Data da venda (sem horário). Período dos dados: 13/12/2025 a 11/01/2026.',
  dia_semana       STRING        COMMENT 'Nome do dia da semana em português (ex.: Segunda, Terça, Sábado). Use em conjunto com dia_semana_num para ordenação correta.',
  dia_semana_num   INT           COMMENT 'Número do dia da semana: 1 = Domingo, 2 = Segunda, ..., 7 = Sábado (padrão Spark/IBGE). Use para ordenar dia_semana cronologicamente.',
  hora             INT           COMMENT 'Hora do dia em que as vendas ocorreram (0–23, formato 24h).',
  canal_venda      STRING        COMMENT 'Canal de venda: ecommerce ou loja_fisica.',
  total_vendas     BIGINT        COMMENT 'Quantidade de pedidos (transações) realizados nesta combinação de data, hora e canal.',
  itens_vendidos   BIGINT        COMMENT 'Total de itens (unidades) vendidos nesta combinação de data, hora e canal.',
  receita          DECIMAL(12,2) COMMENT 'Receita total em R$ nesta combinação de data, hora e canal (soma de quantidade × preco_unitario de todas as vendas do grupo). Inclui vendas de produto não cadastrado.',
  clientes_unicos  BIGINT        COMMENT 'Número de clientes distintos que compraram nesta combinação de data, hora e canal. ⚠️ NÃO some entre linhas: um mesmo cliente pode aparecer em múltiplas datas, horas ou canais e seria contado em duplicidade. Para total de clientes únicos no período, use gold.clientes_segmentacao.'
)
COMMENT 'Tabela da Diretoria Comercial para análise temporal de vendas. Use para responder: quais horas do dia vendem mais, quais dias da semana são mais fortes, como o ecommerce e a loja física se comparam ao longo do tempo. Período dos dados: 13/12/2025 a 11/01/2026. Uma linha por combinação de (data, hora, canal_venda).'
AS
SELECT
  data,
  dia_semana,
  dia_semana_num,
  hora,
  canal_venda,
  COUNT(id_venda)              AS total_vendas,
  SUM(quantidade)              AS itens_vendidos,
  CAST(SUM(receita) AS DECIMAL(12,2)) AS receita,
  COUNT(DISTINCT id_cliente)   AS clientes_unicos
FROM silver.vendas
GROUP BY
  data,
  dia_semana,
  dia_semana_num,
  hora,
  canal_venda
