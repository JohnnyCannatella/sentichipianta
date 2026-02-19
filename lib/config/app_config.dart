class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR_PROJECT.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_ANON_KEY',
  );
  static const aiEndpoint = String.fromEnvironment(
    'AI_ENDPOINT',
    defaultValue: 'https://YOUR_API_ENDPOINT/ai',
  );
  static const chatSecret = String.fromEnvironment(
    'CHAT_SECRET',
    defaultValue: '',
  );
  static const fireworksApiKey = String.fromEnvironment(
    'FIREWORKS_API_KEY',
    defaultValue: 'YOUR_FIREWORKS_KEY',
  );
  static const claudeEndpoint = aiEndpoint;
  static const claudeApiKey = fireworksApiKey;

  static bool get isConfigured {
    return !supabaseUrl.contains('YOUR_PROJECT') &&
        !supabaseAnonKey.contains('YOUR_ANON_KEY') &&
        (!aiEndpoint.contains('YOUR_API_ENDPOINT') ||
            !fireworksApiKey.contains('YOUR_FIREWORKS_KEY'));
  }
}
