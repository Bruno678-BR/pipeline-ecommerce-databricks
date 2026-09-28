"""
Transformação Silver: clientes
Catálogo: projeto_ao_vivo | Schema: silver

PORQUÊ DAS REGRAS:
1. Deduplicação por id_cliente: Garante que cada cliente seja único na dimensão, evitando duplicações
   ao consolidar métricas de clientes e vendas.
2. Preservação de nome_original: Mantém o registro histórico/cadastral original para auditoria e conferência.
3. Limpeza de nome_cliente: Remoção de pronomes de tratamento no início (Sr., Sra., Srta., Dr., Dra.)
   e padronização em formato título (InitCap), assegurando uniformidade em comunicações e relatórios.
4. Padronização de estado (UF): Conversão para maiúsculas e remoção de espaços para consistência cadastral.
5. Mapeamento das 27 UFs do IBGE: Como não há tabela de estados na camada bronze, o enriquecimento com
   nome_estado e regiao geográfica é feito diretamente através de mapeamento fixo oficial das 27 UFs,
   habilitando agregações e segmentações territoriais.
6. Expectations:
   - Fail (regras intransigentes): id_cliente não pode ser nulo e regiao deve ser devidamente mapeada
     (impede clientes sem identificação ou com UFs inválidas).
"""

from pyspark import pipelines as dp
from pyspark.sql import functions as F

# Mapeamento oficial das 27 Unidades Federativas do Brasil (IBGE)
MAPA_UFS = {
    # Norte (7 UFs)
    "AC": ("Acre", "Norte"),
    "AP": ("Amapá", "Norte"),
    "AM": ("Amazonas", "Norte"),
    "PA": ("Pará", "Norte"),
    "RO": ("Rondônia", "Norte"),
    "RR": ("Roraima", "Norte"),
    "TO": ("Tocantins", "Norte"),
    # Nordeste (9 UFs)
    "AL": ("Alagoas", "Nordeste"),
    "BA": ("Bahia", "Nordeste"),
    "CE": ("Ceará", "Nordeste"),
    "MA": ("Maranhão", "Nordeste"),
    "PB": ("Paraíba", "Nordeste"),
    "PE": ("Pernambuco", "Nordeste"),
    "PI": ("Piauí", "Nordeste"),
    "RN": ("Rio Grande do Norte", "Nordeste"),
    "SE": ("Sergipe", "Nordeste"),
    # Centro-Oeste (4 UFs)
    "DF": ("Distrito Federal", "Centro-Oeste"),
    "GO": ("Goiás", "Centro-Oeste"),
    "MT": ("Mato Grosso", "Centro-Oeste"),
    "MS": ("Mato Grosso do Sul", "Centro-Oeste"),
    # Sudeste (4 UFs)
    "ES": ("Espírito Santo", "Sudeste"),
    "MG": ("Minas Gerais", "Sudeste"),
    "RJ": ("Rio de Janeiro", "Sudeste"),
    "SP": ("São Paulo", "Sudeste"),
    # Sul (3 UFs)
    "PR": ("Paraná", "Sul"),
    "RS": ("Rio Grande do Sul", "Sul"),
    "SC": ("Santa Catarina", "Sul"),
}

mapa_nome_estado = F.create_map([F.lit(x) for k, v in MAPA_UFS.items() for x in (k, v[0])])
mapa_regiao = F.create_map([F.lit(x) for k, v in MAPA_UFS.items() for x in (k, v[1])])


@dp.table(
    name="clientes",
    comment="Tabela silver de clientes enriquecida com nome tratado, estado por extenso e região do IBGE."
)
@dp.expect_all_or_fail({
    "id_cliente_preenchido": "id_cliente IS NOT NULL",
    "regiao_preenchida": "regiao IS NOT NULL"
})
def clientes():
    return (
        spark.read.table("bronze.clientes")
        .dropDuplicates(["id_cliente"])
        .withColumn("nome_original", F.col("nome_cliente"))
        .withColumn(
            "nome_cliente",
            F.initcap(
                F.trim(
                    F.regexp_replace(
                        F.col("nome_cliente"),
                        r"^(Sr\.|Sra\.|Srta\.|Dr\.|Dra\.)\s*",
                        ""
                    )
                )
            )
        )
        .withColumn("estado", F.upper(F.trim(F.col("estado"))))
        .withColumn("nome_estado", mapa_nome_estado[F.col("estado")])
        .withColumn("regiao", mapa_regiao[F.col("estado")])
    )
