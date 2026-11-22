import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_config.dart';
import '../../data/models/building_models.dart';

// ==================== STATE ====================
class BuildingState {
  final List<BuildingModel> buildings;
  final List<RoomModel> allRooms;
  final String searchQuery;
  final String? selectedBuildingId;

  BuildingState({
    this.buildings = const [],
    this.allRooms = const [],
    this.searchQuery = '',
    this.selectedBuildingId,
  });

  List<BuildingModel> get filteredBuildings {
    if (searchQuery.isEmpty) return buildings;
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return buildings;

    return buildings.where((building) {
      // Search in building name and code
      if (building.name.toLowerCase().contains(query) ||
          (building.code?.toLowerCase().contains(query) ?? false)) {
        return true;
      }

      // Search in floors
      for (final floor in building.floors) {
        if (floor.name.toLowerCase().contains(query) ||
            floor.floorNumber.toString().contains(query)) {
          return true;
        }

        // Search in rooms
        for (final room in floor.rooms) {
          if (room.name.toLowerCase().contains(query) ||
              room.roomType.toLowerCase().contains(query) ||
              room.roomTypeLabel.toLowerCase().contains(query) ||
              room.capacity.toString().contains(query)) {
            return true;
          }
        }
      }

      return false;
    }).toList();
  }

  List<RoomModel> get availableRooms {
    return allRooms.where((r) => r.isActive).toList();
  }

  List<RoomModel> roomsForBuilding(String buildingId) {
    final building = buildings.firstWhere(
      (b) => b.id == buildingId,
      orElse: () => BuildingModel(id: '', schoolId: '', name: ''),
    );
    return building.floors.expand((f) => f.rooms).toList();
  }

  BuildingState copyWith({
    List<BuildingModel>? buildings,
    List<RoomModel>? allRooms,
    String? searchQuery,
    String? selectedBuildingId,
    bool clearBuildingFilter = false,
  }) => BuildingState(
    buildings: buildings ?? this.buildings,
    allRooms: allRooms ?? this.allRooms,
    searchQuery: searchQuery ?? this.searchQuery,
    selectedBuildingId: clearBuildingFilter
        ? null
        : (selectedBuildingId ?? this.selectedBuildingId),
  );
}

// ==================== PROVIDER ====================
final buildingProvider = AsyncNotifierProvider<BuildingNotifier, BuildingState>(
  BuildingNotifier.new,
);

class BuildingNotifier extends AsyncNotifier<BuildingState> {
  @override
  Future<BuildingState> build() async => _load();

