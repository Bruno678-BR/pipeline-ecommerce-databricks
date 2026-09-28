# PRD: Pipeline de dados do e-commerce

Documento de requisitos do pipeline da Imersão Jornada de Dados. É a fonte da verdade para quem desenvolve, humano ou IA: antes de mudar o código, mude o PRD.

## 1. Contexto

E-commerce brasileiro com vendas em dois canais (site e loja física). Três diretores precisam de números confiáveis todo dia às 8h:

| Diretoria | Pergunta principal | Tabela gold |
|---|---|---|
| Comercial | Quanto vendemos, quando, em qual canal e com quais produtos? | `gold.vendas_temporais`, `gold.vendas_produtos` |
| Customer Success | Quem são os melhores clientes e onde estão? | `gold.clientes_segmentacao` |
| Pricing | Estamos mais caros que a concorrência? | `gold.precos_competitividade` |

## 2. Plataforma

- Databricks Free Edition, compute **serverless**.
- Unity Catalog, catálogo `ecommerce`, schemas `bronze`, `silver` e `gold`.
- Tudo implantado por **Declarative Automation Bundle** (`databricks.yml` na raiz).

## 3. Fontes

| Fonte | Formato | Endereço | Conteúdo |
|---|---|---|---|
| Data lake (Storage do Supabase, protocolo S3) | Parquet | bucket `Datalake`, arquivos `{tabela}.parquet` | `vendas`, `produtos`, `clientes`, `preco_competidores` |
| API do IBGE | JSON | `https://servicodados.ibge.gov.br/api/v1/localidades/estados` | 27 UFs com nome e região |

## 4. Camadas

### Bronze (`aula-02-python-engenharia/01_ingestao_bronze_gabarito.py`, Python) — Aula 2
- Baixa cada Parquet do bucket S3 com `boto3`, lê com pandas e grava uma tabela Delta por arquivo, **sobrescrevendo**.
- Enriquece com a API do IBGE (`bronze.estados_ibge`).
- Cria catálogo e schema se não existirem (**idempotente**).
- Credenciais no próprio notebook durante a aula; movê-las para o secret scope é tarefa da Aula 3.

### Silver (`aula-03-claude-code/01_silver.py`, PySpark) — Aula 3

| Tabela | Chave | Regras |
|---|---|---|
| `silver.produtos` | `id_produto` | Remove duplicatas; `preco_atual` em `DECIMAL(10,2)`; `faixa_preco` = PREMIUM (> 1.000), MEDIO (> 500) ou BASICO |
| `silver.clientes` | `id_cliente` | Remove duplicatas; nome em formato título; UF em maiúsculas; junta `nome_estado` e `regiao` do IBGE |
| `silver.preco_competidores` | `id_produto` + `nome_concorrente` | Remove duplicatas; preço em `DECIMAL(10,2)`; `data_coleta` em `timestamp` |
| `silver.vendas` | `id_venda` | Remove duplicatas; `receita = quantidade × preco_unitario`; `data`, `hora`, `dia_semana` (português) e `dia_semana_num` (1 = domingo); `produto_cadastrado` = false quando o produto não existe no catálogo. **Nenhuma venda é descartada.** |

### Gold (`aula-03-claude-code/02_gold.sql`, SQL) — Aula 3

| Tabela | Grão | Colunas principais |
|---|---|---|
| `gold.vendas_temporais` | data × hora × canal | `total_vendas`, `itens_vendidos`, `receita`, `clientes_unicos` |
| `gold.vendas_produtos` | produto | `receita`, `itens_vendidos`, `ticket_medio`, `ranking_receita`, `ranking_na_categoria`. Vendas sem cadastro aparecem como "Produto não cadastrado". |
| `gold.clientes_segmentacao` | cliente (inclusive quem nunca comprou) | `receita`, `total_compras`, `ticket_medio`, `regiao`, `segmento_cliente`, `ranking_receita` |
| `gold.precos_competitividade` | produto com preço de concorrente | `nosso_preco`, média, mínimo e máximo dos concorrentes, `diferenca_pct_vs_media`, `classificacao_preco`, `receita` |

**Regras de negócio**
- Segmentação: VIP a partir de R$ 22.000; TOP_TIER de R$ 17.000 até R$ 21.999,99; REGULAR abaixo disso.
- Classificação de preço: MAIS_CARO_QUE_TODOS, MAIS_BARATO_QUE_TODOS, ACIMA_DA_MEDIA, ABAIXO_DA_MEDIA ou NA_MEDIA.
- `diferenca_pct_vs_media` em pontos percentuais (10 = 10% mais caro).

## 5. Qualidade de dados (`aula-03-claude-code/testes/03_testes_qualidade.py`)

O Job **falha** se qualquer teste encontrar problema:

- unicidade das chaves da silver e da gold de pricing;
- campos obrigatórios de vendas preenchidos; todo cliente com região;
- canal em (`ecommerce`, `loja_fisica`); segmento em (`VIP`, `TOP_TIER`, `REGULAR`);
- quantidade e preço positivos; `receita = quantidade × preco_unitario`; VIP com receita ≥ 22.000;
- **reconciliação:** a receita da silver é igual à de `vendas_temporais`, `vendas_produtos` e `clientes_segmentacao`;
- vendas de produtos não cadastrados abaixo de **1%** do total.

## 6. Orquestração

Job `Pipeline E-commerce` (`resources/pipeline_ecommerce.job.yml`), serverless, todo dia às 06:00 (America/Sao_Paulo), e-mail em caso de falha:

```
ingestao_bronze → silver → gold → testes_qualidade → documentar_para_genie
```

Parâmetros do Job: `catalogo` (padrão `ecommerce`) e `url_base`.

## 7. Consumo

- Dashboard **Diretoria E-commerce** sobre a gold (`resources/diretoria_gold.dashboard.yml`).
- Genie space **Diretoria E-commerce** (Aula 4) sobre as 4 tabelas gold.

## 8. Requisitos não funcionais

- Nomes de tabelas e colunas em português, `snake_case`, sem acento.
- Nenhum catálogo fixo no código Python: sempre o widget `catalogo`.
- Notebooks no formato *source* do Databricks (`.py` e `.sql`), com células de texto explicando o porquê.
- Toda nova tabela gold precisa de pelo menos um teste de reconciliação ou de chave.
- `databricks bundle validate --strict` sem avisos antes de qualquer deploy.

## 9. Próxima feature (exercício da Aula 3)

**`gold.vendas_por_regiao`**: receita, vendas, clientes e ticket médio por região e canal, para a Diretora de Customer Success planejar a equipe regional.

Critérios de aceite:
1. Uma linha por `regiao` × `canal_venda`.
2. A soma da receita bate com `silver.vendas` (novo teste de reconciliação).
3. Comentários de tabela e coluna adicionados em `aula-04-genie/01_preparar_dados_para_ia.sql`.
4. Tabela incluída no Genie space e no dashboard gold (página Clientes).
5. Deploy em `dev`, Job verde, depois deploy em `prod`.
