import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'services/app_settings.dart';
import 'services/reminders.dart';
import 'services/sound_effects.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  final reminders = await LocalReminders.create();
  final settings = await AppSettings.load();
  runApp(
    TodoApp(
      reminders: reminders,
      settings: settings,
      sounds: AssetSoundPlayer(),
    ),
  );
}
