<p align="center">
  <img width="940" alt="Axon Finance" src="https://raw.githubusercontent.com/axon-personal-finances/salesforce/main/resources/AxonPersonalFinancesLogo.png">
</p>

<p align="center"><a href="README.md">English</a> · <a href="README.pt-BR.md">Português</a></p>

# Axon Finance

Axon Finance é uma aplicação open source de finanças pessoais criada nativamente na plataforma Salesforce. Ela reúne contas bancárias, cartões de crédito, transações, investimentos, empréstimos, receitas, despesas e planejamento de fluxo de caixa em um modelo de dados seguro e extensível.

O projeto integra-se à [Pluggy](https://pluggy.ai/) para sincronizar dados financeiros por Open Finance, mantendo as credenciais da aplicação protegidas por External Credentials e Named Credentials do Salesforce.

## Principais recursos

- Sincronização de Open Finance pela API da Pluggy.
- Consolidação de contas bancárias, cartões, faturas, transações, investimentos e empréstimos.
- Gestão de receitas, despesas, parcelas, financiamentos e fluxo de caixa.
- Dashboards e ações Lightning construídos com Lightning Web Components.
- Autenticação segura no servidor — os segredos da Pluggy não ficam no Apex nem no navegador.
- Código-fonte no formato Salesforce DX e validação automatizada com GitHub Actions.

## Instalação no Salesforce

> Faça a primeira instalação em uma Sandbox ou Developer Edition. Revise os metadados e acessos solicitados antes de implantar em outra organização.

<p align="center">
  <a href="https://githubsfdeploy.herokuapp.com?owner=axon-personal-finances&repo=salesforce&ref=main">
    <img alt="Deploy to Salesforce" src="https://githubsfdeploy.herokuapp.com/resources/img/deploy.png">
  </a>
</p>

O botão utiliza a ferramenta comunitária GitHub Salesforce Deploy Tool. Caso sua organização bloqueie ferramentas de implantação de terceiros, use o Salesforce CLI:

```bash
git clone https://github.com/axon-personal-finances/salesforce.git
cd salesforce
sf org login web --alias AxonFinance
sf project deploy start --source-dir force-app --target-org AxonFinance
sf org assign permset --name AXF_PS_User --target-org AxonFinance
```

Depois da implantação, conclua a configuração da Pluggy descrita abaixo. Os segredos são específicos de cada organização e, de propósito, não fazem parte do repositório nem da implantação.

## Configuração da Pluggy

### 1. Crie sua conta e aplicação na Pluggy

1. Acesse o [Dashboard da Pluggy](https://dashboard.pluggy.ai/) e crie sua conta. A criação da conta também cria um Time, no qual você pode convidar colaboradores.
2. Abra **Aplicações** e crie uma aplicação para o ambiente desejado.
3. Copie o `CLIENT_ID` e o `CLIENT_SECRET` gerados. Aplicações de desenvolvimento e produção possuem credenciais diferentes.

Trate os dois valores como segredos. Eles dão acesso a dados financeiros e nunca devem ser adicionados ao Git, publicados em uma issue ou armazenados no frontend. Consulte o guia oficial da Pluggy sobre [chaves da API](https://docs.pluggy.ai/docs/get-your-api-keys).

### 2. Armazene as credenciais no Salesforce

A implantação cria estes componentes:

| Componente          | Nome de API         | Finalidade                                                         |
| ------------------- | ------------------- | ------------------------------------------------------------------ |
| External Credential | `AXF_EXC_Pluggy`    | Armazena com segurança os parâmetros da aplicação Pluggy.          |
| Named Credential    | `AXF_NC_Pluggy_API` | Define o endpoint `https://api.pluggy.ai` usado nos callouts Apex. |
| Permission Set      | `AXF_PS_User`       | Concede acesso à aplicação e ao principal da External Credential.  |

No Setup do Salesforce:

1. Acesse **Setup → Named Credentials → External Credentials**.
2. Abra **AXF Pluggy External Credential** (`AXF_EXC_Pluggy`).
3. No principal nomeado `AXF_Pluggy_Principal`, informe os parâmetros de autenticação:
   - `clientId`: o `CLIENT_ID` da Pluggy.
   - `clientSecret`: o `CLIENT_SECRET` da Pluggy.
4. Salve os parâmetros do principal.
5. Confirme que **AXF Pluggy API** (`AXF_NC_Pluggy_API`) está habilitada e aponta para `https://api.pluggy.ai`.
6. Atribua o conjunto de permissões **Axon Personal Finances - User** (`AXF_PS_User`) a cada usuário da aplicação.

O Axon Finance troca essas credenciais no servidor por uma API Key de curta duração. As API Keys da Pluggy expiram após duas horas; a aplicação gerencia a renovação e o cache automaticamente.

## Requisitos

- Uma organização Salesforce com suporte a Apex, Lightning Web Components e Named Credentials.
- Uma aplicação Pluggy com `CLIENT_ID` e `CLIENT_SECRET` ativos.
- Salesforce CLI e Node.js 22+ somente para desenvolvimento local ou instalação pela linha de comando.

## Desenvolvimento local

```bash
npm ci
npm run prettier:verify
npm run lint
npm run test:unit
```

```text
force-app/  Metadados implantáveis do Salesforce
config/     Configuração da Scratch Org
docs/       Documentação de arquitetura e entrega
scripts/    Utilitários Salesforce, SOQL, Apex e CI
.github/    Templates de issues e workflows de CI/CD
```

Consulte [Salesforce Development and Delivery](docs/SALESFORCE_DELIVERY.md) para conhecer o fluxo de contribuição e entrega.

## Segurança e privacidade

Informações financeiras e credenciais de API são sensíveis. Adote o menor privilégio, configure o compartilhamento do Salesforce adequadamente, teste em uma organização não produtiva e nunca versione URLs de autenticação, credenciais, tokens, dados financeiros exportados, `.env`, `.sf` ou `.sfdx`.

Para relatar uma vulnerabilidade, use o recurso de reporte privado de segurança do GitHub quando disponível; não publique detalhes exploráveis em uma issue pública.

## Como contribuir

Issues e pull requests são bem-vindos. Mantenha as alterações focadas, inclua os testes relevantes e não adicione dados financeiros pessoais nem segredos em exemplos, logs, commits ou capturas de tela.

## Licença e atribuição

Licenciado sob a [Apache License 2.0](LICENSE). Você pode usar, modificar e distribuir este projeto nos termos dessa licença. Cópias redistribuídas e trabalhos derivados devem preservar os avisos obrigatórios de copyright, licença e atribuição, incluindo o conteúdo do arquivo [NOTICE](NOTICE).

Axon Finance é um projeto open source independente e não é afiliado nem endossado pela Salesforce ou pela Pluggy. Salesforce e Pluggy são marcas de seus respectivos proprietários.
