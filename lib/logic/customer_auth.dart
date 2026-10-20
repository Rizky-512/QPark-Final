import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/errors.dart';

class CustomerIdentity {
  const CustomerIdentity({required this.id, required this.displayName});
  final String id, displayName;
}

/// Authentication seam used by Supabase in production and a disabled provider
/// in demo/test builds without Supabase configuration.
abstract interface class CustomerAuthProvider {
  bool get googleAvailable;
  CustomerIdentity? get currentIdentity;
  Stream<CustomerIdentity?> get authStateChanges;
  Future<void> signInWithGoogle();
  Future<void> signOut();
}

class PendingSupabaseAuth implements CustomerAuthProvider {
  const PendingSupabaseAuth();
  @override
  bool get googleAvailable => false;
  @override
  CustomerIdentity? get currentIdentity => null;
  @override
  Stream<CustomerIdentity?> get authStateChanges => const Stream.empty();
  @override
  Future<void> signInWithGoogle() async => throw const QParkException(
    'Supabase belum dikonfigurasi. Isi SUPABASE_URL dan SUPABASE_PUBLISHABLE_KEY.',
  );
  @override
  Future<void> signOut() async {}
}

class SupabaseCustomerAuth implements CustomerAuthProvider {
  const SupabaseCustomerAuth(
    this.client, {
    required this.mobileRedirectUrl,
    required this.webRedirectUrl,
  });

  final SupabaseClient client;
  final String mobileRedirectUrl, webRedirectUrl;

  CustomerIdentity? _identity(User? user) {
    if (user == null) return null;
    final metadata = user.userMetadata;
    final name =
        metadata?['full_name'] ?? metadata?['name'] ?? user.email ?? 'Customer';
    return CustomerIdentity(id: user.id, displayName: name.toString());
  }

  @override
  bool get googleAvailable => true;

  @override
  CustomerIdentity? get currentIdentity => _identity(client.auth.currentUser);

  @override
  Stream<CustomerIdentity?> get authStateChanges => client
      .auth
      .onAuthStateChange
      .map((event) => _identity(event.session?.user))
      .distinct((a, b) => a?.id == b?.id && a?.displayName == b?.displayName);

  @override
  Future<void> signInWithGoogle() async {
    try {
      await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? webRedirectUrl : mobileRedirectUrl,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    } on AuthException catch (error) {
      throw QParkException('Login Google gagal: ${error.message}');
    } catch (_) {
      throw const QParkException(
        'Login Google gagal dibuka. Periksa koneksi lalu coba lagi.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } on AuthException catch (error) {
      throw QParkException('Gagal keluar dari akun: ${error.message}');
    }
  }
}
