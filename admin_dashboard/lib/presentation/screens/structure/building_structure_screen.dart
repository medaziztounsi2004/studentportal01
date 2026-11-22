import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/building_models.dart';
import '../../providers/building_provider.dart';
import '../../widgets/admin_sidebar.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/undo_redo_toolbar_buttons.dart';
import '../../providers/undo_redo_provider.dart';
import '../../widgets/feedback_pill.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';

class BuildingStructureScreen extends ConsumerStatefulWidget {
  const BuildingStructureScreen({super.key});
  @override
  ConsumerState<BuildingStructureScreen> createState() =>
      _BuildingStructureScreenState();
}

class _BuildingStructureScreenState
    extends ConsumerState<BuildingStructureScreen> {
  String? _expandedBuildingId;
  String? _expandedFloorId;
  final _searchController = TextEditingController();
  String _lastSearchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Auto-expand buildings and floors based on search query
  void _updateExpandedItemsForSearch(BuildingState state) {
    final query = state.searchQuery.trim().toLowerCase();

    // If search is cleared, collapse all
    if (query.isEmpty) {
      if (_expandedBuildingId != null || _expandedFloorId != null) {
        setState(() {
          _expandedBuildingId = null;
          _expandedFloorId = null;
        });
      }
      return;
    }

    // Find first building and floor that match the search
    String? buildingToExpand;
    String? floorToExpand;

    for (final building in state.buildings) {
      // Check if building itself matches
      bool buildingMatches =
          building.name.toLowerCase().contains(query) ||
          (building.code?.toLowerCase().contains(query) ?? false);

      if (buildingMatches) {
        buildingToExpand ??= building.id;
      }

      // Check floors and rooms
      for (final floor in building.floors) {
        bool floorMatches =
            floor.name.toLowerCase().contains(query) ||
            floor.floorNumber.toString().contains(query);

        bool hasMatchingRoom = false;
        for (final room in floor.rooms) {
          if (room.name.toLowerCase().contains(query) ||
              room.roomType.toLowerCase().contains(query) ||
              room.roomTypeLabel.toLowerCase().contains(query) ||
              room.capacity.toString().contains(query)) {
            hasMatchingRoom = true;
            break;
          }
        }

        // If this floor or its rooms match, expand it
        if (floorMatches || hasMatchingRoom) {
          buildingToExpand = building.id;
          floorToExpand = floor.id;
          break;
        }
      }

      if (buildingToExpand != null) break;
    }

    // Update expanded items if they changed
    if (_expandedBuildingId != buildingToExpand ||
        _expandedFloorId != floorToExpand) {
      setState(() {
        _expandedBuildingId = buildingToExpand;
        _expandedFloorId = floorToExpand;
      });
    }
  }

  Future<void> _handleUndo() async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canUndo('structure')) return;
    try {
      final desc = await notifier.undo('structure');
      if (mounted && desc != null) {
        FeedbackPill.showUndo(context, message: 'Action annulée : $desc');
      }
    } catch (e) {
      if (mounted) FeedbackPill.showError(context, 'Impossible d\'annuler : $e');
    }
  }

  Future<void> _handleRedo() async {
    final notifier = ref.read(undoRedoProvider.notifier);
    if (!ref.read(undoRedoProvider).canRedo('structure')) return;
    try {
      final desc = await notifier.redo('structure');
      if (mounted && desc != null) {
        FeedbackPill.showSuccess(context, 'Action rétablie : $desc');
      }
    } catch (e) {
      if (mounted) FeedbackPill.showError(context, 'Impossible de rétablir : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(buildingProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => _handleUndo(),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () => _handleUndo(),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => _handleRedo(),
        const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () => _handleRedo(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Row(
            children: [
              const AdminSidebar(currentRoute: '/structure'),
              Expanded(
                child: Column(
                  children: [
                    _buildTopBar(context, stateAsync),
                    Expanded(
                      child: stateAsync.when(
                        loading: () => const BuildingStructureSkeletonLoader(),
                        error: (e, _) => _buildErrorState(e),
                        data: (state) => _buildContent(context, state),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, AsyncValue<BuildingState> stateAsync) {
    int bCount = 0;
    int fCount = 0;
    int rCount = 0;
    stateAsync.whenData((s) {
      bCount = s.buildings.length;
      fCount = s.buildings.fold(0, (sum, b) => sum + b.floors.length);
      rCount = s.allRooms.length;
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9EAF2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Structure Physique',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$bCount bâtiments • $fCount étages • $rCount salles',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 320,
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (v) {
                ref.read(buildingProvider.notifier).setSearch(v);
                setState(() {});
              },
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher un bâtiment ou salle...',
                hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textTertiary),
                suffixIcon: _searchController.text.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text('⌘K', style: TextStyle(fontSize: 10, color: AppColors.textTertiary, fontFamily: 'monospace')),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(buildingProvider.notifier).setSearch('');
                          setState(() {});
                        },
                      ),
                filled: true,
                fillColor: AppColors.slate50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: const Color(0xFF655DD5).withOpacity(0.4), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          UndoRedoToolbarButtons(
            scope: 'structure',
            onUndo: _handleUndo,
            onRedo: _handleRedo,
          ),
          const SizedBox(width: 16),
          SizedBox(
            height: 40,
            child: PopupMenuButton<String>(
              onSelected: (v) => _showAddDialog(v),
              itemBuilder: (ctx) => [
                _buildPopupMenuItem('building', Icons.domain_add_rounded, 'Nouveau Bâtiment'),
                _buildPopupMenuItem('floor', Icons.layers_rounded, 'Nouvel Étage'),
                _buildPopupMenuItem('room', Icons.meeting_room_rounded, 'Nouvelle Salle'),
              ],
              offset: const Offset(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Material(
                color: const Color(0xFF6D4CF6),
                elevation: 2,
                shadowColor: const Color(0xFF6D4CF6).withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Row(
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Ajouter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupMenuItem(String value, IconData icon, String text) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF6D4CF6)),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
          ),
          const SizedBox(height: 24),
          const Text('Unable to load structure', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            UserFriendlyError.format(
              error,
              fallback: 'Unable to load building structure right now. Please try again.',
            ),
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => ref.read(buildingProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Réessayer', style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              side: BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, BuildingState state) {
    if (state.searchQuery != _lastSearchQuery) {
      _lastSearchQuery = state.searchQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateExpandedItemsForSearch(state));
    }

    final buildings = state.filteredBuildings;

    if (buildings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: AppColors.primaryLight.withValues(alpha: 0.5), shape: BoxShape.circle),
              child: Icon(Icons.domain_disabled_rounded, size: 64, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            const Text('Aucune structure trouvée', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Commencez par ajouter un premier bâtiment.', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddDialog('building'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Ajouter un Bâtiment', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...buildings.map((building) => _buildBuildingCard(building, state)),
        ],
      ),
    );
  }

  Widget _buildBuildingCard(BuildingModel building, BuildingState state) {
    final isExpanded = _expandedBuildingId == building.id;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expandedBuildingId = isExpanded ? null : building.id),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(16),
              bottom: isExpanded ? Radius.zero : const Radius.circular(16),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isExpanded ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(16),
                  bottom: isExpanded ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isExpanded ? const Color(0xFF6D4CF6) : AppColors.slate100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.business_rounded,
                      color: isExpanded ? Colors.white : AppColors.slate500,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          building.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isExpanded ? AppColors.textPrimary : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildModernBadge(Icons.layers_rounded, '${building.floors.length} étages', AppColors.textSecondary),
                            const SizedBox(width: 8),
                            _buildModernBadge(Icons.meeting_room_rounded, '${building.roomCount} salles', AppColors.textSecondary),
                            if (building.code != null && building.code!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              _buildModernBadge(Icons.tag_rounded, building.code!, AppColors.textTertiary),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        icon: Icons.edit_rounded,
                        color: AppColors.slate500,
                        hoverColor: AppColors.primary,
                        onTap: () => _showBuildingDialog(building: building),
                      ),
                      const SizedBox(width: 4),
                      _buildActionButton(
                        icon: Icons.delete_outline_rounded,
                        color: AppColors.slate500,
                        hoverColor: AppColors.error,
                        onTap: () => _confirmDelete('building', building.id, building.name),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isExpanded ? AppColors.primarySoft : AppColors.slate100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: isExpanded ? AppColors.primary : AppColors.slate500,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          if (isExpanded) ...[
            Divider(height: 1, color: AppColors.border),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  if (building.floors.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.layers_clear_rounded, size: 32, color: AppColors.slate300),
                            const SizedBox(height: 8),
                            Text('Aucun étage configuré', style: TextStyle(color: AppColors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    )
                  else
                    ...building.floors.map((floor) => _buildFloorSection(floor, building)),
                  
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () => _addFloorAutomatically(building.id),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Ajouter un étage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6D4CF6),
                          side: BorderSide(color: AppColors.border, width: 1.5),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModernBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required Color color, required Color hoverColor, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: hoverColor.withOpacity(0.1),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  Widget _buildFloorSection(FloorModel floor, BuildingModel building) {
    final isExpanded = _expandedFloorId == floor.id;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.015), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expandedFloorId = isExpanded ? null : floor.id),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.slate100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.layers_rounded, color: AppColors.slate500, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          floor.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
                        ),
                        Text(
                          '${floor.rooms.where((r) => r.isActive).length} salles',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        icon: Icons.edit_rounded,
                        color: AppColors.slate500,
                        hoverColor: AppColors.primary,
                        onTap: () => _showFloorDialog(floor: floor, buildingId: building.id),
                      ),
                      _buildActionButton(
                        icon: Icons.delete_outline_rounded,
                        color: AppColors.slate500,
                        hoverColor: AppColors.error,
                        onTap: () => _confirmDelete('floor', floor.id, floor.name),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.slate500,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          if (isExpanded) ...[
            Divider(height: 1, color: AppColors.border),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (floor.rooms.where((r) => r.isActive).isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aucune salle dans cet étage', style: TextStyle(color: AppColors.slate500, fontSize: 12)),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: floor.rooms.where((r) => r.isActive).map((room) => _buildRoomChip(room, floor)).toList(),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: () => _showRoomDialog(floorId: floor.id),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Ajouter une salle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.slate50,
                        foregroundColor: AppColors.textSecondary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoomChip(RoomModel room, FloorModel floor) {
    IconData getRoomIcon() {
      switch (room.roomType) {
        case 'classroom': return Icons.chair_alt_rounded;
        case 'lab': return Icons.science_rounded;
        case 'gym': return Icons.sports_basketball_rounded;
        case 'library': return Icons.local_library_rounded;
        case 'cafeteria': return Icons.restaurant_rounded;
        case 'office': return Icons.work_rounded;
        case 'restroom': return Icons.wc_rounded;
        default: return Icons.meeting_room_rounded;
      }
    }

    final Color baseColor;

    if (room.roomType == 'lab') {
      baseColor = AppColors.primary;
    } else if (room.roomType == 'office') {
      baseColor = AppColors.slate600;
    } else {
      baseColor = AppColors.textPrimary;
    }

    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(getRoomIcon(), size: 16, color: baseColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  room.name,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: baseColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${room.capacity} places',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => _showRoomDialog(room: room, floorId: floor.id),
                    child: Icon(Icons.edit_rounded, size: 14, color: AppColors.textTertiary),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _confirmDelete('room', room.id, room.name),
                    hoverColor: AppColors.errorSoft,
                    child: Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoTag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== DIALOGS ====================
  Future<void> _addFloorAutomatically(String buildingId) async {
    final buildingState = ref.read(buildingProvider).value;
    final building = buildingState?.buildings.firstWhere(
      (b) => b.id == buildingId,
      orElse: () => BuildingModel(id: '', schoolId: '', name: ''),
    );
    if (building == null || building.id.isEmpty) return;

    final existingFloors = building.floors;
    int nextNumber = 0;
    if (existingFloors.isNotEmpty) {
      int maxNum = 0;
      for (final f in existingFloors) {
        if (f.floorNumber > maxNum) maxNum = f.floorNumber;
      }
      nextNumber = maxNum + 1;
    }

    String floorName;
    if (nextNumber == 0) {
      floorName = 'Rez-de-chaussée';
    } else if (nextNumber == 1) {
      floorName = '1er étage';
    } else {
      floorName = '${nextNumber}ème étage';
    }

    if (existingFloors.any((f) => f.name == floorName)) {
      int suffix = 2;
      while (existingFloors.any((f) => f.name == '$floorName ($suffix)')) {
        suffix++;
      }
      floorName = '$floorName ($suffix)';
    }

    try {
      await ref.read(buildingProvider.notifier).addFloor(
        FloorModel(
          id: '',
          buildingId: buildingId,
          name: floorName,
          floorNumber: nextNumber,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Étage "$floorName" ajouté avec succès'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFriendlyError.format(e)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }


  void _showAddDialog(String type) {
    switch (type) {
      case 'building':
        _showBuildingDialog();
        break;
      case 'floor':
        final buildingState = ref.read(buildingProvider).value;
        if (buildingState != null && buildingState.buildings.isNotEmpty) {
          _addFloorAutomatically(buildingState.buildings.first.id);
        } else {
          _showBuildingDialog();
        }
        break;
      case 'room':
        _showRoomDialog();
        break;
    }
  }

  void _showBuildingDialog({BuildingModel? building}) {
    final nameController = TextEditingController(text: building?.name ?? '');
    final isNew = building == null;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              width: 500,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 50, offset: const Offset(0, 20)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border(bottom: BorderSide(color: AppColors.slate100)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isNew ? 'Nouveau Bâtiment' : 'Modifier Bâtiment', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                              const SizedBox(height: 4),
                              Text(isNew ? 'Ajouter un nouveau bâtiment à la structure' : 'Modifier les informations du bâtiment', style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.slate50),
                            child: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Nom du bâtiment *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            hintText: 'Ex: Bloc A',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
                            filled: true,
                            fillColor: AppColors.slate50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderLight)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.borderLight)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                          ),
                        ),

                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                      border: Border(top: BorderSide(color: AppColors.slate100)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 40,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF6B7280),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                            ),
                            child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (nameController.text.isEmpty) return;
                              final autoCode = (building?.code != null && building!.code!.isNotEmpty)
                                  ? building.code
                                  : nameController.text.trim().replaceAll(' ', '-').toUpperCase();
                              if (isNew) {
                                await ref.read(buildingProvider.notifier).addBuilding(
                                  BuildingModel(id: '', schoolId: '', name: nameController.text, code: autoCode),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bâtiment ajouté avec succès'), backgroundColor: AppColors.success));
                              } else {
                                await ref.read(buildingProvider.notifier).updateBuilding(building.id, building.copyWith(name: nameController.text, code: autoCode));
                              }
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(isNew ? 'Créer le bâtiment' : 'Enregistrer', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6D4CF6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showFloorDialog({FloorModel? floor, String? buildingId}) {
    final isNew = floor == null;
    int floorNumber = floor?.floorNumber ?? 0;

    final buildingState = ref.read(buildingProvider).value;
    final buildings = buildingState?.buildings ?? [];

    BuildingModel? selectedBuilding;
    if (buildingId != null && buildingState != null) {
      selectedBuilding = buildings.where((b) => b.id == buildingId).firstOrNull;
    } else if (floor != null && buildingState != null) {
      selectedBuilding = buildings.where((b) => b.id == floor.buildingId).firstOrNull;
    } else if (buildings.isNotEmpty) {
      selectedBuilding = buildings.first;
    }

    // Auto-generate floor name based on number
    String _generateFloorName(int number, String? currentBuildingId) {
      if (currentBuildingId == null) return '';

      final bState = ref.read(buildingProvider).value;
      if (bState == null) return '';

      // Find the building
      final building = bState.buildings.firstWhere(
        (b) => b.id == currentBuildingId,
        orElse: () => BuildingModel(id: '', schoolId: '', name: ''),
      );

      if (building.id.isEmpty) return '';

      // Check for duplicates
      final existingFloors = building.floors.where((f) => f.id != floor?.id);

      // Standard naming conventions
      String baseName;
      if (number == 0) {
        baseName = 'Rez-de-chaussée';
      } else if (number == 1) {
        baseName = '1er étage';
      } else if (number == 2) {
        baseName = '2ème étage';
      } else if (number == 3) {
        baseName = '3ème étage';
      } else if (number > 3) {
        baseName = '${number}ème étage';
      } else if (number == -1) {
        baseName = 'Sous-sol';
      } else if (number < -1) {
        baseName = 'Sous-sol ${number.abs()}';
      } else {
        baseName = 'Étage $number';
      }

      // Check if this name already exists
      final nameExists = existingFloors.any((f) => f.name == baseName);

      if (nameExists) {
        // Find next available suffix
        int suffix = 1;
        String newName;
        do {
          suffix++;
          newName = '$baseName ($suffix)';
        } while (existingFloors.any((f) => f.name == newName));
        return newName;
      }

      return baseName;
    }

    String autoName = isNew && selectedBuilding != null
        ? _generateFloorName(floorNumber, selectedBuilding!.id)
        : floor?.name ?? '';

    final nameController = TextEditingController(text: autoName);
    final numberController = TextEditingController(
      text: floorNumber.toString(),
    );

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              width: 500,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 50, offset: const Offset(0, 20)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border(bottom: BorderSide(color: AppColors.slate100)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isNew ? 'Nouvel Étage' : 'Modifier Étage', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                              const SizedBox(height: 4),
                              Text(isNew ? 'Ajouter un nouvel étage au bâtiment' : 'Modifier les informations de l\'étage', style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.slate50),
                            child: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cascading select: Bloc
                        const Text('Bâtiment / Bloc *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<BuildingModel>(
                          value: selectedBuilding,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(8),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textTertiary),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Sélectionner un bloc',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            filled: true,
                            fillColor: AppColors.slate50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                          ),
                          items: buildings.map((b) => DropdownMenuItem(value: b, child: Text(b.name, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)))).toList(),
                          onChanged: (b) {
                            setDialogState(() {
                              selectedBuilding = b;
                              if (isNew && selectedBuilding != null) {
                                nameController.text = _generateFloorName(floorNumber, selectedBuilding!.id);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text('Numéro d\'étage *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: numberController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          onChanged: (value) {
                            final num = int.tryParse(value) ?? 0;
                            setDialogState(() {
                              floorNumber = num;
                              if (isNew && selectedBuilding != null) {
                                nameController.text = _generateFloorName(num, selectedBuilding!.id);
                              }
                            });
                          },
                          decoration: InputDecoration(
                            hintText: '0 = RDC, 1 = 1er, -1 = Sous-sol',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            filled: true,
                            fillColor: AppColors.slate50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Nom de l\'étage *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameController,
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: isNew ? 'Nom auto-généré, modifiable' : 'Nom de l\'étage',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            filled: true,
                            fillColor: AppColors.slate50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                      border: Border(top: BorderSide(color: AppColors.slate100)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 40,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF6B7280),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                            ),
                            child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (selectedBuilding == null) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez sélectionner un bâtiment'), backgroundColor: AppColors.error));
                                return;
                              }
                              if (nameController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le nom est requis'), backgroundColor: AppColors.error));
                                return;
                              }
                              try {
                                final bState = ref.read(buildingProvider).value;
                                if (bState != null) {
                                  final bldg = bState.buildings.firstWhere((b) => b.id == selectedBuilding!.id, orElse: () => BuildingModel(id: '', schoolId: '', name: ''));
                                  final duplicateName = bldg.floors.where((f) => f.id != floor?.id).any((f) => f.name.trim().toLowerCase() == nameController.text.trim().toLowerCase());
                                  if (duplicateName) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Un étage avec ce nom existe déjà'), backgroundColor: AppColors.error));
                                    return;
                                  }
                                }
                                if (isNew) {
                                  await ref.read(buildingProvider.notifier).addFloor(FloorModel(id: '', buildingId: selectedBuilding!.id, name: nameController.text.trim(), floorNumber: int.tryParse(numberController.text) ?? 0));
                                } else {
                                  await ref.read(buildingProvider.notifier).updateFloor(floor!.id, FloorModel(id: floor.id, buildingId: selectedBuilding!.id, name: nameController.text.trim(), floorNumber: int.tryParse(numberController.text) ?? 0));
                                }
                                Navigator.pop(ctx);
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: AppColors.error));
                              }
                            },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(isNew ? 'Créer l\'étage' : 'Enregistrer', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6D4CF6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showRoomDialog({RoomModel? room, String? floorId}) {
    final isNew = room == null;
    String roomType = room?.roomType ?? 'classroom';

    final buildingState = ref.read(buildingProvider).value;
    final buildings = buildingState?.buildings ?? [];

    BuildingModel? selectedBuilding;
    FloorModel? selectedFloor;

    if (floorId != null && buildingState != null) {
      for (final b in buildings) {
        final f = b.floors.where((f) => f.id == floorId).firstOrNull;
        if (f != null) {
          selectedBuilding = b;
          selectedFloor = f;
          break;
        }
      }
    } else if (buildings.isNotEmpty) {
      selectedBuilding = buildings.first;
      selectedFloor = selectedBuilding.floors.firstOrNull;
    }

    // Auto-generate name for new rooms based on room type and floor
    String _generateRoomName(
      String type,
      FloorModel floor,
      List<RoomModel> existingRooms,
    ) {
      final floorNum = floor.floorNumber;

      // Get rooms of the same type on this floor
      final sameTypeRooms = existingRooms
          .where((r) => r.roomType == type && r.isActive)
          .toList();

      switch (type) {
        case 'classroom':
          // Standard: Floor number + sequential (101, 102, 201, 202, etc.)
          final existingNumbers = <int>[];
          for (final room in sameTypeRooms) {
            final match = RegExp(r'^(\d{3,})$').firstMatch(room.name);
            if (match != null) {
              final num = int.tryParse(match.group(1)!);
              if (num != null && num ~/ 100 == floorNum) {
                existingNumbers.add(num % 100);
              }
            }
          }

          int nextNum = 1;
          if (existingNumbers.isNotEmpty) {
            existingNumbers.sort();
            for (int i = 1; i <= existingNumbers.length + 1; i++) {
              if (!existingNumbers.contains(i)) {
                nextNum = i;
                break;
              }
            }
          }
          return '${floorNum}${nextNum.toString().padLeft(2, '0')}';

        case 'lab':
          // Labs: L + floor + sequential (L101, L102, L201, etc.)
          final labNumbers = <int>[];
          for (final room in sameTypeRooms) {
            final match = RegExp(r'^L(\d+)$').firstMatch(room.name);
            if (match != null) {
              final num = int.tryParse(match.group(1)!);
              if (num != null && num ~/ 100 == floorNum) {
                labNumbers.add(num % 100);
              }
            }
          }

          int nextNum = 1;
          if (labNumbers.isNotEmpty) {
            labNumbers.sort();
            for (int i = 1; i <= labNumbers.length + 1; i++) {
              if (!labNumbers.contains(i)) {
                nextNum = i;
                break;
              }
            }
          }
          return 'L${floorNum}${nextNum.toString().padLeft(2, '0')}';

        case 'office':
          // Offices: B (Bureau) + floor + sequential (B101, B102, B201, etc.)
          final officeNumbers = <int>[];
          for (final room in sameTypeRooms) {
            final match = RegExp(r'^B(\d+)$').firstMatch(room.name);
            if (match != null) {
              final num = int.tryParse(match.group(1)!);
              if (num != null && num ~/ 100 == floorNum) {
                officeNumbers.add(num % 100);
              }
            }
          }

          int nextNum = 1;
          if (officeNumbers.isNotEmpty) {
            officeNumbers.sort();
            for (int i = 1; i <= officeNumbers.length + 1; i++) {
              if (!officeNumbers.contains(i)) {
                nextNum = i;
                break;
              }
            }
          }
          return 'B${floorNum}${nextNum.toString().padLeft(2, '0')}';

        case 'library':
          // Libraries: LIB + floor (LIB-1, LIB-2, etc.) - usually one per floor
          return 'LIB-$floorNum';

        case 'gym':
          // Gyms: GYM + floor (GYM-1, GYM-2, etc.)
          final gymCount = sameTypeRooms.length + 1;
          return 'GYM-$floorNum${gymCount > 1 ? '-$gymCount' : ''}';

        case 'cafeteria':
          // Cafeterias: CAF + floor
          final cafCount = sameTypeRooms.length + 1;
          return 'CAF-$floorNum${cafCount > 1 ? '-$cafCount' : ''}';

        case 'other':
        default:
          // Other rooms: SALLE + floor + sequential
          final otherNumbers = <int>[];
          for (final room in sameTypeRooms) {
            final match = RegExp(r'^SALLE-(\d+)$').firstMatch(room.name);
            if (match != null) {
              final num = int.tryParse(match.group(1)!);
              if (num != null) {
                otherNumbers.add(num);
              }
            }
          }

          int nextNum = 1;
          if (otherNumbers.isNotEmpty) {
            otherNumbers.sort();
            nextNum = otherNumbers.last + 1;
          }
          return 'SALLE-${floorNum}${nextNum.toString().padLeft(2, '0')}';
      }
    }

    String autoGeneratedName = '';
    if (isNew && selectedFloor != null) {
      autoGeneratedName = _generateRoomName(roomType, selectedFloor, selectedFloor.rooms);
    }

    final nameController = TextEditingController(
      text: room?.name ?? autoGeneratedName,
    );
    final capacityController = TextEditingController(
      text: room?.capacity.toString() ?? '30',
    );

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              width: 500,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 50, offset: const Offset(0, 20)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border(bottom: BorderSide(color: AppColors.slate100)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isNew ? 'Nouvelle Salle' : 'Modifier Salle', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                              const SizedBox(height: 4),
                              Text(isNew ? 'Ajouter une nouvelle salle à l\'étage' : 'Modifier les informations de la salle', style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.slate50),
                            child: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cascading select: Bloc
                        const Text('Bâtiment / Bloc *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<BuildingModel>(
                          value: selectedBuilding,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(8),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textTertiary),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Sélectionner un bloc',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            filled: true,
                            fillColor: AppColors.slate50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                          ),
                          items: buildings.map((b) => DropdownMenuItem(value: b, child: Text(b.name, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)))).toList(),
                          onChanged: (b) {
                            setDialogState(() {
                              selectedBuilding = b;
                              selectedFloor = b?.floors.firstOrNull;
                              if (isNew && selectedFloor != null) {
                                nameController.text = _generateRoomName(roomType, selectedFloor!, selectedFloor!.rooms);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        // Cascading select: Étage
                        const Text('Étage *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<FloorModel>(
                          value: selectedFloor,
                          isExpanded: true,
                          borderRadius: BorderRadius.circular(8),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textTertiary),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: selectedBuilding == null ? 'Sélectionnez un bloc d\'abord' : 'Sélectionner un étage',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            filled: true,
                            fillColor: AppColors.slate50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                          ),
                          items: (selectedBuilding?.floors ?? []).map((f) => DropdownMenuItem(value: f, child: Text(f.name, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)))).toList(),
                          onChanged: (f) {
                            setDialogState(() {
                              selectedFloor = f;
                              if (isNew && selectedFloor != null) {
                                nameController.text = _generateRoomName(roomType, selectedFloor!, selectedFloor!.rooms);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text('Nom de la salle *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameController,
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: isNew ? 'Nom auto-généré, modifiable' : 'Nom de la salle',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            filled: true,
                            fillColor: AppColors.slate50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Type de salle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: roomType,
                          borderRadius: BorderRadius.circular(8),
                          dropdownColor: Colors.white,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textTertiary),
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: AppColors.slate50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                          ),
                          items: RoomModel.roomTypes
                              .map((t) => DropdownMenuItem(value: t.$1, child: Text(t.$2, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))))
                              .toList(),
                          onChanged: (v) {
                            setDialogState(() {
                              roomType = v!;
                              if (isNew && selectedFloor != null) {
                                nameController.text = _generateRoomName(roomType, selectedFloor!, selectedFloor!.rooms);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text('Capacité (personnes)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: capacityController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Ex: 30',
                            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                            filled: true,
                            fillColor: AppColors.slate50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.borderLight)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6D4CF6), width: 1.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                      border: Border(top: BorderSide(color: AppColors.slate100)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: 40,
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF6B7280),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                            ),
                            child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final targetFloorId = selectedFloor?.id ?? floorId;
                              if (targetFloorId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez sélectionner un étage'), backgroundColor: AppColors.error));
                                return;
                              }
                              final roomName = nameController.text.trim().isEmpty && selectedFloor != null
                                  ? _generateRoomName(roomType, selectedFloor!, selectedFloor!.rooms)
                                  : nameController.text.trim();
                              if (roomName.isEmpty) return;
                              if (isNew) {
                                await ref.read(buildingProvider.notifier).addRoom(RoomModel(id: '', floorId: targetFloorId, name: roomName, roomType: roomType, capacity: int.tryParse(capacityController.text) ?? 30));
                              } else if (!isNew) {
                                await ref.read(buildingProvider.notifier).updateRoom(room!.id, RoomModel(id: room.id, floorId: targetFloorId, name: roomName, roomType: roomType, capacity: int.tryParse(capacityController.text) ?? 30));
                              }
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: Text(isNew ? 'Créer la salle' : 'Enregistrer', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6D4CF6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(String type, String id, String name) {
    final typeLabel = type == 'building'
        ? 'bâtiment'
        : type == 'floor'
        ? 'étage'
        : 'salle';

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: 420,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 50, offset: const Offset(0, 20)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: AppColors.slate100)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Confirmer la suppression', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            const Text('Cette action est irréversible', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(ctx),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.slate50),
                          child: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Voulez-vous vraiment supprimer le $typeLabel "$name" ?',
                          style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                    border: Border(top: BorderSide(color: AppColors.slate100)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 40,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF6B7280),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          child: const Text('Annuler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              switch (type) {
                                case 'building': await ref.read(buildingProvider.notifier).deleteBuilding(id); break;
                                case 'floor': await ref.read(buildingProvider.notifier).deleteFloor(id); break;
                                case 'room': await ref.read(buildingProvider.notifier).deleteRoom(id); break;
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                FeedbackPill.showSuccess(context, '$typeLabel "$name" supprimé');
                              }
                            } catch (e) {
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                FeedbackPill.showError(context, 'Impossible de supprimer $typeLabel "$name" : $e');
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Supprimer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
