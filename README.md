# ApêSync

> "Sincronizando a convivência, dividindo os custos sem dividir a amizade."

## Sobre o Projeto
O **ApêSync** é um aplicativo móvel voltado para a gestão automatizada de moradias compartilhadas:
divisão de gastos entre moradores, simplificação de dívidas, registro de pagamentos e leitura de nota
fiscal por OCR. Funciona **offline** (SQLite no celular) e sincroniza com o **Supabase** quando há internet.

Projeto Integrado 1 — Desenvolvimento Mobile · PUC Minas

## Equipe
* **Vitor Goulart** — Frontend / Mobile
* **Raphael Rodrigues** — Backend
* **Gabriel Maia** — Integração / Dados (OCR)
* **João Pedro** — UI/UX & QA

## Tecnologias
* Flutter / Dart (Material 3)
* Supabase — PostgreSQL, Auth, Row Level Security, Realtime
* SQLite (`sqflite`) — banco local, offline-first
* Google ML Kit Text Recognition — scanner de nota fiscal
* `google_sign_in` — login com Google nativo (Credential Manager do Android)
* `connectivity_plus`, `uuid`, `image_picker`, `crypto`


O repositório já vem com a permissão de INTERNET no `AndroidManifest.xml` e com `isMinifyEnabled = false`
no `android/app/build.gradle.kts` (o R8 quebrava o ML Kit no release). Se o Gradle pedir o NDK
`28.2.13676358`, instale pelo Android Studio → SDK Manager → SDK Tools → NDK (Side by side).
Se o celular recusar instalar ("pacote conflita"), desinstale a versão antiga — APKs gerados em PCs
diferentes têm assinaturas de debug diferentes.

O identificador do app é **`br.com.apesync`** (`applicationId` no `android/app/build.gradle.kts`;
definitivo, não muda depois de publicar na loja). Até o Bloco 6 era `com.example.apesync`, que a
Google Play não aceita: se ainda tiver o app antigo instalado, pode desinstalar (os dados voltam do
servidor no app novo).

Testes: `flutter test`

## Ajustes

Aba **Ajustes** (`screens/ajustes_screen.dart`, no lugar da antiga aba Sobre):
- **Perfil:** trocar o nome (muda na casa e na conta).
- **Trocar senha** (pede a senha atual) ou **Criar senha**, para quem entrou só com Google.
- **Cor do app:** 6 opções (`AppColors.paletas` em `lib/theme.dart`). A escolha fica nos metadados
  da conta (`cor_app`), então vale em qualquer celular. `AppColors.primary`, `primaryLight` e
  `primaryMuted` seguem a cor escolhida: **não use `const`** em widgets que usam essas três cores.
- **Sobre o ApêSync**, **Sair da conta** e **Excluir conta**.

### Excluir conta

Exigência da App Store e da Google Play. Pede para digitar `EXCLUIR` e precisa de internet:
- Admin que mora **sozinho** (nenhum outro morador com conta): a casa é apagada inteira.
- Admin com outros moradores: precisa **transferir a administração** antes.
- Morador: precisa estar com o **saldo zerado** (mesma regra de sair da casa). Nos gastos antigos
  ele vira **"Ex-morador"** (sem conta, sem PIX), para as contas de quem fica continuarem certas.
- O servidor faz tudo na função `excluir_minha_conta()` do `schema.sql` (inclusive apagar o
  login em `auth.users`) e o app apaga o banco local e revoga o acesso do Google.

## Banco de dados e sincronização offline

- `supabase/schema.sql` — tabelas `casas`, `moradores`, `gastos`, `pagamentos`, RLS, trigger `synced_at`,
  função `entrar_na_casa`, realtime.
- `lib/data/local_db.dart` — SQLite local (mesmas tabelas + coluna `pendente`).
- `lib/data/app_data.dart` — repositório: telas leem/escrevem só no SQLite (funciona offline).
- `lib/data/sync_service.dart` — push dos pendentes (upsert), pull incremental (`synced_at`),
  conflito "last write wins" (`updated_at`), realtime e detecção de rede.
- `lib/data/regras_sync.dart` — regras puras do sync (testes em `test/regras_sync_test.dart`).

Garantias da sincronização:
- **A alteração mais recente vence, decidido no servidor** (trigger `mais_recente_vence`): um
  celular que estava offline e envia uma versão mais velha não apaga a edição mais nova de
  outro morador. Relógio de celular adiantado (mais de 5 min) é corrigido para a hora do servidor.
