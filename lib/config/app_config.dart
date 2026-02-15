class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR_PROJECT.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR_ANON_KEY',
  );
  static const claudeEndpoint = String.fromEnvironment(
    'CLAUDE_ENDPOINT',
    defaultValue: 'https://YOUR_API_ENDPOINT/claude',
  );
  static const chatSecret = String.fromEnvironment(
    'CHAT_SECRET',
    defaultValue: '',
  );
  static const claudeApiKey = String.fromEnvironment(
    'CLAUDE_API_KEY',
    defaultValue: 'YOUR_ANTHROPIC_KEY',
  );

  static bool get isConfigured {
    return !supabaseUrl.contains('YOUR_PROJECT') &&
        !supabaseAnonKey.contains('YOUR_ANON_KEY') &&
        (!claudeEndpoint.contains('YOUR_API_ENDPOINT') ||
            !claudeApiKey.contains('YOUR_ANTHROPIC_KEY'));
  }
}
