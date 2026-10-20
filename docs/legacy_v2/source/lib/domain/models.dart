/// Model domain, bebas dari widget dan jenis database.
enum Role { admin, officer }

enum Vehicle { motor, car }

extension RoleLabel on Role {
  String get label => this == Role.admin ? 'Admin' : 'Petugas';
}

extension VehicleLabel on Vehicle {
  String get label => this == Vehicle.motor ? 'Motor' : 'Mobil';
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    required this.active,
  });
  final int id;
  final String name, username;
  final Role role;
  final bool active;
}

class Credentials {
  const Credentials(this.user, this.passwordHash);
  final AppUser user;
  final String passwordHash;
}

class Session {
  const Session(this.token, this.user);
  final String token;
  final AppUser user;
}

class ParkingSetting {
  const ParkingSetting(this.vehicle, this.capacity, this.hourlyRate);
  final Vehicle vehicle;
  final int capacity, hourlyRate;
}

class SlotSummary {
  const SlotSummary(this.vehicle, this.capacity, this.occupied);
  final Vehicle vehicle;
  final int capacity, occupied;
  int get available => capacity - occupied;
  bool get full => available <= 0;
}

class Visit {
  const Visit({
    required this.id,
    required this.plate,
    required this.vehicle,
    required this.enteredAt,
    required this.hourlyRate,
    required this.entryOfficerId,
    required this.entryOfficerName,
    this.exitedAt,
    this.hours,
    this.total,
    this.received,
    this.change,
    this.exitOfficerId,
    this.exitOfficerName,
  });
  final String id, plate, entryOfficerName;
  final Vehicle vehicle;
  final DateTime enteredAt;
  final int hourlyRate, entryOfficerId;
  final DateTime? exitedAt;
  final int? hours, total, received, change, exitOfficerId;
  final String? exitOfficerName;
  bool get active => exitedAt == null;
  String get status => active ? 'Aktif · Belum bayar' : 'Selesai · Lunas';
}

class Quote {
  const Quote(this.visit, this.exitedAt, this.duration, this.hours, this.total);
  final Visit visit;
  final DateTime exitedAt;
  final Duration duration;
  final int hours, total;
}

class Dashboard {
  const Dashboard(this.slots, this.visits);
  final List<SlotSummary> slots;
  final List<Visit> visits;
}

class HistoryFilter {
  const HistoryFilter({
    required this.start,
    required this.end,
    this.vehicle,
    this.query = '',
  });
  final DateTime start, end;
  final Vehicle? vehicle;
  final String query;
  DateTime get from => DateTime(start.year, start.month, start.day);
  DateTime get until => DateTime(end.year, end.month, end.day + 1);
}

class Revenue {
  const Revenue(this.count, this.total);
  final int count, total;
}
