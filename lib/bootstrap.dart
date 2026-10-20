import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'data/remote_repository.dart';
import 'data/supabase_customer_repository.dart';
import 'logic/customer_auth.dart';
import 'logic/remote_service.dart';

Future<RemoteService> bootstrap() async {
  AppConfig.validateSupabase();
  final preferences = await SharedPreferences.getInstance();
  if (!AppConfig.supabaseConfigured) {
    return RemoteService(RemoteRepository(AppConfig.apiBaseUrl), preferences);
  }

  final initialized = await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
  );
  final client = initialized.client;
  return RemoteService(
    RemoteRepository(AppConfig.apiBaseUrl),
    preferences,
    customerAuth: SupabaseCustomerAuth(
      client,
      AppConfig.supabaseMobileRedirectUrl,
    ),
    customerData: SupabaseCustomerRepository(client),
  );
}
