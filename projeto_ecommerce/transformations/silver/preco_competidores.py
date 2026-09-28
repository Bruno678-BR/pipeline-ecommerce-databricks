"""
Transformação Silver: preco_competidores
Catálogo: projeto_ao_vivo | Schema: silver

PORQUÊ DAS REGRAS:
1. Deduplicação por chave composta (id_produto, nome_concorrente): Cada concorrente deve ter apenas
   um registro de preço monitorado por produto em cada ciclo de coleta.
2. DECIMAL(10,2) em preco_concorrente: Padronização financeira e prevenção de erros de precisão decimal.
3. Conversão de data_coleta para TIMESTAMP: Permite cálculos temporais, análises de defasagem de preço
   e ordenação cronológica adequada.
4. preco_suspeito (menor que 60% do nosso preco_atual): Preços excessivamente baixos no concorrente podem indicar
   erros de captura (scraping), produtos com defeito ou itens não comparáveis.
   REGRA DE OURO: Não descartamos o registro para manter o histórico de coletas; marcamos a coluna como booleana
   e monitoramos a taxa de ocorrência via expectativa de aviso (warn).
5. Expectations:
   - Fail: id_produto deve estar preenchido e preco_concorrente deve ser estritamente maior que zero.
   - Warn: preco_plausivel (preco_suspeito = false) para monitoramento de desvios de mercado sem interromper o pipeline.
"""

from pyspark import pipelines as dp
from pyspark.sql import functions as F

DINHEIRO = "DECIMAL(10,2)"


@dp.table(
    name="preco_competidores",
    comment="Tabela silver de monitoramento de preços da concorrência com validação de plausibilidade."
)
@dp.expect_all_or_fail({
    "id_produto_preenchido": "id_produto IS NOT NULL",
    "preco_positivo": "preco_concorrente > 0"
})
@dp.expect("preco_plausivel", "preco_suspeito = false")
def preco_competidores():
    produtos = spark.read.table("silver.produtos").select("id_produto", "preco_atual")

    return (
        spark.read.table("bronze.preco_competidores")
        .dropDuplicates(["id_produto", "nome_concorrente"])
        .withColumn("preco_concorrente", F.col("preco_concorrente").cast(DINHEIRO))
        .withColumn("data_coleta", F.to_timestamp(F.col("data_coleta")))
        .join(produtos, on="id_produto", how="left")
        .withColumn(
            "preco_suspeito",
            F.when(
                F.col("preco_atual").isNotNull()
                & (F.col("preco_concorrente") < (F.col("preco_atual") * 0.60)),
                F.lit(True)
            ).otherwise(F.lit(False))
        )
        .drop("preco_atual")
    )
