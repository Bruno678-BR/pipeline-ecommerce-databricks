"""
Transformação Silver: vendas
Catálogo: projeto_ao_vivo | Schema: silver

PORQUÊ DAS REGRAS:
1. Deduplicação por id_venda: Garante que cada transação de venda seja única, prevenindo duplicação
   de receita e contagem inflada de pedidos.
2. DECIMAL(10,2) em preco_unitario e receita: Toda métrica financeira precisa de precisão exata. A coluna
   receita = quantidade * preco_unitario é calculada explicitamente para assegurar totalização exata.
3. Extrações temporais (data, hora, dia_semana_num, dia_semana): Decompor o timestamp data_venda viabiliza
   análises de comportamento de compra (vendas por horário, dias de pico na semana) e particionamento.
4. REGRA DE OURO - Nunca descartar linhas:
   - Vendas de produto não cadastrado (20 vendas / R$ 4.240,01): Marcadas como produto_cadastrado = false.
     Não podemos apagar porque a venda existiu e seu valor compõe o faturamento total da empresa.
   - Vendas anteriores ao cadastro (5 vendas / R$ 325,88): Marcadas como venda_antes_do_cadastro = true.
     Mantidas para auditoria de catálogo e integridade contábil.
5. Expectations:
   - Fail: Campos mandatórios (id_venda, data_venda, id_cliente, id_produto), quantidade > 0, preco_unitario > 0
     e canal_venda em ('ecommerce', 'loja_fisica').
   - Warn: Expectativas de aviso para produto_cadastrado e venda_depois_do_cadastro, gerando métricas no
     Event Log do pipeline sem interromper a execução nem descartar registros válidos contabilmente.
"""

from pyspark import pipelines as dp
from pyspark.sql import functions as F

DINHEIRO = "DECIMAL(10,2)"

# Mapeamento do dia da semana (1 = Domingo ... 7 = Sábado)
MAPA_DIAS_SEMANA = {
    1: "Domingo",
    2: "Segunda",
    3: "Terça",
    4: "Quarta",
    5: "Quinta",
    6: "Sexta",
    7: "Sábado",
}

mapa_dias = F.create_map([F.lit(x) for k, v in MAPA_DIAS_SEMANA.items() for x in (k, v)])


@dp.table(
    name="vendas",
    comment="Tabela silver transacional de vendas com métricas calculadas e flags de conformidade cadastral."
)
@dp.expect_all_or_fail({
    "id_venda_preenchido": "id_venda IS NOT NULL",
    "data_venda_preenchida": "data_venda IS NOT NULL",
    "id_cliente_preenchido": "id_cliente IS NOT NULL",
    "id_produto_preenchido": "id_produto IS NOT NULL",
    "quantidade_valida": "quantidade IS NOT NULL AND quantidade > 0",
    "preco_unitario_valido": "preco_unitario IS NOT NULL AND preco_unitario > 0",
    "canal_venda_valido": "canal_venda IN ('ecommerce', 'loja_fisica')"
})
@dp.expect("produto_cadastrado", "produto_cadastrado = true")
@dp.expect("venda_depois_do_cadastro", "venda_antes_do_cadastro = false")
def vendas():
    produtos = spark.read.table("silver.produtos").select(
        F.col("id_produto"),
        F.lit(True).alias("produto_cadastrado_flag"),
        F.col("data_criacao").alias("data_criacao_produto")
    )

    return (
        spark.read.table("bronze.vendas")
        .dropDuplicates(["id_venda"])
        .withColumn("preco_unitario", F.col("preco_unitario").cast(DINHEIRO))
        .withColumn("receita", (F.col("quantidade") * F.col("preco_unitario")).cast(DINHEIRO))
        .withColumn("data", F.to_date(F.col("data_venda")))
        .withColumn("hora", F.hour(F.col("data_venda")))
        .withColumn("dia_semana_num", F.dayofweek(F.col("data_venda")))
        .withColumn("dia_semana", mapa_dias[F.col("dia_semana_num")])
        .join(produtos, on="id_produto", how="left")
        .withColumn("produto_cadastrado", F.coalesce(F.col("produto_cadastrado_flag"), F.lit(False)))
        .withColumn(
            "venda_antes_do_cadastro",
            F.when(
                F.col("data_criacao_produto").isNotNull()
                & (F.col("data_venda") < F.col("data_criacao_produto")),
                F.lit(True)
            ).otherwise(F.lit(False))
        )
        .drop("produto_cadastrado_flag", "data_criacao_produto")
    )
