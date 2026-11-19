/// Login com Google: o "ID do cliente" do tipo **Aplicativo da Web** criado no
/// Google Cloud (o mesmo colado no Supabase → Authentication → Providers →
/// Google).
///
/// Não é segredo (vai dentro de todo APK), por isso fica no repositório e vale
/// para a equipe toda. O segredo do cliente fica só no Supabase, nunca aqui.
///
/// Para testar com outro projeto: --dart-define=GOOGLE_WEB_CLIENT_ID=...
/// Passo a passo no README, seção "Login com Google".
class GoogleConfig {
  static const webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '672831525600-ccjepsth5v8r9gbufj1adpqi6dnq2prd.apps.googleusercontent.com',
  );

  static bool get configurado => !webClientId.startsWith('SEU-CLIENT-ID');
}
