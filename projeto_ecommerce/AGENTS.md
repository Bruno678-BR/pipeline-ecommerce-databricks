# Declarative Automation Bundles Project

This project uses Declarative Automation Bundles (DABs) for deployment. Add project-specific instructions below.

## For AI Agents: Use Databricks AI Tools

**BEFORE any other action, read the `databricks-core` skill.**

It sets you up to work with this project reliably: CLI authentication, profile
selection, data discovery, and the bundle deployment workflow. Without it,
results are often slower and less accurate.

If this skill is not available (Databricks AI Tools are not installed), you can install them for your coding agent in seconds:

```bash
databricks aitools install
```

If the CLI is not installed, see: https://docs.databricks.com/dev-tools/cli/install

---

## Project Instructions

### Contexto do Projeto
Construção do pipeline de e-commerce brasileiro no Databricks (Lakeflow Declarative Pipeline / DLT) dentro do bundle `projeto_ecommerce`.
- **Catálogo único:** `projetoaovivo`. Nunca use outro catálogo.
- **Schemas:** `bronze`, `silver` e `gold`.
- **Origem (Bronze):** As tabelas bronze já existem no catálogo `projetoaovivo` e são sobrescritas por outra ingestão:
  - `projetoaovivo.bronze.vendas`
  - `projetoaovivo.bronze.produtos`
  - `projetoaovivo.bronze.clientes`
  - `projetoaovivo.bronze.preco_competidores`

### Perfil da CLI & Comandos Databricks
- Use sempre o perfil de CLI `imersao` (`-p imersao`).
- Sempre rode `databricks bundle validate --strict -t dev -p imersao` antes do deploy.
- Comandos padrão:
  ```bash
  databricks bundle validate --strict -t dev -p imersao
  databricks bundle deploy -t dev -p imersao
  databricks bundle run pipeline_ecommerce -t dev -p imersao
  ```

### Convenções de Código e Engenharia
1. **Nomenclatura:** Nomes de tabelas e colunas em português, `snake_case`, sem acento.
2. **Linguagens:**
   - Camada Silver em Python: `from pyspark import pipelines as dp`
   - Camada Gold em SQL.
3. **Estrutura de Arquivos:**
   - Um arquivo por tabela: `transformations/silver/<nome_tabela>.py` e `transformations/gold/<nome_tabela>.sql`.
   - Limpar arquivos/exemplos do template não utilizados.
4. **Tipo de Carga:** Todas as tabelas são materialized views com leitura batch (`spark.read.table`), nunca streaming table, porque a bronze é sobrescrita a cada execução.
5. **Configuração de Pipeline:** Pipeline serverless, catálogo `projetoaovivo`, schema padrão `silver`. Golds publicadas explicitamente como `gold.<tabela>`. Nomes no código sempre `schema.tabela`, sem catálogo.
6. **Documentação de Código:** Cada arquivo começa com comentários explicando o **PORQUÊ** das regras, em português.
7. **Tipagem Financeira:** Dinheiro sempre `DECIMAL(10,2)`.
8. **Políticas de Qualidade de Dados:**
   - **Regra de ouro:** Nunca descarte linhas em silver (apagar vendas mudaria a receita contábil).
   - Problema de qualidade conhecido é **MARCADO** em uma coluna de controle (booleana) e medido com `@dp.expect` (*warn*).
   - `@dp.expect_all_or_fail` apenas para o que nunca pode acontecer (chaves nulas, valores <= 0, etc.).

### Números de Referência (Métricas Esperadas)
- **Vendas totais:** 3.020 vendas
- **Receita total:** R$ 974.077,28
- **Vendas de produtos não cadastrados:** 20 vendas (R$ 4.240,01)
- **Vendas antes do cadastro do produto:** 5 vendas (R$ 325,88)
- **Preços de concorrentes suspeitos (< 60% do preço atual):** 55
- **Clientes com pronome de tratamento no nome:** 11
- **Distribuição de clientes por região:**
  - Norte: 17
  - Nordeste: 12
  - Centro-Oeste: 9
  - Sudeste: 8
  - Sul: 4