- **Download com margem de 60 s**: cada download volta um pouco antes da última marca, para
  não perder linhas gravadas quase ao mesmo tempo; linhas que o celular já tem são ignoradas.
- **Gastos e pagamentos só citam moradores da própria casa** (triggers `validar_moradores_*`).

## Login com Google

Botão **Continuar com Google** no login (`lib/services/login_google.dart`): abre a janela de
contas do Android, sem navegador. O Google devolve um ID token e o Supabase troca por uma sessão
(`signInWithIdToken`, com *nonce* contra reaproveitamento de token).
- Primeira vez: a conta é criada sozinha e o nome do morador vem da conta Google.
- Quem já tinha conta com senha no **mesmo e-mail** continua com a mesma conta: o Supabase junta
  as duas (mesma casa, mesmo histórico).

### Configuração (uma vez por projeto Supabase)

1. **Google Cloud** ([console.cloud.google.com](https://console.cloud.google.com)) → criar um projeto.
2. **Google Auth Platform → Branding / Público-alvo**: tipo **Externo**, nome do app e e-mail de
   suporte. Enquanto o app estiver "Em teste", adicione o e-mail de quem vai testar em
   **Usuários de teste**.
3. **Clientes → Criar cliente → Aplicativo da Web** (ex.: "ApeSync Supabase"). Em *URIs de
   redirecionamento autorizados* coloque `https://SEU-PROJETO.supabase.co/auth/v1/callback`.
   Guarde o **ID do cliente** e a **chave secreta**.
4. **Clientes → Criar cliente → Android**: pacote `br.com.apesync` e o **SHA-1** do PC que
   gera o APK (comando abaixo). **Cada desenvolvedor cria um cliente Android com o SHA-1 do
   próprio PC** (APKs de debug de PCs diferentes têm assinaturas diferentes).
5. **Supabase → Authentication → Sign In / Providers → Google**: ativar, colar o ID do cliente
   **Web** em *Client IDs* e a chave secreta em *Client Secret*. Deixe *Skip nonce checks*
   desligado. Salvar.
6. **`lib/config_google.dart`** → `GoogleConfig.webClientId` = ID do cliente **Web** (ou rode
   com `--dart-define=GOOGLE_WEB_CLIENT_ID=...`). O ID não é segredo e fica no repositório, valendo
   para a equipe toda; a chave secreta fica só no Supabase.

SHA-1 do certificado de debug (PowerShell):

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -J-Duser.language=en -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

(o `-J-Duser.language=en` evita um erro do keytool em português). Para publicar na Play Store,
crie também um cliente Android com o SHA-1 da chave de release.

Se der erro: *"O Google recusou o login neste aparelho"* = pacote ou SHA-1 errado no cliente
Android (ou ID Web errado no `config_google.dart`); *"não está ativado no Supabase"* = passo 5;
*"O ID do cliente Google do app não está no Supabase"* = o ID do `config_google.dart` não foi
colado em *Client IDs*.

## Recuperar senha

Login → **Esqueci minha senha** (`screens/recuperar_senha_screen.dart`):
1. A pessoa informa o e-mail e o Supabase manda o e-mail padrão **"Reset your password"**.
2. Ela abre o e-mail **no celular onde pediu** e toca em **Reset password**.
3. O link leva a `apesync://recuperar-senha`, que **abre o app já logado** (intent-filter no
   `AndroidManifest.xml`; quem troca o link pela sessão é o `supabase_flutter`, com PKCE). O
   `main.dart` recebe o aviso `passwordRecovery` e mostra a tela **Criar senha nova**.

Serve também para quem entrou com Google criar uma senha. Link vencido, já usado ou aberto em
outro celular mostra um aviso no app.

Configuração (já feita no projeto): **Supabase → Authentication → URL Configuration →
Redirect URLs** com `apesync://recuperar-senha`.

Limites do e-mail padrão do Supabase: poucos e-mails por hora, só entrega para e-mails de
**membros da organização** no Supabase e não deixa editar o modelo. Para usar com qualquer
e-mail, configure um SMTP (Authentication → Emails → SMTP Settings; ex.: Brevo ou Resend, com
plano grátis). Com SMTP dá para editar o modelo **Reset Password** e incluir também o código
`{{ .Token }}`: a tela tem a opção **Recebi um código** para digitar o código em vez de usar o
link.

## Administração da casa

Quem cria a casa é o **administrador** (`casas.admin_id`). Regras em `lib/data/permissoes.dart`
(tela) e nas policies de RLS de `supabase/schema.sql` (servidor — valem mesmo fora do app):

| Ação | Morador | Admin |
|---|---|---|
| Ver gastos, saldos e moradores | ✅ | ✅ |
| Lançar gasto | ✅ | ✅ |
| Editar/excluir gasto | só os que lançou | qualquer um |
| Registrar/desfazer pagamento | se paga ou recebe | qualquer um |
| Editar nome | só o próprio | qualquer um |
| Convidar (código / compartilhar) | ✅ | ✅ |
| Gerar novo código de convite | — | ✅ |
| Remover morador quite ou devendo (nunca quem tem a receber) | — | ✅ |
| Transferir a administração | — | ✅ |
| Sair da casa (com saldo zerado) | ✅ | depois de transferir |

- Moradores só entram pelo **código de convite** (não existe mais "morador sem conta").
  Quem foi removido e volta com o código recupera o mesmo registro e o histórico.
- Quem é removido descobre no próximo sync e o app volta para a tela "Sua casa".
- Removido **devendo**: o app cria um gasto de categoria **Ajuste** ("Ajuste: dívida de X
  dividida"), pago por X e dividido igualmente entre quem fica — o saldo de X vai a zero e as
  contas continuam fechando (`Calculos.ajusteDeRemocao`). Ajustes não entram nos totais do mês,
  não podem ser editados, e só o admin os exclui, depois que X voltar para a casa (a dívida volta).
- Se o servidor recusar uma alteração feita offline (ex.: a pessoa perdeu a permissão), o app
  descarta essa alteração e volta para a versão do servidor, em vez de travar o sync.
- Depois de atualizar o app, **rode o `supabase/schema.sql` de novo** no SQL Editor (não apaga dados).

Testes em `test/permissoes_test.dart`.

## Acertos (simplificar dívidas)

Início → card de saldo → **Ver acertos** (`screens/acertos_screen.dart`):
- **Quem paga quem**: dívidas simplificadas no menor número de transferências
  (`AppData.simplificarDividas`, algoritmo guloso: quem mais deve paga quem mais tem a receber).
- **Registrar pagamento**: confirma e zera aquela transferência; saldos atualizam na hora.
- **Saldo de cada morador**: quem recebe e quem deve.
- **Histórico de pagamentos**.

Testes em `test/acertos_test.dart` (com os gastos de exemplo: 3 transferências em vez de 6).

### PIX nos acertos

- Cada morador cadastra a **própria chave PIX** em Moradores (ícone PIX na sua linha). Só a
  própria pessoa muda a dela — o servidor também garante isso (trigger `proteger_morador`).
- **Pagar com PIX** (quando você deve): gera o código **PIX copia e cola** já com o valor, para
  colar no app do banco, e oferece "Já paguei — registrar".
- **Cobrar com PIX** (quando você recebe): mostra o **QR code** e permite mandar a cobrança pelo
  WhatsApp.
- O código segue o padrão BR Code do Banco Central (`lib/data/pix.dart`, testes em
  `test/pix_test.dart`, incluindo o exemplo oficial do manual). Pacote `qr_flutter` para o QR.

## Gastos fixos (recorrentes)

- No **Novo gasto**, ligue **Repetir todo mês**: o app lança o gasto todo mês no mesmo dia
  (dia 31 em mês curto vira o último dia). Ótimo para aluguel, internet, condomínio.
- Aba Gastos → **Gastos fixos**: lista, editar valor (vale para os próximos meses), pausar/retomar
  (ao retomar não lança os meses pausados) e excluir (os já lançados continuam).
- Quem lança é o celular de quem criou o gasto fixo ou do admin, ao abrir o app/sincronizar. O
  gasto de cada mês tem **id determinístico** (UUID v5 de gasto fixo + mês): dois celulares lançando
  o mesmo mês não duplicam. Lógica em `lib/data/recorrentes.dart`, testes em
  `test/recorrentes_test.dart`.

## Busca de gastos

Aba Gastos → lupa: procura em **todos os meses** pela descrição, categoria, quem pagou ou valor
(`120`, `1.500`, `189,90`). Ignora maiúsculas e acentos e exige todas as palavras
(`mercado bia` = mercado que a Bia pagou). Funciona junto com os filtros de categoria e mostra o
total encontrado. Regras em `lib/data/busca.dart`, testes em `test/busca_test.dart`.

## Tarefas da casa

Aba **Tarefas** (`screens/tarefas_screen.dart`) e **Nova tarefa** (`screens/nova_tarefa_screen.dart`):
- Tarefa **avulsa** ("Comprar papel higiênico, para a Bia, até sexta") ou **repetida**: todo dia,
  dias da semana (ex.: seg/qua/sex) ou todo mês, com **rodízio**: ao marcar como feita, a vez passa
  para o próximo da lista (pulando quem saiu da casa) e a data vai para a próxima vez. Se estava
  atrasada há várias vezes, pula as perdidas.
- Lista **Atrasadas / Hoje / Próximas**, filtro **Da casa / Minhas**, **placar do mês** (quem fez
  mais) e **feitas recentemente** ("Caio fez *Tirar o lixo* no lugar da Bia").
- Início: cartão **Suas tarefas de hoje**. Ao marcar como feita aparece **Desfazer**. Tarefa de
  **compras** oferece lançar o gasto já preenchido.
- Permissões: qualquer morador cria e marca como feita (inclusive cobrindo a vez de outro); editar
  e excluir só quem criou ou o admin (trigger `proteger_tarefa` no servidor).
- Histórico em `tarefas_feitas` com id determinístico (tarefa + data): a mesma vez não conta duas
  vezes, mesmo marcada em dois celulares. Regras em `lib/data/rodizio.dart`, testes em
  `test/rodizio_test.dart`.

## Scanner de nota fiscal

Botão **Escanear nota fiscal** no Novo gasto: tira foto (ou escolhe da galeria), lê o texto com
Google ML Kit no próprio aparelho e pré-preenche valor, data, descrição (nome da loja) e categoria.
Código em `lib/services/nota_scanner.dart`; testes em `test/nota_scanner_test.dart`.

- Funciona só em **Android e iOS** (no Chrome/desktop o botão avisa que é só no celular).
- Se `flutter pub get` reclamar de versão: `flutter pub add image_picker google_mlkit_text_recognition`.
- iOS (só com Mac): em `ios/Runner/Info.plist` adicione `NSCameraUsageDescription` e
  `NSPhotoLibraryUsageDescription`, e no `ios/Podfile` use `platform :ios, '15.5'`.

## Telas e rotas

| Tela | Arquivo | Rota |
|---|---|---|
| Login | `screens/login_screen.dart` | `/` |
| Cadastro | `screens/cadastro_screen.dart` | `/cadastro` |
| Recuperar senha | `screens/recuperar_senha_screen.dart` | `/recuperar-senha` |
| Início | `screens/inicio_screen.dart` | aba 0 de `/home` |
| Gastos | `screens/gastos_screen.dart` | aba 1 de `/home` |
| Novo gasto | `screens/novo_gasto_screen.dart` | `/novo-gasto` |
| Ajustes | `screens/ajustes_screen.dart` | aba 3 de `/home` |
| Sobre o app | `screens/sobre_screen.dart` | `/sobre` |
| Acertos | `screens/acertos_screen.dart` | `/acertos` |
| Sua casa | `screens/casa_screen.dart` | `/casa` |
| Moradores | `screens/moradores_screen.dart` | `/moradores` |
| Gastos fixos | `screens/recorrentes_screen.dart` | `/gastos-fixos` |
| Tarefas | `screens/tarefas_screen.dart` | aba 2 de `/home` |
| Nova tarefa | `screens/nova_tarefa_screen.dart` | `/nova-tarefa` |

## Navegação

- Login → Entrar → (Sua casa) → Home · Login → Cadastre-se → Cadastro → (Sua casa) → Home
- Login → Continuar com Google → (Sua casa) → Home
- Login → Esqueci minha senha → link do e-mail abre o app → Criar senha nova → Home
- Sua casa: criar casa (offline) ou entrar com código de convite (online)
- Início → Moradores → Gerenciar (adicionar, editar, remover, código de convite)
- Tocar num gasto → Editar gasto (salvar alterações ou excluir)
- Home: barra inferior Início / Gastos / Tarefas / Ajustes · Início → Ver todos → Gastos
- Gastos → lupa → busca em todos os meses
- Botão + → Novo gasto → Salvar → volta e atualiza saldo e listas
- Início → Ver acertos → Acertos (registrar pagamento)
- Ajustes → Sair da conta (ou Excluir conta) → Login · Ajustes → Sobre o ApêSync

Dados ficam no SQLite do celular e no Supabase; ver seção "Banco de dados e sincronização offline".
