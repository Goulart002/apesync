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

## Acertos (simplificar dívidas)

Início → card de saldo → **Ver acertos** (`screens/acertos_screen.dart`):
- **Quem paga quem**: dívidas simplificadas no menor número de transferências
  (`AppData.simplificarDividas`, algoritmo guloso: quem mais deve paga quem mais tem a receber).
- **Registrar pagamento**: confirma e zera aquela transferência; saldos atualizam na hora.
- **Saldo de cada morador**: quem recebe e quem deve.
- **Histórico de pagamentos**.

Testes em `test/acertos_test.dart` (com os gastos de exemplo: 3 transferências em vez de 6).

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
| Sobre o app | `screens/sobre_screen.dart` | aba 2 de `/home` |
| Acertos | `screens/acertos_screen.dart` | `/acertos` |
| Sua casa | `screens/casa_screen.dart` | `/casa` |
| Moradores | `screens/moradores_screen.dart` | `/moradores` |

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
