/// Credenciais do projeto Supabase.
///
/// Pegue em: Supabase → Project Settings → API
///   - Project URL           -> url   (sem /rest/v1 no final)
///   - anon / public API key -> anonKey  (NUNCA a service_role)
///
/// Troque só os textos de defaultValue, ou passe na hora de rodar:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
///
/// A anon key é pública por design (vai dentro do app); quem protege os
/// dados são as policies de RLS do arquivo supabase/schema.sql.
class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://SEU-PROJETO.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'SUA-ANON-KEY',
  );

  static bool get configurado =>
      !url.contains('SEU-PROJETO') && !anonKey.contains('SUA-ANON-KEY');
}
