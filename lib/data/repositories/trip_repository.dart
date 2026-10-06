import 'package:sembast/sembast.dart' show Database;
import 'package:uuid/uuid.dart';

import '../../domain/models/catch_entry.dart';
import '../../domain/models/trip.dart';
import '../db/document_store.dart';

class TripRepository {
  TripRepository(this._db, this._trips, this._catches, {Uuid? uuid, DateTime Function()? clock})
      : _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final Database _db;
  final DocumentStore<Trip> _trips;
  final DocumentStore<CatchEntry> _catches;
  final Uuid _uuid;
  final DateTime Function() _clock;

  Stream<List<Trip>> watchAll() => _trips.watchAll().map(_newestFirst);
  Stream<Trip?> watch(String id) => _trips.watch(id);
  Future<Trip?> get(String id) => _trips.get(id);
  Future<List<Trip>> all() async => _newestFirst(await _trips.all());

  List<Trip> _newestFirst(List<Trip> trips) =>
      [...trips]..sort((a, b) => b.startDate.compareTo(a.startDate));

  Future<void> save(Trip trip) => _trips.put(trip);

  /// Starts a new session. At most one trip is active — nothing in the schema can enforce
  /// that, so it's enforced here, atomically: other active trips are ended, never left
  /// dangling as "active forever".
  Future<Trip> startSession({String title = '', String? waterBodyName}) async {
    final now = _clock().toUtc();
    final trip = Trip(
      id: _uuid.v4(),
      startDate: now,
      title: title,
      waterBodyName: waterBodyName,
      isActive: true,
    );
    await _db.transaction((txn) async {
      for (final existing in await _trips.all()) {
        if (existing.isActive) {
          await _trips.put(existing.copyWith(isActive: false, endDate: existing.endDate ?? now), client: txn);
        }
      }
      await _trips.put(trip, client: txn);
    });
    return trip;
  }

  Future<void> endSession(String id) async {
    final trip = await _trips.get(id);
    if (trip == null || !trip.isActive) return;
    await _trips.put(trip.copyWith(isActive: false, endDate: _clock().toUtc()));
  }

  /// Deleting a trip detaches its catches rather than destroying them — a day on the water
  /// is a label on catches, not their owner.
  Future<void> delete(String id) async {
    await _db.transaction((txn) async {
      for (final entry in await _catches.all()) {
        if (entry.tripId == id) {
          await _catches.put(entry.copyWith(tripId: null), client: txn);
        }
      }
      await _trips.delete(id, client: txn);
    });
  }

  DocumentStore<Trip> get store => _trips;
}
