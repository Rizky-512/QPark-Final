import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/errors.dart';
import 'customer_repository.dart';

class SupabaseCustomerRepository implements CustomerRepository {
  const SupabaseCustomerRepository(this.client);

  final SupabaseClient client;

  @override
  Future<List<String>> listVehicles(String userId) async {
    try {
      final rows = await client
          .from('customer_vehicles')
          .select('plate')
          .eq('user_id', userId)
          .order('created_at');
      return rows.map((row) => row['plate'] as String).toList(growable: false);
    } on PostgrestException catch (error) {
      throw QParkException('Data kendaraan gagal dimuat: ${error.message}');
    }
  }

  @override
  Future<void> addVehicle(String userId, String plate) async {
    try {
      await client.from('customer_vehicles').upsert({
        'user_id': userId,
        'plate': plate,
      }, onConflict: 'user_id,plate');
    } on PostgrestException catch (error) {
      throw QParkException('Kendaraan gagal disimpan: ${error.message}');
    }
  }

  @override
  Future<void> replaceVehicle(
    String userId,
    String oldPlate,
    String newPlate,
  ) async {
    try {
      await client
          .from('customer_vehicles')
          .update({'plate': newPlate})
          .eq('user_id', userId)
          .eq('plate', oldPlate);
    } on PostgrestException catch (error) {
      throw QParkException('Kendaraan gagal diubah: ${error.message}');
    }
  }

  @override
  Future<void> removeVehicle(String userId, String plate) async {
    try {
      await client
          .from('customer_vehicles')
          .delete()
          .eq('user_id', userId)
          .eq('plate', plate);
    } on PostgrestException catch (error) {
      throw QParkException('Kendaraan gagal dihapus: ${error.message}');
    }
  }
}
