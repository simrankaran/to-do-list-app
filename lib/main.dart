import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'services/reminders.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  final reminders = await LocalReminders.create();
  runApp(TodoApp(reminders: reminders));
}
