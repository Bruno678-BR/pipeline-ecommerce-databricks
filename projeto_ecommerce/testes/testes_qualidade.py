# Databricks notebook source
# MAGIC %md
# MAGIC # Testes de Qualidade de Dados · Camada Silver
# MAGIC
# MAGIC Validações de integridade, unicidade de chaves primárias e regras de negócio para a camada Silver.
# MAGIC Cada teste é uma consulta que conta **linhas com problema** (zero é o resultado esperado).
# MAGIC Se qualquer teste falhar, o notebook exibe a tabela de resultados e lança um `AssertionError`.

# COMMAND ----------

dbutils.widgets.text("catalogo", "projeto_ao_vivo")
catalogo = dbutils.widgets.get("catalogo")
spark.sql(f"USE CATALOG {catalogo}")

# COMMAND ----------

TESTES = {
    # 1. Unicidade das 4 tabelas silver
    "silver.produtos: id_produto único":
        "SELECT id_produto FROM silver.produtos GROUP BY id_produto HAVING COUNT(*) > 1",
    "silver.clientes: id_cliente único":
        "SELECT id_cliente FROM silver.clientes GROUP BY id_cliente HAVING COUNT(*) > 1",
    "silver.preco_competidores: (id_produto, nome_concorrente) único":
        "SELECT id_produto, nome_concorrente FROM silver.preco_competidores GROUP BY id_produto, nome_concorrente HAVING COUNT(*) > 1",
    "silver.vendas: id_venda único":
        "SELECT id_venda FROM silver.vendas GROUP BY id_venda HAVING COUNT(*) > 1",

    # 2. Integridade matemática da receita
    "silver.vendas: receita = quantidade × preco_unitario":
        "SELECT id_venda FROM silver.vendas WHERE receita <> CAST(quantidade * preco_unitario AS DECIMAL(10,2))",

    # 3. Limite tolerado: vendas de produtos não cadastrados abaixo de 1% do total
    "silver.vendas: vendas de produto não cadastrado abaixo de 1% do total":
        "SELECT 1 FROM silver.vendas HAVING AVG(CASE WHEN produto_cadastrado THEN 0.0 ELSE 1.0 END) >= 0.01",

    # 4. Integridade de regras críticas (fail expectations)
    "silver.produtos: id_produto preenchido e preco_atual positivo":
        "SELECT id_produto FROM silver.produtos WHERE id_produto IS NULL OR preco_atual <= 0",
    "silver.clientes: id_cliente e regiao preenchidos":
        "SELECT id_cliente FROM silver.clientes WHERE id_cliente IS NULL OR regiao IS NULL",
    "silver.preco_competidores: id_produto preenchido e preco positivo":
        "SELECT id_produto FROM silver.preco_competidores WHERE id_produto IS NULL OR preco_concorrente <= 0",
    "silver.vendas: campos obrigatórios preenchidos e domínio válido":
        "SELECT id_venda FROM silver.vendas WHERE id_venda IS NULL OR data_venda IS NULL OR id_cliente IS NULL OR id_produto IS NULL OR quantidade <= 0 OR preco_unitario <= 0 OR canal_venda NOT IN ('ecommerce', 'loja_fisica')",

    # -------------------------------------------------------------------------
    # 5. Gold: clientes_segmentacao
    # -------------------------------------------------------------------------

    # 5.1 Receita total da gold deve ser igual à receita total de silver.vendas
    #     (garante que o LEFT JOIN não inflou nem perdeu receita)
    "gold.clientes_segmentacao: receita total igual à silver.vendas": """
        SELECT 1
        FROM (
            SELECT COALESCE(SUM(receita), 0) AS receita_gold FROM gold.clientes_segmentacao
        ) g,
        (
            SELECT COALESCE(SUM(receita), 0) AS receita_silver FROM silver.vendas
        ) s
        WHERE ROUND(g.receita_gold, 2) <> ROUND(s.receita_silver, 2)
    """,

    # 5.2 id_cliente único — uma linha por cliente
    "gold.clientes_segmentacao: id_cliente único":
        "SELECT id_cliente FROM gold.clientes_segmentacao GROUP BY id_cliente HAVING COUNT(*) > 1",

    # 5.3 Segmento só pode ser VIP, TOP_TIER ou REGULAR
    "gold.clientes_segmentacao: segmento apenas VIP, TOP_TIER ou REGULAR":
        "SELECT id_cliente, segmento_cliente FROM gold.clientes_segmentacao WHERE segmento_cliente NOT IN ('VIP', 'TOP_TIER', 'REGULAR')",

    # 5.4 Nenhum cliente VIP pode ter receita abaixo de R$ 22.000
    "gold.clientes_segmentacao: nenhum VIP com receita abaixo de R$ 22.000":
        "SELECT id_cliente, receita FROM gold.clientes_segmentacao WHERE segmento_cliente = 'VIP' AND receita < 22000",

    # 5.5 Toda coluna do schema gold deve ter comentário no Unity Catalog
    #     (ignora tabelas internas __materialization* geradas pelo pipeline)
    "gold: todas as colunas com COMMENT no Unity Catalog": """
        SELECT table_name, column_name
        FROM system.information_schema.columns
        WHERE table_catalog = 'projetoaovivo'
          AND table_schema  = 'gold'
          AND table_name NOT LIKE '__materialization%'
          AND (comment IS NULL OR TRIM(comment) = '')
    """,

    # -------------------------------------------------------------------------
    # 6. Gold: Diretoria Comercial (vendas_temporais, vendas_produtos, vendas_detalhadas)
    # -------------------------------------------------------------------------

    # 6.1 Receita total de vendas_temporais deve ser igual à de silver.vendas
    "gold.vendas_temporais: receita total igual à silver.vendas": """
        SELECT 1
        FROM (
            SELECT COALESCE(SUM(receita), 0) AS receita_gold FROM gold.vendas_temporais
        ) g,
        (
            SELECT COALESCE(SUM(receita), 0) AS receita_silver FROM silver.vendas
        ) s
        WHERE ROUND(g.receita_gold, 2) <> ROUND(s.receita_silver, 2)
    """,

    # 6.2 Receita total de vendas_produtos deve ser igual à de silver.vendas
    "gold.vendas_produtos: receita total igual à silver.vendas": """
        SELECT 1
        FROM (
            SELECT COALESCE(SUM(receita), 0) AS receita_gold FROM gold.vendas_produtos
        ) g,
        (
            SELECT COALESCE(SUM(receita), 0) AS receita_silver FROM silver.vendas
        ) s
        WHERE ROUND(g.receita_gold, 2) <> ROUND(s.receita_silver, 2)
    """,

    # 6.3 Receita total de vendas_detalhadas deve ser igual à de silver.vendas
    "gold.vendas_detalhadas: receita total igual à silver.vendas": """
        SELECT 1
        FROM (
            SELECT COALESCE(SUM(receita), 0) AS receita_gold FROM gold.vendas_detalhadas
        ) g,
        (
            SELECT COALESCE(SUM(receita), 0) AS receita_silver FROM silver.vendas
        ) s
        WHERE ROUND(g.receita_gold, 2) <> ROUND(s.receita_silver, 2)
    """,

    # 6.4 vendas_detalhadas deve ter o mesmo número de linhas que silver.vendas
    "gold.vendas_detalhadas: mesmo número de linhas que silver.vendas": """
        SELECT 1
        FROM (
            SELECT COUNT(1) AS linhas_gold   FROM gold.vendas_detalhadas
        ) g,
        (
            SELECT COUNT(1) AS linhas_silver FROM silver.vendas
        ) s
        WHERE g.linhas_gold <> s.linhas_silver
    """,

    # 6.5 id_venda único em vendas_detalhadas — uma linha por transação
    "gold.vendas_detalhadas: id_venda único":
        "SELECT id_venda FROM gold.vendas_detalhadas GROUP BY id_venda HAVING COUNT(*) > 1",

    # 6.6 Toda venda em vendas_detalhadas deve ter segmento_cliente e regiao preenchidos
    #     (garante que o JOIN com gold.clientes_segmentacao cobriu todos os clientes)
    "gold.vendas_detalhadas: toda venda com segmento_cliente e regiao preenchidos":
        "SELECT id_venda FROM gold.vendas_detalhadas WHERE segmento_cliente IS NULL OR regiao IS NULL",
}

# COMMAND ----------

resultados = []
for nome, consulta in TESTES.items():
    problemas = spark.sql(consulta).count()
    resultados.append((nome, problemas, "✅ OK" if problemas == 0 else "❌ FALHOU"))

df_resultados = spark.createDataFrame(resultados, "teste string, linhas_com_problema long, status string")
display(df_resultados)

# COMMAND ----------

falhas = [f"{nome} ({n} linhas com problema)" for nome, n, _ in resultados if n > 0]
if falhas:
    raise AssertionError(f"Testes de qualidade falharam ({len(falhas)} falhas):\n- " + "\n- ".join(falhas))

print(f"✅ Todos os {len(resultados)} testes de qualidade da camada Silver passaram com sucesso!")
