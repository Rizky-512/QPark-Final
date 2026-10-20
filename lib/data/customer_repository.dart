abstract interface class CustomerRepository {
  Future<List<String>> listVehicles(String userId);
  Future<void> addVehicle(String userId, String plate);
  Future<void> replaceVehicle(String userId, String oldPlate, String newPlate);
  Future<void> removeVehicle(String userId, String plate);
}
