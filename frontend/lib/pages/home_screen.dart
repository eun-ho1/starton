import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/pages/home/home_category_quest_dialog.dart';
import 'package:start_on/pages/home/home_screen_sections.dart';

// 홈 탭 전체 상태와 상위 액션 콜백을 연결하는 메인 화면 위젯입니다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.data,
    required this.userName,
    required this.onAddQuest,
    required this.onAddQuestForCategory,
    required this.onQuestTap,
    required this.onDeleteQuest,
    required this.onDeleteQuests,
    required this.onUserEnergyChanged,
    required this.onOpenSettings,
    required this.onTabChange,
  });

  final AppLocalData data;
  final String userName;
  final VoidCallback onAddQuest;
  final ValueChanged<String> onAddQuestForCategory;
  final ValueChanged<QuestItem> onQuestTap;
  final ValueChanged<QuestItem> onDeleteQuest;
  final ValueChanged<List<QuestItem>> onDeleteQuests;
  final ValueChanged<String> onUserEnergyChanged;
  final VoidCallback onOpenSettings;
  final ValueChanged<int> onTabChange;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  Timer? _creditVisibilityTimer;
  double _scrollOffset = 0;
  bool _isAtTop = true;
  bool _showCreditAmount = true;
  bool _bulkDeleteMode = false;
  final Set<String> _bulkDeleteQuestIds = <String>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _startCreditVisibilityTimer();
  }

  @override
  void dispose() {
    _creditVisibilityTimer?.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 오늘 날짜 기준으로 헤더 문구와 완료 퀘스트 목록을 계산합니다.
    final now = DateTime.now();
    final todayLabel = 'Today ${DateFormat('d MMMM').format(now)}';
    final pendingCategoryCounts = _categoryCounts(widget.data.quests);
    final completedCategoryCounts = _completedCategoryCounts(
      widget.data.completedQuests,
    );
    final todayCompletedQuests = _todayCompletedQuests(
      records: widget.data.completedQuests,
      now: now,
    );
    final totalTaskCount = widget.data.quests.length + todayCompletedQuests.length;
    final completionProgress = totalTaskCount == 0
        ? 0.0
        : todayCompletedQuests.length / totalTaskCount;
    final completedQuestRevealProgress = _completedQuestRevealProgress;

    // 상단 헤더, 카테고리, 퀘스트 목록, 완료 기록을 세로로 배치합니다.
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 118),
      children: [
        HomeHeaderSection(
          todayLabel: todayLabel,
          userName: widget.userName,
          credits: widget.data.credits,
          userEnergy: widget.data.userEnergy,
          completedTodayCount: todayCompletedQuests.length,
          totalTaskCount: totalTaskCount,
          completionProgress: completionProgress,
          showCreditAmount: _showCreditAmount,
          onEnergyTap: _openEnergyPicker,
          onOpenSettings: widget.onOpenSettings,
        ),
        const SizedBox(height: 12),
        HomeCategoryGrid(
          completedCategoryCounts: completedCategoryCounts,
          pendingCategoryCounts: pendingCategoryCounts,
          onCategoryTap: _openCategoryQuestDialog,
          onAddCategoryQuest: widget.onAddQuestForCategory,
        ),
        const SizedBox(height: 26),
        HomeQuestSectionHeader(
          questCount: widget.data.quests.length,
          quests: widget.data.quests,
          completedRecords: widget.data.completedQuests,
          bulkDeleteMode: _bulkDeleteMode,
          selectedDeleteCount: _bulkDeleteQuestIds.length,
          onToggleBulkDelete: _toggleBulkDeleteMode,
          onConfirmBulkDelete: _confirmBulkDelete,
          onCancelBulkDelete: _cancelBulkDelete,
        ),
        const SizedBox(height: 12),
        HomeQuestList(
          quests: widget.data.quests,
          onAddQuest: widget.onAddQuest,
          onQuestTap: widget.onQuestTap,
          onDeleteQuest: widget.onDeleteQuest,
          bulkDeleteMode: _bulkDeleteMode,
          selectedQuestIds: _bulkDeleteQuestIds,
          onToggleQuestSelection: _toggleQuestSelection,
        ),
        if (todayCompletedQuests.isNotEmpty) ...[
          const SizedBox(height: 8),
          if (completedQuestRevealProgress > 0)
            Align(
              alignment: Alignment.topCenter,
              child: Opacity(
                opacity: completedQuestRevealProgress,
                child: Transform.translate(
                  offset: Offset(0, (1 - completedQuestRevealProgress) * 18),
                  child: HomeCompletedQuestSection(
                    records: todayCompletedQuests,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  List<CompletedQuestRecord> _todayCompletedQuests({
    required List<CompletedQuestRecord> records,
    required DateTime now,
  }) {
    return records.where((item) {
      final completedAt = DateTime.tryParse(item.completedAt)?.toLocal();
      return completedAt != null &&
          completedAt.year == now.year &&
          completedAt.month == now.month &&
          completedAt.day == now.day;
    }).toList();
  }

  Map<String, int> _categoryCounts(List<QuestItem> quests) {
    final counts = <String, int>{'work': 0, 'life': 0, 'study': 0, 'home': 0};

    for (final quest in quests) {
      counts.update(quest.category, (value) => value + 1, ifAbsent: () => 1);
    }

    return counts;
  }

  Map<String, int> _completedCategoryCounts(
    List<CompletedQuestRecord> records,
  ) {
    final counts = <String, int>{'work': 0, 'life': 0, 'study': 0, 'home': 0};

    for (final record in records) {
      counts.update(record.category, (value) => value + 1, ifAbsent: () => 1);
    }

    return counts;
  }

  Future<void> _openCategoryQuestDialog(String category) async {
    final quests = widget.data.quests
        .where((item) => item.category == category)
        .toList();
    final completedRecords = widget.data.completedQuests
        .where((item) => item.category == category)
        .toList()
        .reversed
        .toList();
    final result = await showDialog<Object?>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (context) => HomeCategoryQuestDialog(
        category: category,
        quests: quests,
        completedRecords: completedRecords,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result case QuestItem selectedQuest) {
      widget.onQuestTap(selectedQuest);
      return;
    }

    if (result == 'add') {
      widget.onAddQuestForCategory(category);
    }
  }

  Future<void> _openEnergyPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _EnergyPickerSheet(currentEnergy: widget.data.userEnergy),
    );
    if (!mounted || selected == null || selected == widget.data.userEnergy) {
      return;
    }
    widget.onUserEnergyChanged(selected);
  }

  void _toggleBulkDeleteMode() {
    setState(() {
      _bulkDeleteMode = !_bulkDeleteMode;
      _bulkDeleteQuestIds.clear();
    });
  }

  void _cancelBulkDelete() {
    setState(() {
      _bulkDeleteMode = false;
      _bulkDeleteQuestIds.clear();
    });
  }

  void _toggleQuestSelection(QuestItem quest) {
    setState(() {
      if (!_bulkDeleteQuestIds.add(quest.id)) {
        _bulkDeleteQuestIds.remove(quest.id);
      }
    });
  }

  Future<void> _confirmBulkDelete() async {
    final selectedQuests = widget.data.quests
        .where((quest) => _bulkDeleteQuestIds.contains(quest.id))
        .toList();
    if (selectedQuests.isEmpty) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFF1F3F8),
        title: const Text('퀘스트 일괄 삭제'),
        content: Text('${selectedQuests.length}개의 퀘스트를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE55353)),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (!mounted || shouldDelete != true) {
      return;
    }

    widget.onDeleteQuests(selectedQuests);
    _cancelBulkDelete();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final nextOffset = _scrollController.offset < 0
        ? 0.0
        : _scrollController.offset;
    final isAtTop = nextOffset <= 0.5;

    if (isAtTop) {
      if (!_isAtTop) {
        _isAtTop = true;
        _creditVisibilityTimer?.cancel();
        setState(() {
          _scrollOffset = nextOffset;
          _showCreditAmount = true;
        });
        _startCreditVisibilityTimer();
        return;
      }

      if (_scrollOffset != nextOffset) {
        setState(() => _scrollOffset = nextOffset);
      }
      return;
    }

    _isAtTop = false;
    _creditVisibilityTimer?.cancel();
    if (_showCreditAmount || _scrollOffset != nextOffset) {
      setState(() {
        _scrollOffset = nextOffset;
        _showCreditAmount = false;
      });
    }
  }

  void _startCreditVisibilityTimer() {
    _creditVisibilityTimer?.cancel();
    _creditVisibilityTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      if (_scrollController.offset <= 0.5 && _showCreditAmount) {
        setState(() => _showCreditAmount = false);
      }
    });
  }

  double get _completedQuestRevealProgress {
    const startOffset = 36.0;
    const endOffset = 160.0;

    final rawProgress =
        ((_scrollOffset - startOffset) / (endOffset - startOffset)).clamp(
          0.0,
          1.0,
        );
    return Curves.easeOutCubic.transform(rawProgress);
  }
}

class _EnergyPickerSheet extends StatelessWidget {
  const _EnergyPickerSheet({required this.currentEnergy});

  final String currentEnergy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F8),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '현재 에너지 조정',
              style: TextStyle(
                color: Color(0xFF172033),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in const [
              ('low', '낮음', Icons.battery_1_bar_rounded),
              ('medium', '보통', Icons.battery_4_bar_rounded),
              ('high', '높음', Icons.battery_full_rounded),
            ]) ...[
              ListTile(
                onTap: () => Navigator.of(context).pop(item.$1),
                leading: Icon(item.$3, color: const Color(0xFF6F63FF)),
                title: Text(
                  item.$2,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: currentEnergy == item.$1
                    ? const Icon(Icons.check_rounded, color: Color(0xFF6F63FF))
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
