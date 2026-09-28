-- =============================================================================
-- Gold: vendas_detalhadas
-- Catálogo: projetoaovivo | Schema: gold
-- =============================================================================
--
-- PORQUÊ DAS REGRAS:
--
-- 1. Uma linha por venda (mesma granularidade de silver.vendas):
--    Esta tabela é o ponto central de cruzamento entre diretorias. Perguntas
--    como "receita por região e categoria" ou "canal preferido dos VIPs"
--    exigem combinar atributos de produto, cliente e venda na mesma linha.
--    Manter a granularidade da venda preserva a capacidade de agregar em
--    qualquer dimensão sem risco de duplicação.
--
-- 2. LEFT JOIN silver.produtos:
--    Garante que as 20 vendas de produto não cadastrado (R$ 4.240,01)
--    permaneçam na tabela, com nome_produto = 'Produto não cadastrado'.
--    Um INNER JOIN excluiria essas vendas e subnotificaria a receita.
--
-- 3. LEFT JOIN gold.clientes_segmentacao:
--    O segmento_cliente (VIP / TOP_TIER / REGULAR) só existe na camada gold.
--    Usamos LEFT JOIN por segurança — se por algum motivo um id_cliente de
--    silver.vendas não estiver em gold.clientes_segmentacao, a venda ainda
--    aparece (com segmento NULL) em vez de ser descartada.
--    Na prática, todos os 50 clientes estão mapeados.
--
-- 4. CLUSTER BY (data):
--    Otimiza a performance de filtros por data no dashboard e no Genie.
--    Como o período tem ~30 dias, a maioria das consultas filtra por data
--    ou intervalo de datas. O CLUSTER BY organiza os dados fisicamente por
--    data, reduzindo a quantidade de dados lidos em cada consulta filtrada.
--
-- =============================================================================

CREATE OR REFRESH MATERIALIZED VIEW gold.vendas_detalhadas
(
  id_venda                STRING        COMMENT 'Identificador único da venda. Chave primária desta tabela (um registro por transação).',
  data_venda              TIMESTAMP     COMMENT 'Data e hora exatas da venda (timestamp completo). Use para análises que exigem precisão de horário.',
  data                    DATE          COMMENT 'Data da venda (sem horário). Período dos dados: 13/12/2025 a 11/01/2026. Use para filtros e agrupamentos diários.',
  dia_semana              STRING        COMMENT 'Nome do dia da semana em português (ex.: Segunda, Terça, Sábado). Use em conjunto com dia_semana_num para ordenação correta.',
  dia_semana_num          INT           COMMENT 'Número do dia da semana: 1 = Domingo, 2 = Segunda, ..., 7 = Sábado (padrão Spark). Use para ordenar dia_semana cronologicamente.',
  hora                    INT           COMMENT 'Hora do dia em que a venda ocorreu (0–23, formato 24h).',
  canal_venda             STRING        COMMENT 'Canal de venda: ecommerce ou loja_fisica.',
  id_produto              STRING        COMMENT 'Identificador do produto vendido. Para produtos não cadastrados em silver.produtos, o id ainda é registrado (a venda existiu).',
  nome_produto            STRING        COMMENT 'Nome do produto. Valor "Produto não cadastrado" quando o id_produto não existe em silver.produtos.',
  categoria               STRING        COMMENT 'Categoria do produto. Valor "Não cadastrado" quando o produto não existe em silver.produtos.',
  marca                   STRING        COMMENT 'Marca do produto. Valor "Não cadastrado" quando o produto não existe em silver.produtos.',
  faixa_preco             STRING        COMMENT 'Faixa de preço: PREMIUM (> R$ 1.000), MEDIO (R$ 500–1.000) ou BASICO (até R$ 500). Valor "Não cadastrado" quando o produto não existe em silver.produtos.',
  id_cliente              STRING        COMMENT 'Identificador do cliente que realizou a compra.',
  nome_cliente            STRING        COMMENT 'Nome do cliente sem pronome de tratamento (já tratado em silver.clientes).',
  estado                  STRING        COMMENT 'Sigla da UF do cliente (ex.: SP, MG, RJ).',
  regiao                  STRING        COMMENT 'Região geográfica do IBGE do cliente: Norte, Nordeste, Centro-Oeste, Sudeste ou Sul.',
  segmento_cliente        STRING        COMMENT 'Segmento de valor do cliente: VIP (receita total >= R$ 22.000), TOP_TIER (R$ 17.000–21.999,99) ou REGULAR (abaixo de R$ 17.000). Proveniente de gold.clientes_segmentacao — calculado sobre o período completo, não apenas nesta venda.',
  quantidade              BIGINT        COMMENT 'Quantidade de unidades do produto compradas nesta venda.',
  preco_unitario          DECIMAL(10,2) COMMENT 'Preço unitário do produto no momento da venda em R$.',
  receita                 DECIMAL(10,2) COMMENT 'Receita gerada por esta venda em R$ (quantidade × preco_unitario).',
  produto_cadastrado      BOOLEAN       COMMENT 'Indica se o produto desta venda existe em silver.produtos (true) ou não (false). Vendas com false ainda compõem a receita total.',
  venda_antes_do_cadastro BOOLEAN       COMMENT 'Indica se a venda ocorreu antes da data de cadastro do produto (true = venda anterior ao cadastro). Relevante para auditoria de catálogo.'
)
COMMENT 'Tabela da Diretoria Comercial para análises cruzadas entre diretorias e filtros do dashboard. Use para responder perguntas que combinam múltiplas dimensões: "receita por região e categoria", "canal preferido dos clientes VIP", "produtos mais vendidos no Nordeste". Contém UMA LINHA POR VENDA (mesma granularidade de silver.vendas). CLUSTER BY (data) para performance em filtros de datas. Período dos dados: 13/12/2025 a 11/01/2026.'
CLUSTER BY (data)
AS
SELECT
  v.id_venda,
  v.data_venda,
  v.data,
  v.dia_semana,
  v.dia_semana_num,
  v.hora,
  v.canal_venda,
  v.id_produto,
  COALESCE(p.nome_produto, 'Produto não cadastrado')  AS nome_produto,
  COALESCE(p.categoria,    'Não cadastrado')           AS categoria,
  COALESCE(p.marca,        'Não cadastrado')           AS marca,
  COALESCE(p.faixa_preco,  'Não cadastrado')           AS faixa_preco,
  v.id_cliente,
  cs.nome_cliente,
  cs.estado,
  cs.regiao,
  cs.segmento_cliente,
  v.quantidade,
  v.preco_unitario,
  v.receita,
  v.produto_cadastrado,
  v.venda_antes_do_cadastro
FROM silver.vendas v
LEFT JOIN silver.produtos             p  ON v.id_produto = p.id_produto
LEFT JOIN gold.clientes_segmentacao   cs ON v.id_cliente = cs.id_cliente
