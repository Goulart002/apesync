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
* `connectivity_plus`, `uuid`, `image_picker`


O repositório já vem com a permissão de INTERNET no `AndroidManifest.xml` e com `isMinifyEnabled = false`
no `android/app/build.gradle.kts` (o R8 quebrava o ML Kit no release). Se o Gradle pedir o NDK
`28.2.13676358`, instale pelo Android Studio → SDK Manager → SDK Tools → NDK (Side by side).
Se o celular recusar instalar ("pacote conflita"), desinstale a versão antiga — APKs gerados em PCs
diferentes têm assinaturas de debug diferentes.

Testes: `flutter test`

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
| Início | `screens/inicio_screen.dart` | aba 0 de `/home` |
| Gastos | `screens/gastos_screen.dart` | aba 1 de `/home` |
| Novo gasto | `screens/novo_gasto_screen.dart` | `/novo-gasto` |
| Sobre o app | `screens/sobre_screen.dart` | aba 3 de `/home` |
| Acertos | `screens/acertos_screen.dart` | `/acertos` |
| Sua casa | `screens/casa_screen.dart` | `/casa` |
| Moradores | `screens/moradores_screen.dart` | `/moradores` |
| Gastos fixos | `screens/recorrentes_screen.dart` | `/gastos-fixos` |
| Tarefas | `screens/tarefas_screen.dart` | aba 2 de `/home` |
| Nova tarefa | `screens/nova_tarefa_screen.dart` | `/nova-tarefa` |

## Navegação

- Login → Entrar → (Sua casa) → Home · Login → Cadastre-se → Cadastro → (Sua casa) → Home
- Sua casa: criar casa (offline) ou entrar com código de convite (online)
- Início → Moradores → Gerenciar (adicionar, editar, remover, código de convite)
- Tocar num gasto → Editar gasto (salvar alterações ou excluir)
- Home: barra inferior Início / Gastos / Sobre · Início → Ver todos → Gastos
- Botão + → Novo gasto → Salvar → volta e atualiza saldo e listas
- Início → Ver acertos → Acertos (registrar pagamento)
- Sobre → Sair da conta → Login

Dados ficam no SQLite do celular e no Supabase; ver seção "Banco de dados e sincronização offline".
