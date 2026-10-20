import '../domain/models.dart';

/// Kontrak backend: mutasi memeriksa aktor dan commit secara atomik.
abstract interface class ParkingRepository {
  Future<Credentials?> credentials(String username);
  Future<AppUser?> user(int id);
  Future<Dashboard> dashboard(String query);
  Future<List<Visit>> active(String query);
  Future<Visit?> visit(String id);
  Future<Visit> createEntry(
    String plate,
    Vehicle vehicle,
    DateTime now,
    int actor,
  );
  Future<Visit> completePayment(Quote quote, int received, int actor);
  Future<List<Visit>> history(HistoryFilter filter);
  Future<Revenue> revenue(HistoryFilter filter);
  Future<List<ParkingSetting>> settings();
  Future<void> updateSetting(ParkingSetting setting, int actor);
  Future<List<AppUser>> officers();
  Future<AppUser> createOfficer(
    String name,
    String username,
    String hash,
    int actor,
  );
  Future<void> setOfficerActive(int id, bool active, int actor);
  Future<void> close();
}
