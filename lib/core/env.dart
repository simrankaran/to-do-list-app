/// Supabase connection settings.
///
/// The publishable key is meant to ship in client apps: row level security in
/// the database is what keeps each user's data private. Override either value
/// at build time with `--dart-define=SUPABASE_URL=...` and
/// `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://cfrjrvkkkrkxggsticwe.supabase.co',
);

const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_UXj9EY7t41GhmkQWXuSkLA_kTW4vVbN',
);