  Future<BuildingState> _load() async {
    final supabase = SupabaseConfig.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Non connecté');

    final profile = await supabase
        .from('users')
        .select('school_id')
        .eq('id', user.id)
        .single();
    final schoolId = profile['school_id'];

    // Load buildings with nested floors and rooms
    final buildingsResp = await supabase
        .from('buildings')
        .select('''
          *,
          floors(
            *,
            rooms(*)
          )
        ''')
        .eq('school_id', schoolId)
        .eq('is_active', true)
        .order('name');

    final buildings = (buildingsResp as List)
        .map((b) => BuildingModel.fromJson(b))
        .toList();

    // Also load flat list of all rooms for quick access
    final roomsResp = await supabase
        .from('rooms')
        .select('''
          *,
          floors(name, buildings(name))
        ''')
        .eq('is_active', true)
        .order('name');

    final allRooms = (roomsResp as List)
        .map((r) => RoomModel.fromJson(r))
        .toList();

    // Preserve existing search query if the state already exists
    final existingQuery = state.asData?.value.searchQuery ?? '';

    return BuildingState(
      buildings: buildings,
      allRooms: allRooms,
      searchQuery: existingQuery,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  void setSearch(String query) {
    final currentState = state;
    if (currentState is AsyncData<BuildingState>) {
      state = AsyncData(currentState.value.copyWith(searchQuery: query));
    }
  }

  void setBuildingFilter(String? buildingId) {
    state.whenData((s) {
      state = AsyncData(
        s.copyWith(
          selectedBuildingId: buildingId,
          clearBuildingFilter: buildingId == null,
        ),
      );
    });
  }

  // ==================== BUILDING CRUD ====================
  Future<void> addBuilding(BuildingModel building) async {
    await SupabaseConfig.adminClient.from('buildings').insert(building.toJson());
    ref.invalidateSelf();
  }

  Future<void> updateBuilding(String id, BuildingModel building) async {
    await SupabaseConfig.adminClient
        .from('buildings')
        .update(building.toJson())
        .eq('id', id);
    ref.invalidateSelf();
  }

  Future<void> deleteBuilding(String id) async {
    final previous = state.value;
    state.whenData((cur) {
      state = AsyncData(cur.copyWith(
        buildings: cur.buildings.where((b) => b.id != id).toList(),
      ));
    });

    final client = SupabaseConfig.adminClient;
    final fallbackClient = SupabaseConfig.client;
    try {
      try {
        final floors = await client.from('floors').select('id').eq('building_id', id);
        final floorIds = (floors as List).map((f) => f['id'].toString()).toList();
        if (floorIds.isNotEmpty) {
          await client.from('rooms').update({'is_active': false}).filter('floor_id', 'in', floorIds);
          await client.from('floors').update({'is_active': false}).eq('building_id', id);
        }
      } catch (_) {
        try {
          final floors = await fallbackClient.from('floors').select('id').eq('building_id', id);
          final floorIds = (floors as List).map((f) => f['id'].toString()).toList();
          if (floorIds.isNotEmpty) {
            await fallbackClient.from('rooms').update({'is_active': false}).filter('floor_id', 'in', floorIds);
            await fallbackClient.from('floors').update({'is_active': false}).eq('building_id', id);
          }
        } catch (_) {}
      }
      try {
        await client.from('buildings').update({'is_active': false}).eq('id', id);
      } catch (_) {
        try { await fallbackClient.from('buildings').update({'is_active': false}).eq('id', id); } catch (_) {}
      }
      try {
        await client.from('buildings').delete().eq('id', id);
      } catch (_) {}
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  // ==================== FLOOR CRUD ====================
  Future<void> addFloor(FloorModel floor) async {
    await SupabaseConfig.adminClient.from('floors').insert(floor.toJson());
    ref.invalidateSelf();
  }

  Future<void> updateFloor(String id, FloorModel floor) async {
    await SupabaseConfig.adminClient
        .from('floors')
        .update(floor.toJson())
        .eq('id', id);
    ref.invalidateSelf();
  }

  Future<void> deleteFloor(String id) async {
    final previous = state.value;
    state.whenData((cur) {
      final updatedBuildings = cur.buildings.map((b) {
        final remainingFloors = b.floors.where((f) => f.id != id).toList();
        return b.copyWith(floors: remainingFloors);
      }).toList();
      state = AsyncData(cur.copyWith(buildings: updatedBuildings));
    });

    final client = SupabaseConfig.adminClient;
    final fallbackClient = SupabaseConfig.client;
    try {
      try {
        await client.from('rooms').update({'is_active': false}).eq('floor_id', id);
      } catch (_) {
        try { await fallbackClient.from('rooms').update({'is_active': false}).eq('floor_id', id); } catch (_) {}
      }
      try {
        await client.from('rooms').delete().eq('floor_id', id);
      } catch (_) {}
      try {
        await client.from('floors').update({'is_active': false}).eq('id', id);
      } catch (_) {
        try { await fallbackClient.from('floors').update({'is_active': false}).eq('id', id); } catch (_) {}
      }
      try {
        await client.from('floors').delete().eq('id', id);
      } catch (_) {}
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }

  // ==================== ROOM CRUD ====================
  Future<void> addRoom(RoomModel room) async {
    await SupabaseConfig.adminClient.from('rooms').insert(room.toJson());
    ref.invalidateSelf();
  }

  Future<void> updateRoom(String id, RoomModel room) async {
    await SupabaseConfig.adminClient
        .from('rooms')
        .update(room.toJson())
        .eq('id', id);
    ref.invalidateSelf();
  }

  Future<void> deleteRoom(String id) async {
    final previous = state.value;
    state.whenData((cur) {
      final updatedBuildings = cur.buildings.map((b) {
        final updatedFloors = b.floors.map((f) {
          final remainingRooms = f.rooms.where((r) => r.id != id).toList();
          return FloorModel(
            id: f.id,
            buildingId: f.buildingId,
            name: f.name,
            floorNumber: f.floorNumber,
            isActive: f.isActive,
            createdAt: f.createdAt,
            rooms: remainingRooms,
          );
        }).toList();
        return b.copyWith(floors: updatedFloors);
      }).toList();
      state = AsyncData(cur.copyWith(
        buildings: updatedBuildings,
        allRooms: cur.allRooms.where((r) => r.id != id).toList(),
      ));
    });

    final client = SupabaseConfig.adminClient;
    final fallbackClient = SupabaseConfig.client;
    try {
      try {
        await client.from('rooms').update({'is_active': false}).eq('id', id);
      } catch (_) {
        try { await fallbackClient.from('rooms').update({'is_active': false}).eq('id', id); } catch (_) {}
      }
      try {
        await client.from('rooms').delete().eq('id', id);
      } catch (_) {}
    } catch (e) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}
