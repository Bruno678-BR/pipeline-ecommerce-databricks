"""
Transformação Silver: produtos
Catálogo: projeto_ao_vivo | Schema: silver

PORQUÊ DAS REGRAS:
1. Deduplicação por id_produto: Garante a unicidade da dimensão de produtos, impedindo duplicidade
   em análises e evitando multiplicações indesejadas em joins com a tabela de vendas.
2. Trim em nome_produto: Elimina espaços em branco sobressalentes nas pontas para consistência
   em buscas, filtros e agrupamentos em relatórios.
3. DECIMAL(10,2) em preco_atual: Tipagem monetária precisa que evita inconsistências e desvios de
   arredondamento inerentes ao tipo de ponto flutuante (double/float).
4. faixa_preco: Segmentação mercadológica dos itens para análises de margem e precificação:
   - PREMIUM: preço > 1000
   - MEDIO: preço > 500 e <= 1000
   - BASICO: preço <= 500
5. Expectations:
   - Fail (regras intransigentes): Todo produto deve ter id_produto preenchido e preco_atual positivo.
"""

from pyspark import pipelines as dp
from pyspark.sql import functions as F

DINHEIRO = "DECIMAL(10,2)"


@dp.table(
    name="produtos",
    comment="Tabela silver de produtos limpa, deduplicada e com faixa de preço calculada."
)
@dp.expect_all_or_fail({
    "id_produto_preenchido": "id_produto IS NOT NULL",
    "preco_atual_positivo": "preco_atual > 0"
})
def produtos():
    return (
        spark.read.table("bronze.produtos")
        .dropDuplicates(["id_produto"])
        .withColumn("nome_produto", F.trim(F.col("nome_produto")))
        .withColumn("preco_atual", F.col("preco_atual").cast(DINHEIRO))
        .withColumn(
            "faixa_preco",
            F.when(F.col("preco_atual") > 1000, "PREMIUM")
            .when(F.col("preco_atual") > 500, "MEDIO")
            .otherwise("BASICO")
        )
    )
