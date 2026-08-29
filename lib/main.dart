import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const appVersion = 'v0.6.8';
const seedExportDate = '2026-08-27 14:24';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('el_GR');
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    await windowManager.ensureInitialized();
    final preferences = await SharedPreferences.getInstance();
    final width = preferences.getDouble('window-width') ?? 1280;
    final height = preferences.getDouble('window-height') ?? 800;
    final savedX = preferences.getDouble('window-x');
    final savedY = preferences.getDouble('window-y');
    final options = WindowOptions(
      size: Size(width, height),
      minimumSize: const Size(900, 600),
      center: savedX == null || savedY == null,
      title: 'Financial App $appVersion',
    );
    windowManager.waitUntilReadyToShow(options, () async {
      if (savedX != null && savedY != null) {
        await windowManager.setPosition(Offset(savedX, savedY));
      }
      await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const FinancialApp());
}

class FinancialApp extends StatelessWidget {
  const FinancialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Financial App $appVersion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF159A9C),
          surface: const Color(0xFFF7F9FB),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9FB),
        fontFamily: 'Arial',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF102A43),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE5EAF0)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E0E8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD8E0E8)),
          ),
        ),
      ),
      home: const FinanceHomePage(),
    );
  }
}

class Transaction {
  const Transaction({
    required this.account,
    required this.flag,
    required this.date,
    required this.payee,
    required this.category,
    required this.categoryGroup,
    required this.memo,
    required this.outflow,
    required this.inflow,
    required this.cleared,
  });

  final String account;
  final String flag;
  final DateTime date;
  final String payee;
  final String category;
  final String categoryGroup;
  final String memo;
  final double outflow;
  final double inflow;
  final String cleared;

  double get net => inflow - outflow;

  Transaction copyWith({
    String? cleared,
    String? flag,
    DateTime? date,
    String? memo,
    String? payee,
    String? category,
    String? categoryGroup,
    double? outflow,
    double? inflow,
  }) => Transaction(
    account: account,
    date: date ?? this.date,
    payee: payee ?? this.payee,
    category: category ?? this.category,
    categoryGroup: categoryGroup ?? this.categoryGroup,
    memo: memo ?? this.memo,
    outflow: outflow ?? this.outflow,
    inflow: inflow ?? this.inflow,
    cleared: cleared ?? this.cleared,
    flag: flag ?? this.flag,
  );
}

class NetWorthPoint {
  const NetWorthPoint({
    required this.month,
    required this.assets,
    required this.debts,
    required this.netWorth,
  });

  final DateTime month;
  final double assets;
  final double debts;
  final double netWorth;
}

enum AccountType {
  liquid,
  creditCard,
  investment,
  asset,
  personalDebts,
  inactive,
}

const accountTypeOrder = [
  AccountType.liquid,
  AccountType.creditCard,
  AccountType.investment,
  AccountType.asset,
  AccountType.personalDebts,
  AccountType.inactive,
];

AccountType classifyAccount(String account) {
  final name = account.toLowerCase();
  if (name.contains('diners') ||
      name.contains('highlow') ||
      name.contains('neteller') ||
      name == '3. εμπορική' ||
      name == 'εθνική' ||
      name == 'σπίτι 2' ||
      name == 'tdm900') {
    return AccountType.inactive;
  }
  if (name == 'δανεικά') return AccountType.personalDebts;
  if (name.contains('prepaid')) return AccountType.creditCard;
  if (name.contains('visa')) {
    return AccountType.creditCard;
  }
  if (name.contains('degiro')) {
    return AccountType.investment;
  }
  if (name.contains('kawasaki') ||
      name.contains('tdm900') ||
      name.contains('διαμέρισμα') ||
      name == 'σπίτι 2') {
    return AccountType.asset;
  }
  return AccountType.liquid;
}

String accountTypeLabel(AccountType type) => switch (type) {
  AccountType.liquid => 'Ρευστά & Καταθέσεις',
  AccountType.creditCard => 'Πιστωτικές Κάρτες',
  AccountType.investment => 'Επενδύσεις',
  AccountType.asset => 'Περιουσιακά Στοιχεία',
  AccountType.personalDebts => 'Δανεικά & Ιδιωτικές Οφειλές',
  AccountType.inactive => 'Μη Ενεργά',
};

IconData accountTypeIcon(AccountType type) => switch (type) {
  AccountType.liquid => Icons.account_balance,
  AccountType.creditCard => Icons.credit_card,
  AccountType.investment => Icons.trending_up,
  AccountType.asset => Icons.home_work_outlined,
  AccountType.personalDebts => Icons.people_outline,
  AccountType.inactive => Icons.archive_outlined,
};

Color accountTypeColor(AccountType type) => switch (type) {
  AccountType.liquid => const Color(0xFF159A9C),
  AccountType.creditCard => const Color(0xFFD45D4C),
  AccountType.investment => const Color(0xFF356AE6),
  AccountType.asset => const Color(0xFF8A5A44),
  AccountType.personalDebts => const Color(0xFF8A63B8),
  AccountType.inactive => const Color(0xFF718096),
};

String uppercaseWithoutGreekTones(String value) {
  const replacements = {
    'Ά': 'Α',
    'Έ': 'Ε',
    'Ή': 'Η',
    'Ί': 'Ι',
    'Ό': 'Ο',
    'Ύ': 'Υ',
    'Ώ': 'Ω',
    'ά': 'α',
    'έ': 'ε',
    'ή': 'η',
    'ί': 'ι',
    'ό': 'ο',
    'ύ': 'υ',
    'ώ': 'ω',
  };
  var result = value;
  for (final entry in replacements.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result.toUpperCase();
}

class FinanceHomePage extends StatefulWidget {
  const FinanceHomePage({super.key});

  @override
  State<FinanceHomePage> createState() => _FinanceHomePageState();
}

class _FinanceHomePageState extends State<FinanceHomePage> with WindowListener {
  final _currency = NumberFormat.currency(locale: 'el_GR', symbol: '€');
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _searchController = TextEditingController();
  List<Transaction> _transactions = const [];
  int _section = 0;
  String? _selectedAccount;
  String? _selectedCategory;
  bool _loading = false;
  String? _error;
  int _reportMode = 0;
  int? _hoveredNetWorthIndex;
  final Set<AccountType> _collapsedGroups = {};
  bool _futureTransactionsCollapsed = false;
  List<double> _columnWidths = [34, 34, 120, 220, 180, 220, 110, 110, 90];
  final Set<Transaction> _selectedTransactions = {};
  final Map<Transaction, Uint8List> _transactionImages = {};
  Transaction? _editingOriginal;
  Transaction? _editingDraft;
  List<Transaction>? _editingSplitDraft;
  List<Transaction>? _editingSplitOriginal;
  String? _editingSplitKey;
  final Set<String> _collapsedSplits = {};
  int _transactionSortColumn = 0;
  bool _transactionSortAscending = false;
  double _sidebarWidth = 300;
  Timer? _windowSaveTimer;

  @override
  void initState() {
    super.initState();
    _loadSeedRegister();
    _loadCollapsedGroups();
    _loadSidebarWidth();
    _loadColumnWidths();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      windowManager.addListener(this);
    }
  }

  Future<void> _loadSidebarWidth() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final width = preferences.getDouble('sidebar-width');
      if (!mounted || width == null) return;
      setState(() => _sidebarWidth = width.clamp(220, 420));
    } catch (_) {}
  }

  Future<void> _setSidebarWidth(double width) async {
    final clamped = width.clamp(220, 420).toDouble();
    setState(() => _sidebarWidth = clamped);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble('sidebar-width', clamped);
  }

  Future<void> _loadColumnWidths() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getStringList('transaction-column-widths');
      if (!mounted || saved == null || saved.length != _columnWidths.length) {
        return;
      }
      final widths = saved.map(double.parse).toList();
      setState(() => _columnWidths = widths);
    } catch (_) {}
  }

  Future<void> _setColumnWidth(int index, double width) async {
    final widths = [..._columnWidths];
    final minimum = index < 2 ? 34.0 : 80.0;
    widths[index] = width.clamp(minimum, 420).toDouble();
    setState(() => _columnWidths = widths);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      'transaction-column-widths',
      widths.map((value) => value.toString()).toList(),
    );
  }

  Future<void> _pickTransactionImage(Transaction transaction) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
    );
    final bytes = result.isEmpty ? null : await result.single.readAsBytes();
    if (bytes == null || !mounted) return;
    setState(() => _transactionImages[transaction] = bytes);
  }

  void _scheduleWindowSave() {
    _windowSaveTimer?.cancel();
    _windowSaveTimer = Timer(
      const Duration(milliseconds: 400),
      _saveWindowGeometry,
    );
  }

  Future<void> _saveWindowGeometry() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setDouble('window-width', size.width);
      await preferences.setDouble('window-height', size.height);
      await preferences.setDouble('window-x', position.dx);
      await preferences.setDouble('window-y', position.dy);
    } catch (_) {}
  }

  @override
  void onWindowResized() => _scheduleWindowSave();

  @override
  void onWindowMoved() => _scheduleWindowSave();

  @override
  void onWindowClose() => _saveWindowGeometry();

  Future<void> _loadCollapsedGroups() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        for (final type in accountTypeOrder) {
          if (preferences.getBool('account-group-collapsed-${type.name}') ??
              false) {
            _collapsedGroups.add(type);
          }
        }
        _futureTransactionsCollapsed =
            preferences.getBool('future-transactions-collapsed') ?? false;
      });
    } catch (_) {
      // Persistence is optional in test runners without native plugins.
    }
  }

  Future<void> _setGroupCollapsed(AccountType type, bool collapsed) async {
    setState(() {
      if (collapsed) {
        _collapsedGroups.add(type);
      } else {
        _collapsedGroups.remove(type);
      }
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      'account-group-collapsed-${type.name}',
      collapsed,
    );
  }

  Future<void> _setFutureTransactionsCollapsed(bool collapsed) async {
    setState(() => _futureTransactionsCollapsed = collapsed);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('future-transactions-collapsed', collapsed);
  }

  @override
  void dispose() {
    _windowSaveTimer?.cancel();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      windowManager.removeListener(this);
    }
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _accounts =>
      _transactions.map((t) => t.account).toSet().toList()..sort();

  List<String> get _categories =>
      _transactions
          .map(
            (t) => t.categoryGroup.isEmpty
                ? t.category
                : '${t.categoryGroup}: ${t.category}',
          )
          .where((value) => value.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  List<Transaction> get _filteredTransactions {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _transactions.where((transaction) {
      final category = transaction.categoryGroup.isEmpty
          ? transaction.category
          : '${transaction.categoryGroup}: ${transaction.category}';
      final matchesSearch =
          query.isEmpty ||
          '${transaction.payee} ${transaction.memo} $category ${transaction.account}'
              .toLowerCase()
              .contains(query);
      final matchesAccount =
          _selectedAccount == null || transaction.account == _selectedAccount;
      final matchesCategory =
          _selectedCategory == null || category == _selectedCategory;
      return matchesSearch && matchesAccount && matchesCategory;
    }).toList();
    filtered.sort((first, second) {
      final comparison = _compareTransactions(
        first,
        second,
        _transactionSortColumn,
      );
      return _transactionSortAscending ? comparison : -comparison;
    });
    return filtered;
  }

  int _compareTransactions(Transaction first, Transaction second, int column) {
    int compareText(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());
    switch (column) {
      case 2:
        return first.date.compareTo(second.date);
      case 3:
        return compareText(first.payee, second.payee);
      case 4:
        return compareText(first.category, second.category);
      case 5:
        return compareText(first.memo, second.memo);
      case 6:
        return first.outflow.compareTo(second.outflow);
      case 7:
        return first.inflow.compareTo(second.inflow);
      case 8:
        int statusRank(String status) => switch (status.toLowerCase()) {
          'uncleared' => 0,
          'cleared' => 1,
          'reconciled' => 2,
          _ => -1,
        };
        return statusRank(first.cleared).compareTo(statusRank(second.cleared));
      default:
        return 0;
    }
  }

  void _sortTransactions(int column, bool ascending) {
    setState(() {
      _transactionSortColumn = column;
      _transactionSortAscending = ascending;
    });
  }

  void _setTransactionSelected(Transaction transaction, bool selected) {
    setState(() {
      if (selected) {
        _selectedTransactions.add(transaction);
      } else {
        _selectedTransactions.remove(transaction);
      }
    });
  }

  void _clearSelection() => setState(_selectedTransactions.clear);

  void _setSplitSelected(
    List<Transaction> transactions,
    bool selected,
  ) {
    setState(() {
      if (selected) {
        _selectedTransactions.addAll(transactions);
      } else {
        _selectedTransactions.removeAll(transactions);
      }
    });
  }

  void _setSplitCollapsed(String key, bool collapsed) {
    setState(() {
      if (collapsed) {
        _collapsedSplits.add(key);
      } else {
        _collapsedSplits.remove(key);
      }
    });
  }

  Set<String> get _splitKeys {
    final pattern = RegExp(r'^Split \(\d+/\d+\)\s*(.*)$');
    final counts = <String, int>{};
    for (final transaction in _transactions) {
      final match = pattern.firstMatch(transaction.memo);
      if (match == null) continue;
      final baseMemo = match.group(1)!.trim();
      final key =
          '${transaction.date.year}-${transaction.date.month}-'
          '${transaction.date.day}|${transaction.account}|$baseMemo';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toSet();
  }

  void _toggleAllSplits() {
    final keys = _splitKeys;
    if (keys.isEmpty) return;
    final collapse = keys.any((key) => !_collapsedSplits.contains(key));
    setState(() {
      if (collapse) {
        _collapsedSplits.addAll(keys);
      } else {
        _collapsedSplits.removeAll(keys);
      }
    });
  }

  Future<void> _showTransactionMenu(
    Offset position,
    Transaction transaction,
    List<Transaction>? splitParts,
  ) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        MediaQuery.sizeOf(context).width - position.dx,
        MediaQuery.sizeOf(context).height - position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!mounted) return;
    if (choice == 'duplicate') {
      await _duplicateTransaction(transaction, splitParts);
    } else if (choice == 'delete') {
      await _deleteTransaction(transaction, splitParts);
    }
  }

  Future<void> _duplicateTransaction(
    Transaction transaction,
    List<Transaction>? splitParts,
  ) async {
    final parts = splitParts ?? [transaction];
    final initialAmount = parts.fold<double>(
      0,
      (sum, item) => sum + item.outflow + item.inflow,
    );
    final date = await showDatePicker(
      context: context,
      initialDate: transaction.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final amountController = TextEditingController(
      text: initialAmount.toStringAsFixed(2),
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Duplicate transaction'),
        content: TextField(
          controller: amountController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'New amount'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(amountController.text.replaceAll(',', '.')),
            ),
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );
    amountController.dispose();
    if (amount == null || amount < 0 || !mounted) return;
    final targetCents = (amount * 100).round();
    final initialCents = (initialAmount * 100).round();
    var assignedCents = 0;
    final duplicates = <Transaction>[];
    for (var index = 0; index < parts.length; index++) {
      final item = parts[index];
      final itemCents = ((item.outflow + item.inflow) * 100).round();
      final cents = index == parts.length - 1
          ? targetCents - assignedCents
          : initialCents == 0
          ? 0
          : (itemCents * targetCents / initialCents).round();
      assignedCents += cents;
      final itemAmount = cents / 100;
      duplicates.add(
        item.copyWith(
          date: date,
          memo: _memoWithTotal(item.memo, amount),
          outflow: item.outflow > 0 ? itemAmount : 0,
          inflow: item.inflow > 0 ? itemAmount : 0,
        ),
      );
    }
    setState(() => _transactions.addAll(duplicates));
  }

  String _memoWithTotal(String memo, double amount) {
    final formatted = amount.toStringAsFixed(2).replaceAll('.', ',');
    final totalPattern = RegExp(r'ΣΥΝΟΛΟ\s*:\s*[-+]?\d+(?:[.,]\d+)?',
        caseSensitive: false);
    if (totalPattern.hasMatch(memo)) {
      return memo.replaceFirst(totalPattern, 'ΣΥΝΟΛΟ: $formatted');
    }
    final trimmed = memo.trim();
    return trimmed.isEmpty
        ? 'ΣΥΝΟΛΟ: $formatted'
        : '$trimmed - ΣΥΝΟΛΟ: $formatted';
  }

  Future<void> _deleteTransaction(
    Transaction transaction,
    List<Transaction>? splitParts,
  ) async {
    final parts = splitParts ?? [transaction];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          parts.length > 1
              ? 'This will delete all ${parts.length} split parts.'
              : 'This transaction will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _transactions.removeWhere(parts.contains));
  }

  Future<void> _editTransaction(Transaction transaction) async {
    DateTime editDate = transaction.date;
    final payee = TextEditingController(text: transaction.payee);
    final memo = TextEditingController(text: transaction.memo);
    final amount = TextEditingController(
      text: (transaction.outflow + transaction.inflow).toStringAsFixed(2),
    );
    final edited = await showDialog<Transaction>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(DateFormat('dd/MM/yyyy').format(editDate)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: editDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialogState(() => editDate = picked);
                  },
                ),
                TextField(controller: payee, decoration: const InputDecoration(labelText: 'Payee')),
                TextField(controller: memo, decoration: const InputDecoration(labelText: 'Memo')),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text.replaceAll(',', '.'));
                if (value == null || value < 0) return;
                Navigator.pop(
                  dialogContext,
                  transaction.copyWith(
                    date: editDate,
                    payee: payee.text,
                    memo: memo.text,
                    outflow: transaction.outflow > 0 ? value : 0,
                    inflow: transaction.inflow > 0 ? value : 0,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    payee.dispose();
    memo.dispose();
    amount.dispose();
    if (edited == null || !mounted) return;
    final index = _transactions.indexOf(transaction);
    if (index >= 0) setState(() => _transactions[index] = edited);
  }

  void _beginInlineEdit(Transaction transaction, [String? splitKey]) {
    final splitParts = splitKey == null
        ? null
        : _transactions.where((item) {
            final match = RegExp(r'^Split \(\d+/\d+\)\s*(.*)$').firstMatch(item.memo);
            if (match == null) return false;
            final baseMemo = match.group(1)!.trim();
            final key =
                '${item.date.year}-${item.date.month}-${item.date.day}|'
                '${item.account}|$baseMemo';
            return key == splitKey;
          }).toList();
    setState(() {
      _editingOriginal = transaction;
      _editingDraft = transaction;
      _editingSplitOriginal = splitParts;
      _editingSplitDraft = null;
      _editingSplitKey = splitKey;
    });
  }

  void _updateInlineEdit(Transaction transaction) {
    if (_editingSplitOriginal != null && transaction != _editingDraft) {
      final parts = [...(_editingSplitDraft ?? _editingSplitOriginal!)];
      final prefix = RegExp(r'^Split \((\d+)/\d+\)').firstMatch(transaction.memo);
      final index = prefix == null ? -1 : int.parse(prefix.group(1)!) - 1;
      if (index >= 0 && index < parts.length) {
        parts[index] = transaction;
        _editingSplitDraft = parts;
        return;
      }
    }
    _editingDraft = transaction;
  }

  void _updateInlineSplitAmount(List<Transaction> parts, double amount) {
    _editingSplitOriginal = parts;
    final totalCents = (amount.abs() * 100).round();
    final weights = parts
        .map((part) => ((part.outflow + part.inflow) * 100).round())
        .toList();
    final weightTotal = weights.fold<int>(0, (sum, value) => sum + value);
    var assigned = 0;
    final updated = <Transaction>[];
    for (var index = 0; index < parts.length; index++) {
      final cents = index == parts.length - 1
          ? totalCents - assigned
          : weightTotal == 0
          ? 0
          : (weights[index] * totalCents / weightTotal).round();
      assigned += cents;
      final value = cents / 100;
      updated.add(
        parts[index].copyWith(
          outflow: amount >= 0 ? value : 0,
          inflow: amount < 0 ? value : 0,
        ),
      );
    }
    _editingDraft = _editingDraft == null
        ? null
        : _editingDraft!.copyWith(
            outflow: amount >= 0 ? amount : 0,
            inflow: amount < 0 ? amount.abs() : 0,
          );
    _editingSplitDraft = updated;
  }

  void _addInlineSplit() {
    final original = _editingSplitOriginal;
    if (original == null || original.isEmpty) return;
    final parts = _editingSplitDraft ?? original;
    final first = parts.first;
    final next = Transaction(
      account: first.account,
      flag: '',
      date: first.date,
      payee: first.payee,
      category: '',
      categoryGroup: '',
      memo: '',
      outflow: 0,
      inflow: 0,
      cleared: first.cleared,
    );
    final updated = [...parts, next];
    final baseMemo = parts
        .map((part) => _displaySplitMemo(part.memo))
        .firstWhere((memo) => memo.isNotEmpty, orElse: () => '');
    _editingSplitDraft = [
      for (var index = 0; index < updated.length; index++)
        updated[index].copyWith(
          memo: 'Split (${index + 1}/${updated.length})${baseMemo.isEmpty ? '' : ' $baseMemo'}',
        ),
    ];
    setState(() {});
  }

  void _cancelInlineEdit() {
    setState(() {
      _editingOriginal = null;
      _editingDraft = null;
      _editingSplitDraft = null;
      _editingSplitOriginal = null;
      _editingSplitKey = null;
    });
  }

  void _saveInlineEdit() {
    final original = _editingOriginal;
    final draft = _editingDraft;
    if (original == null || draft == null) return;
    setState(() {
      if (_editingSplitDraft != null && _editingSplitOriginal != null) {
        _transactions.removeWhere(_editingSplitOriginal!.contains);
        _transactions.addAll(_editingSplitDraft!);
      } else {
        final index = _transactions.indexOf(original);
        if (index >= 0) _transactions[index] = draft;
      }
      _editingOriginal = null;
      _editingDraft = null;
      _editingSplitDraft = null;
      _editingSplitOriginal = null;
      _editingSplitKey = null;
    });
  }

  void _cycleFlag(Transaction transaction) {
    const flags = ['', 'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Purple'];
    final current = flags.indexOf(transaction.flag);
    final next = flags[(current < 0 ? 0 : current + 1) % flags.length];
    final index = _transactions.indexOf(transaction);
    if (index < 0) return;
    setState(() => _transactions[index] = transaction.copyWith(flag: next));
  }

  double get _totalInflow =>
      _transactions.fold(0, (sum, item) => sum + item.inflow);
  double get _totalOutflow =>
      _transactions.fold(0, (sum, item) => sum + item.outflow);
  double get _netChange => _totalInflow - _totalOutflow;

  Map<String, double> get _accountBalances {
    final balances = <String, double>{};
    for (final transaction in _transactions) {
      if (transaction.date.isAfter(DateTime.now())) continue;
      balances.update(
        transaction.account,
        (value) => value + transaction.net,
        ifAbsent: () => transaction.net,
      );
    }
    return balances;
  }

  Map<AccountType, List<MapEntry<String, double>>> get _groupedBalances {
    final grouped = <AccountType, List<MapEntry<String, double>>>{};
    for (final entry in _accountBalances.entries) {
      final type = classifyAccount(entry.key);
      grouped.putIfAbsent(type, () => []).add(entry);
    }
    for (final entries in grouped.values) {
      entries.sort((a, b) => _compareAccounts(a.key, b.key));
    }
    return grouped;
  }

  int _compareAccounts(String first, String second) {
    final firstType = classifyAccount(first);
    final secondType = classifyAccount(second);
    if (firstType == AccountType.creditCard &&
        secondType == AccountType.creditCard) {
      const prepaidName = 'εθνική prepaid';
      final firstIsPrepaid = first.toLowerCase() == prepaidName;
      final secondIsPrepaid = second.toLowerCase() == prepaidName;
      if (firstIsPrepaid != secondIsPrepaid) {
        return firstIsPrepaid ? 1 : -1;
      }
    }
    if (firstType == AccountType.liquid && secondType == AccountType.liquid) {
      final firstName = first.toLowerCase();
      final secondName = second.toLowerCase();
      const priority = {'πορτοφόλι': 0, 'σπίτι': 1};
      final firstPriority = priority[firstName];
      final secondPriority = priority[secondName];
      if (firstPriority != null || secondPriority != null) {
        return (firstPriority ?? 2).compareTo(secondPriority ?? 2);
      }
      final firstMatch = RegExp(r'^(\d+)\.').firstMatch(firstName);
      final secondMatch = RegExp(r'^(\d+)\.').firstMatch(secondName);
      if (firstMatch != null || secondMatch != null) {
        if (firstMatch == null) return 1;
        if (secondMatch == null) return -1;
        final numberOrder = int.parse(
          firstMatch.group(1)!,
        ).compareTo(int.parse(secondMatch.group(1)!));
        if (numberOrder != 0) return numberOrder;
      }
    }
    return first.toLowerCase().compareTo(second.toLowerCase());
  }

  Map<String, double> get _categoryOutflows {
    final values = <String, double>{};
    for (final transaction in _transactions) {
      if (transaction.outflow == 0) continue;
      final name = transaction.categoryGroup.isEmpty
          ? (transaction.category.isEmpty
                ? 'Χωρίς κατηγορία'
                : transaction.category)
          : transaction.categoryGroup;
      values.update(
        name,
        (value) => value + transaction.outflow,
        ifAbsent: () => transaction.outflow,
      );
    }
    return values;
  }

  List<NetWorthPoint> get _netWorthPoints {
    final relevant = _transactions.where((transaction) {
      return !transaction.date.isAfter(DateTime.now());
    }).toList();
    if (relevant.isEmpty) return const [];
    relevant.sort((a, b) => a.date.compareTo(b.date));
    DateTime monthOf(DateTime date) => DateTime(date.year, date.month);
    final firstMonth = monthOf(relevant.first.date);
    final lastMonth = monthOf(DateTime.now());
    final monthlyChanges = <DateTime, List<Transaction>>{};
    for (final transaction in relevant) {
      monthlyChanges.putIfAbsent(monthOf(transaction.date), () => []).add(
        transaction,
      );
    }

    // Rebuild each account's balance first. This preserves Starting Balance
    // rows and prevents unrelated accounts from masking negative balances.
    final balances = <String, double>{};
    final points = <NetWorthPoint>[];
    for (
      var month = firstMonth;
      !month.isAfter(lastMonth);
      month = DateTime(month.year, month.month + 1)
    ) {
      for (final transaction in monthlyChanges[month] ?? const []) {
        balances.update(
          transaction.account,
          (value) => value + transaction.net,
          ifAbsent: () => transaction.net,
        );
      }

      var assets = 0.0;
      var debts = 0.0;
      for (final entry in balances.entries) {
        // YNAB's All Accounts Net Worth includes receivables and inactive
        // accounts too; the sign of the reconstructed balance determines
        // whether it is an asset or a debt.
        assets += math.max(0, entry.value);
        debts += math.max(0, -entry.value);
      }
      points.add(
        NetWorthPoint(
          month: month,
          assets: assets,
          debts: debts,
          netWorth: assets - debts,
        ),
      );
    }
    return points;
  }

  Future<void> _importRegister() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (file == null) {
        setState(() => _loading = false);
        return;
      }
      final text = _registerFromZip(await file.readAsBytes());
      final imported = _parseRegister(text);
      final preferences = await SharedPreferences.getInstance();
      final importedExportDate = _exportDateFromFileName(file.name);
      final currentExportDate = _parseExportDate(
        preferences.getString('imported-export-date') ?? seedExportDate,
      );
      if (importedExportDate != null &&
          currentExportDate != null &&
          importedExportDate.isBefore(currentExportDate)) {
        setState(() {
          _loading = false;
          _error =
              'Το ZIP είναι παλαιότερο από τα ήδη φορτωμένα δεδομένα '
              '(${_formatExportDate(currentExportDate)}). Δεν έγινε αντικατάσταση.';
        });
        return;
      }
      await preferences.setString('imported-register-csv', text);
      if (importedExportDate != null) {
        await preferences.setString(
          'imported-export-date',
          _formatExportDate(importedExportDate),
        );
      }
      setState(() {
        _transactions = imported;
        _loading = false;
        _selectedAccount = _firstAccount(imported);
        _selectedCategory = null;
        _section = 1;
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = 'Αποτυχία εισαγωγής ZIP: $error';
      });
    }
  }

  Future<void> _loadSeedRegister() async {
    try {
      final seedText = await rootBundle.loadString('data/private/register.csv');
      final seedImported = _parseRegister(seedText);
      if (!mounted) return;
      setState(() {
        _transactions = seedImported;
        _selectedAccount = _firstAccount(seedImported);
        _section = 1;
      });

      String? text;
      try {
        final preferences = await SharedPreferences.getInstance();
        text = preferences.getString('imported-register-csv');
      } catch (_) {
        // Native persistence is unavailable in widget tests and web fallback.
      }
      if (text == null) return;
      final imported = _parseRegister(text);
      if (!mounted) return;
      setState(() {
        _transactions = imported;
        _selectedAccount = _firstAccount(imported);
        _section = 1;
      });
    } catch (error) {
      debugPrint('Seed register load failed: $error');
      // The private seed is intentionally optional for other machines.
    }
  }

  String _registerFromZip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final register = archive.files.where((file) {
      return file.isFile &&
          file.name.toLowerCase().endsWith('register.csv');
    }).firstOrNull;
    if (register == null) {
      throw const FormatException('Το ZIP δεν περιέχει Register.csv.');
    }
    return utf8.decode(register.content);
  }

  String? _firstAccount(List<Transaction> transactions) {
    final accounts = transactions.map((t) => t.account).toSet().toList()
      ..sort((first, second) {
        final firstGroup = accountTypeOrder.indexOf(classifyAccount(first));
        final secondGroup = accountTypeOrder.indexOf(classifyAccount(second));
        if (firstGroup != secondGroup) return firstGroup.compareTo(secondGroup);
        return _compareAccounts(first, second);
      });
    return accounts.isEmpty ? null : accounts.first;
  }

  DateTime? _exportDateFromFileName(String fileName) {
    final match = RegExp(
      r'as of (\d{4}-\d{2}-\d{2}) (\d{2})-(\d{2})',
      caseSensitive: false,
    ).firstMatch(fileName);
    if (match == null) return null;
    return _parseExportDate(
      '${match.group(1)} ${match.group(2)}:${match.group(3)}',
    );
  }

  DateTime? _parseExportDate(String value) {
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parseStrict(value);
    } catch (_) {
      return null;
    }
  }

  String _formatExportDate(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm').format(value);

  List<Transaction> _parseRegister(String rawText) {
    final text = rawText.replaceFirst('\uFEFF', '');
    final rows = Csv().decode(text);
    if (rows.isEmpty) {
      throw const FormatException('Το αρχείο δεν περιέχει γραμμές.');
    }
    final headers = rows.first.map((value) => value.toString().trim()).toList();
    final index = {for (var i = 0; i < headers.length; i++) headers[i]: i};
    const required = [
      'Account',
      'Date',
      'Payee',
      'Category Group',
      'Category',
      'Memo',
      'Outflow',
      'Inflow',
      'Cleared',
    ];
    final missing = required
        .where((header) => !index.containsKey(header))
        .toList();
    if (missing.isNotEmpty) {
      throw FormatException('Δεν βρέθηκαν οι στήλες: ${missing.join(', ')}');
    }
    String value(List<dynamic> row, String key) =>
        row[index[key]!].toString().trim();
    final imported = <Transaction>[];
    for (final row in rows.skip(1)) {
      if (row.length < headers.length) {
        continue;
      }
      final date = _parseDate(value(row, 'Date'));
      if (date == null) continue;
      imported.add(
        Transaction(
          account: value(row, 'Account'),
          flag: value(row, 'Flag'),
          date: date,
          payee: value(row, 'Payee'),
          category: value(row, 'Category'),
          categoryGroup: value(row, 'Category Group'),
          memo: value(row, 'Memo'),
          outflow: _parseMoney(value(row, 'Outflow')),
          inflow: _parseMoney(value(row, 'Inflow')),
          cleared: value(row, 'Cleared'),
        ),
      );
    }
    imported.sort((a, b) => b.date.compareTo(a.date));
    return imported;
  }

  DateTime? _parseDate(String value) {
    for (final pattern in ['dd/MM/yyyy', 'd/M/yyyy', 'yyyy-MM-dd']) {
      try {
        return DateFormat(pattern).parseStrict(value);
      } catch (_) {}
    }
    return null;
  }

  double _parseMoney(String value) {
    var normalized = value.replaceAll('€', '').replaceAll(' ', '').trim();
    if (normalized.isEmpty) return 0;
    normalized = normalized.replaceAll(',', '');
    return double.tryParse(normalized) ?? 0;
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedAccount = null;
      _selectedCategory = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: wide ? null : AppBar(title: const Text('Financial App')),
      drawer: wide
          ? null
          : Drawer(
              child: _Navigation(
                selected: _section,
                selectedAccount: _selectedAccount,
                balances: _groupedBalances,
                collapsedGroups: _collapsedGroups,
                sidebarWidth: _sidebarWidth,
                onSelect: _selectSection,
                onAccountSelect: _selectAccount,
                onToggleGroup: (type, collapsed) =>
                    _setGroupCollapsed(type, collapsed),
                onWidthChanged: _setSidebarWidth,
              ),
            ),
      body: Row(
        children: [
          if (wide)
            _Navigation(
              selected: _section,
              selectedAccount: _selectedAccount,
              balances: _groupedBalances,
              collapsedGroups: _collapsedGroups,
              sidebarWidth: _sidebarWidth,
              onSelect: _selectSection,
              onAccountSelect: _selectAccount,
              onToggleGroup: (type, collapsed) =>
                  _setGroupCollapsed(type, collapsed),
              onWidthChanged: _setSidebarWidth,
            ),
          Expanded(child: _buildContent(wide)),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _section,
              onDestinationSelected: _selectSection,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Επισκόπηση',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Συναλλαγές',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: 'Reports',
                ),
              ],
            ),
    );
  }

  void _selectSection(int index) {
    Navigator.maybePop(context);
    setState(() => _section = index);
  }

  void _selectAccount(String account) {
    Navigator.maybePop(context);
    setState(() {
      _section = 1;
      _selectedAccount = account;
      _selectedCategory = null;
      _searchController.clear();
    });
  }

  void _toggleTransactionCleared(Transaction transaction) {
    if (transaction.cleared.toLowerCase() == 'reconciled') return;
    final index = _transactions.indexOf(transaction);
    if (index < 0) return;
    final nextStatus = transaction.cleared.toLowerCase() == 'cleared'
        ? 'Uncleared'
        : 'Cleared';
    setState(() {
      _transactions[index] = transaction.copyWith(cleared: nextStatus);
    });
  }

  Widget _buildContent(bool wide) {
    final showHeader = !(_section == 2 && _reportMode == 1) &&
        !(_section == 1 && _selectedAccount != null);
    return CustomScrollView(
      slivers: [
        if (showHeader)
          SliverToBoxAdapter(
            child: _Header(onImport: _importRegister, loading: _loading),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(wide ? 38 : 18, 24, wide ? 38 : 18, 32),
          sliver: SliverToBoxAdapter(
            child: _section == 0
                ? _buildDashboard()
                : _section == 1
                ? _buildTransactions()
                : _buildReports(),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard() {
    if (_transactions.isEmpty) return _EmptyState(onImport: _importRegister);
    final groupedBalances = _groupedBalances;
    final accountCount = _accountBalances.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(
          title: 'Επισκόπηση',
          subtitle: 'Η συνολική εικόνα των οικονομικών σου.',
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 800 ? 3 : 1;
            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: columns == 1 ? 3.2 : 1.65,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _MetricCard(
                  label: 'Καθαρή μεταβολή',
                  value: _currency.format(_netChange),
                  icon: Icons.account_balance_wallet_outlined,
                  color: const Color(0xFF159A9C),
                ),
                _MetricCard(
                  label: 'Συνολικές εισροές',
                  value: _currency.format(_totalInflow),
                  icon: Icons.arrow_downward_rounded,
                  color: const Color(0xFF2D8A5F),
                ),
                _MetricCard(
                  label: 'Συνολικές εκροές',
                  value: _currency.format(_totalOutflow),
                  icon: Icons.arrow_upward_rounded,
                  color: const Color(0xFFD45D4C),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),
        _SectionHeading(
          title: 'Οικονομικές κατηγορίες',
          action: '$accountCount λογαριασμοί',
        ),
        const SizedBox(height: 12),
        ...accountTypeOrder
            .where((type) => groupedBalances[type]?.isNotEmpty ?? false)
            .map(
              (type) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _AccountGroupCard(
                  type: type,
                  entries: groupedBalances[type]!,
                  collapsed: _collapsedGroups.contains(type),
                  onToggle: (collapsed) => _setGroupCollapsed(type, collapsed),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildTransactions() {
    if (_selectedAccount != null) return _buildAccountPage();
    final transactions = _filteredTransactions;
    final futureTransactions = transactions
        .where((transaction) => transaction.date.isAfter(DateTime.now()))
        .toList();
    final pastTransactions = transactions
        .where((transaction) => !transaction.date.isAfter(DateTime.now()))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(
          title: 'Συναλλαγές',
          subtitle: 'Αναζήτηση και έλεγχος του ιστορικού σου.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Αναζήτηση...',
                ),
              ),
            ),
            _FilterDropdown(
              label: 'Λογαριασμός',
              value: _selectedAccount,
              values: _accounts,
              onChanged: (value) => setState(() => _selectedAccount = value),
            ),
            _FilterDropdown(
              label: 'Κατηγορία',
              value: _selectedCategory,
              values: _categories,
              onChanged: (value) => setState(() => _selectedCategory = value),
            ),
            if (_searchController.text.isNotEmpty ||
                _selectedAccount != null ||
                _selectedCategory != null)
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear),
                label: const Text('Καθαρισμός'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (_error != null) _ErrorBanner(message: _error!),
        if (_selectedTransactions.isNotEmpty)
          _SelectionActionBar(
            count: _selectedTransactions.length,
            onClear: _clearSelection,
          ),
        const SizedBox(height: 10),
        if (transactions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('Δεν βρέθηκαν συναλλαγές.')),
            ),
          ),
        if (futureTransactions.isNotEmpty) ...[
          _TransactionGroupHeader(
            title: 'Μελλοντικές συναλλαγές',
            count: futureTransactions.length,
            collapsed: _futureTransactionsCollapsed,
            onToggle: () => _setFutureTransactionsCollapsed(
              !_futureTransactionsCollapsed,
            ),
          ),
          if (!_futureTransactionsCollapsed)
            Card(
              child: _TransactionTable(
                transactions: futureTransactions,
                currency: _currency,
                dateFormat: _dateFormat,
                onStatusChanged: _toggleTransactionCleared,
                columnWidths: _columnWidths,
                onColumnWidthChanged: _setColumnWidth,
                sortColumnIndex: _transactionSortColumn,
                sortAscending: _transactionSortAscending,
                onSort: _sortTransactions,
                selectedTransactions: _selectedTransactions,
                onTransactionSelected: _setTransactionSelected,
                onSplitSelected: _setSplitSelected,
                onFlagPressed: _cycleFlag,
                collapsedSplits: _collapsedSplits,
                onSplitToggled: _setSplitCollapsed,
                scheduled: true,
                transactionImages: _transactionImages,
                onImageDoubleTap: _pickTransactionImage,
                onContextMenu: _showTransactionMenu,
                editingTransaction: _editingDraft,
                onEdit: _beginInlineEdit,
                editingSplitKey: _editingSplitKey,
                editingSplitDraft: _editingSplitDraft,
                onEditChanged: _updateInlineEdit,
                onEditSave: _saveInlineEdit,
                onEditCancel: _cancelInlineEdit,
                highlightEditing: false,
                availableCategories: _categories,
                onEditSplitAmount: _updateInlineSplitAmount,
                onEditAddSplit: _addInlineSplit,
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (pastTransactions.isNotEmpty)
          Card(
            child: _TransactionTable(
              transactions: pastTransactions,
              currency: _currency,
              dateFormat: _dateFormat,
              onStatusChanged: _toggleTransactionCleared,
              columnWidths: _columnWidths,
              onColumnWidthChanged: _setColumnWidth,
              sortColumnIndex: _transactionSortColumn,
              sortAscending: _transactionSortAscending,
              onSort: _sortTransactions,
              selectedTransactions: _selectedTransactions,
              onTransactionSelected: _setTransactionSelected,
              onSplitSelected: _setSplitSelected,
              onFlagPressed: _cycleFlag,
              collapsedSplits: _collapsedSplits,
              onSplitToggled: _setSplitCollapsed,
              scheduled: false,
              transactionImages: _transactionImages,
              onImageDoubleTap: _pickTransactionImage,
              onContextMenu: _showTransactionMenu,
              editingTransaction: _editingDraft,
              onEdit: _beginInlineEdit,
              editingSplitKey: _editingSplitKey,
              editingSplitDraft: _editingSplitDraft,
              onEditChanged: _updateInlineEdit,
              onEditSave: _saveInlineEdit,
              onEditCancel: _cancelInlineEdit,
              highlightEditing: false,
              availableCategories: _categories,
              onEditSplitAmount: _updateInlineSplitAmount,
              onEditAddSplit: _addInlineSplit,
            ),
          ),
        if (transactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${transactions.length} από ${_transactions.length} συναλλαγών',
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
          ),
      ],
    );
  }

  Widget _buildAccountPage() {
    final account = _selectedAccount!;
    final transactions = _filteredTransactions;
    final current = transactions
        .where((transaction) => !transaction.date.isAfter(DateTime.now()))
        .toList();
    final future = transactions
        .where((transaction) => transaction.date.isAfter(DateTime.now()))
        .toList();
    final cleared = current
        .where(
          (transaction) =>
              transaction.cleared.toLowerCase() == 'cleared' ||
              transaction.cleared.toLowerCase() == 'reconciled',
        )
        .fold<double>(0, (sum, transaction) => sum + transaction.net);
    final working = current.fold<double>(
      0,
      (sum, transaction) => sum + transaction.net,
    );
    final uncleared = working - cleared;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        account,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF102A43),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.star_border, color: Colors.blueGrey.shade400),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    accountTypeLabel(classifyAccount(account)),
                    style: TextStyle(color: Colors.blueGrey.shade600),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Επεξεργασία'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {},
              child: const Text('Reconcile'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
              children: [
                _AccountBalanceMetric(
                  label: 'Cleared Balance',
                  value: _currency.format(cleared),
                ),
                const _BalanceOperator(operator: '+'),
                _AccountBalanceMetric(
                  label: 'Uncleared Balance',
                  value: _currency.format(uncleared),
                ),
                const _BalanceOperator(operator: '='),
                _AccountBalanceMetric(
                  label: 'Working Balance',
                  value: _currency.format(working),
                  emphasized: true,
                ),
              ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Προσθήκη συναλλαγής'),
            ),
            OutlinedButton.icon(
              onPressed: _loading ? null : _importRegister,
              icon: const Icon(Icons.upload_file),
              label: const Text('Import ZIP'),
            ),
            TextButton.icon(
              onPressed: null,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
            ),
            TextButton.icon(
              onPressed: null,
              icon: const Icon(Icons.redo),
              label: const Text('Redo'),
            ),
            OutlinedButton.icon(
              onPressed: _splitKeys.isEmpty ? null : _toggleAllSplits,
              icon: Icon(
                _splitKeys.isNotEmpty &&
                        _splitKeys.every(_collapsedSplits.contains)
                    ? Icons.unfold_more
                    : Icons.unfold_less,
              ),
              label: Text(
                _splitKeys.isNotEmpty &&
                        _splitKeys.every(_collapsedSplits.contains)
                    ? 'Expand splits'
                    : 'Collapse splits',
              ),
            ),
            SizedBox(
              width: 250,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Αναζήτηση λογαριασμού...',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null) _ErrorBanner(message: _error!),
        if (_selectedTransactions.isNotEmpty)
          _SelectionActionBar(
            count: _selectedTransactions.length,
            onClear: _clearSelection,
          ),
        if (future.isNotEmpty) ...[
          _TransactionGroupHeader(
            title: 'Μελλοντικές συναλλαγές',
            count: future.length,
            collapsed: _futureTransactionsCollapsed,
            onToggle: () => _setFutureTransactionsCollapsed(
              !_futureTransactionsCollapsed,
            ),
          ),
          if (!_futureTransactionsCollapsed)
            Card(
              child: _TransactionTable(
                transactions: future,
                currency: _currency,
                dateFormat: _dateFormat,
                onStatusChanged: _toggleTransactionCleared,
                columnWidths: _columnWidths,
                onColumnWidthChanged: _setColumnWidth,
                sortColumnIndex: _transactionSortColumn,
                sortAscending: _transactionSortAscending,
                onSort: _sortTransactions,
                selectedTransactions: _selectedTransactions,
                onTransactionSelected: _setTransactionSelected,
                onSplitSelected: _setSplitSelected,
                onFlagPressed: _cycleFlag,
                collapsedSplits: _collapsedSplits,
                onSplitToggled: _setSplitCollapsed,
                scheduled: true,
                transactionImages: _transactionImages,
                onImageDoubleTap: _pickTransactionImage,
                onContextMenu: _showTransactionMenu,
                editingTransaction: _editingDraft,
                onEdit: _beginInlineEdit,
                editingSplitKey: _editingSplitKey,
                editingSplitDraft: _editingSplitDraft,
                onEditChanged: _updateInlineEdit,
                onEditSave: _saveInlineEdit,
                onEditCancel: _cancelInlineEdit,
                highlightEditing: false,
                availableCategories: _categories,
                onEditSplitAmount: _updateInlineSplitAmount,
                onEditAddSplit: _addInlineSplit,
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (current.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: Text('Δεν βρέθηκαν συναλλαγές.')),
            ),
          )
        else
          Card(
            child: _TransactionTable(
              transactions: current,
              currency: _currency,
              dateFormat: _dateFormat,
              onStatusChanged: _toggleTransactionCleared,
              columnWidths: _columnWidths,
              onColumnWidthChanged: _setColumnWidth,
              sortColumnIndex: _transactionSortColumn,
              sortAscending: _transactionSortAscending,
              onSort: _sortTransactions,
              selectedTransactions: _selectedTransactions,
              onTransactionSelected: _setTransactionSelected,
              onSplitSelected: _setSplitSelected,
              onFlagPressed: _cycleFlag,
              collapsedSplits: _collapsedSplits,
              onSplitToggled: _setSplitCollapsed,
              scheduled: false,
              transactionImages: _transactionImages,
              onImageDoubleTap: _pickTransactionImage,
              onContextMenu: _showTransactionMenu,
              editingTransaction: _editingDraft,
              onEdit: _beginInlineEdit,
              editingSplitKey: _editingSplitKey,
              editingSplitDraft: _editingSplitDraft,
              onEditChanged: _updateInlineEdit,
              onEditSave: _saveInlineEdit,
              onEditCancel: _cancelInlineEdit,
              highlightEditing: false,
              availableCategories: _categories,
              onEditSplitAmount: _updateInlineSplitAmount,
              onEditAddSplit: _addInlineSplit,
            ),
          ),
      ],
    );
  }

  Widget _buildReports() {
    if (_transactions.isEmpty) return _EmptyState(onImport: _importRegister);
    if (_reportMode == 1) return _buildNetWorthReport();
    final categories = _categoryOutflows.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = categories.isEmpty ? 1.0 : categories.first.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(
          title: 'Reports',
          subtitle: 'Πού κατευθύνθηκαν τα χρήματά σου.',
        ),
        const SizedBox(height: 18),
        _ReportSwitcher(
          selected: _reportMode,
          onChanged: (value) => setState(() => _reportMode = value),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Εκροές ανά ομάδα κατηγορίας',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                ...categories
                    .take(15)
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _CategoryBar(
                          name: entry.key,
                          amount: entry.value,
                          maximum: max,
                          currency: _currency,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetWorthReport() {
    final points = _netWorthPoints;
    if (points.isEmpty) return const SizedBox.shrink();
    final selectedIndex =
        _hoveredNetWorthIndex != null && _hoveredNetWorthIndex! < points.length
        ? _hoveredNetWorthIndex!
        : points.length - 1;
    final selectedPoint = points[selectedIndex];
    final previous = selectedIndex > 0
        ? points[selectedIndex - 1]
        : selectedPoint;
    final change = selectedPoint.netWorth - previous.netWorth;
    final ratio = selectedPoint.assets == 0
        ? 0.0
        : selectedPoint.debts / selectedPoint.assets * 100;
    final range =
        '${DateFormat('MMMM yyyy', 'el_GR').format(points.first.month)} - '
        '${DateFormat('MMMM yyyy', 'el_GR').format(points.last.month)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageTitle(
          title: 'Net Worth',
          subtitle: 'Η εξέλιξη της καθαρής θέσης σου στον χρόνο.',
        ),
        const SizedBox(height: 18),
        _ReportSwitcher(
          selected: _reportMode,
          onChanged: (value) => setState(() => _reportMode = value),
        ),
        const SizedBox(height: 14),
        Text(range, style: TextStyle(color: Colors.blueGrey.shade600)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                DateFormat('MMMM yyyy', 'en_US').format(selectedPoint.month),
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
              ),
            ),
            _NetWorthSummary(
              point: selectedPoint,
              change: change,
              debtRatio: ratio,
              currency: _currency,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 18, 12),
            child: SizedBox(
              height: math.max(520, MediaQuery.sizeOf(context).height - 360),
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chartWidth = constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: chartWidth,
                      child: MouseRegion(
                        onHover: (event) {
                          final plotWidth = chartWidth - 58;
                          final rawIndex =
                              ((event.localPosition.dx - 58) /
                                      math.max(1, plotWidth) *
                                      math.max(1, points.length - 1))
                                  .round()
                                  .clamp(0, points.length - 1);
                          final index = rawIndex.toInt();
                          if (_hoveredNetWorthIndex != index) {
                            setState(() => _hoveredNetWorthIndex = index);
                          }
                        },
                        onExit: (_) =>
                            setState(() => _hoveredNetWorthIndex = null),
                        child: CustomPaint(
                          painter: _NetWorthChartPainter(
                            points,
                            hoveredIndex: _hoveredNetWorthIndex,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReportSwitcher extends StatelessWidget {
  const _ReportSwitcher({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
    segments: const [
      ButtonSegment(value: 0, label: Text('Εκροές ανά κατηγορία')),
      ButtonSegment(value: 1, label: Text('Net Worth')),
    ],
    selected: {selected},
    onSelectionChanged: (values) => onChanged(values.first),
  );
}

class _NetWorthSummary extends StatelessWidget {
  const _NetWorthSummary({
    required this.point,
    required this.change,
    required this.debtRatio,
    required this.currency,
  });
  final NetWorthPoint point;
  final double change;
  final double debtRatio;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 0,
    runSpacing: 10,
    children: [
      _SummaryMetric(
        label: 'Debts',
        value: currency.format(point.debts),
        color: const Color(0xFFF36C5A),
      ),
      _SummaryMetric(
        label: 'Assets',
        value: currency.format(point.assets),
        color: const Color(0xFF83CDE3),
      ),
      _SummaryMetric(
        label: 'Debt Ratio',
        value: '${debtRatio.toStringAsFixed(0)}%',
        color: const Color(0xFF102A43),
      ),
      _SummaryMetric(
        label: 'Net Worth',
        value: currency.format(point.netWorth),
        color: const Color(0xFF72AFE4),
      ),
      _SummaryMetric(
        label: 'Change',
        value: currency.format(change),
        color: const Color(0xFF72AFE4),
      ),
    ],
  );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: Color(0xFFE0E0E0))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 16, height: 4, color: color),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _NetWorthChartPainter extends CustomPainter {
  _NetWorthChartPainter(this.points, {this.hoveredIndex});
  final List<NetWorthPoint> points;
  final int? hoveredIndex;
  static const assetsColor = Color(0xFF83CDE3);
  static const debtsColor = Color(0xFFF36C5A);
  static const lineColor = Color(0xFF72AFE4);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 58.0;
    const top = 22.0;
    const bottom = 68.0;
    final chartWidth = size.width - left;
    final chartHeight = size.height - top - bottom;
    final maximum = points
        .fold<double>(
          0,
          (max, point) => math.max(max, math.max(point.assets, point.debts)),
        )
        .clamp(1, double.infinity);
    final netMax = points
        .fold<double>(0, (max, point) => math.max(max, point.netWorth.abs()))
        .clamp(1, double.infinity);
    final scaleMax = math.max(maximum, netMax);
    final gridPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 1;
    final assetsPaint = Paint()
      ..color = assetsColor
      ..strokeWidth = 1.5;
    final debtsPaint = Paint()
      ..color = debtsColor
      ..strokeWidth = 1.5;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    double xFor(int index) =>
        left + (index / math.max(1, points.length - 1)) * chartWidth;
    double yFor(double value) =>
        top + chartHeight - (value / scaleMax) * chartHeight;
    final textStyle = const TextStyle(color: Color(0xFF4F5965), fontSize: 10);
    for (var i = 0; i <= 6; i++) {
      final y = top + chartHeight * i / 6;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      _drawText(
        canvas,
        '€${(scaleMax * (6 - i) / 6 / 1000).toStringAsFixed(0)}k',
        Offset(0, y - 6),
        textStyle,
      );
    }
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x = xFor(i);
      final barWidth = math.max(1.0, chartWidth / points.length * .28);
      canvas.drawLine(
        Offset(x - barWidth, yFor(point.debts)),
        Offset(x - barWidth, top + chartHeight),
        debtsPaint,
      );
      canvas.drawLine(
        Offset(x + barWidth, yFor(point.assets)),
        Offset(x + barWidth, top + chartHeight),
        assetsPaint,
      );
      final linePoint = Offset(x, yFor(point.netWorth));
      if (i == 0) {
        path.moveTo(linePoint.dx, linePoint.dy);
      } else {
        path.lineTo(linePoint.dx, linePoint.dy);
      }
      final labelInterval = points.length > 60 ? 6 : 3;
      if (i % labelInterval == 0 || i == points.length - 1) {
        canvas.save();
        canvas.translate(x - 4, top + chartHeight + 18);
        canvas.rotate(-math.pi / 4);
        _drawText(
          canvas,
          DateFormat('MMM yy', 'en_US').format(point.month),
          Offset.zero,
          textStyle,
        );
        canvas.restore();
      }
    }
    canvas.drawPath(path, linePaint);
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(
        Offset(xFor(i), yFor(points[i].netWorth)),
        2.5,
        Paint()..color = lineColor,
      );
    }
    if (hoveredIndex != null && hoveredIndex! < points.length) {
      final x = xFor(hoveredIndex!);
      final y = yFor(points[hoveredIndex!].netWorth);
      final hoverPaint = Paint()
        ..color = const Color(0xFF607D8B)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, top), Offset(x, top + chartHeight), hoverPaint);
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = lineColor);
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = Colors.white);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _NetWorthChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.hoveredIndex != hoveredIndex;
}

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.selected,
    required this.selectedAccount,
    required this.balances,
    required this.collapsedGroups,
    required this.sidebarWidth,
    required this.onSelect,
    required this.onAccountSelect,
    required this.onToggleGroup,
    required this.onWidthChanged,
  });
  final int selected;
  final String? selectedAccount;
  final Map<AccountType, List<MapEntry<String, double>>> balances;
  final Set<AccountType> collapsedGroups;
  final double sidebarWidth;
  final ValueChanged<int> onSelect;
  final ValueChanged<String> onAccountSelect;
  final void Function(AccountType, bool) onToggleGroup;
  final ValueChanged<double> onWidthChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: sidebarWidth,
      child: Stack(
        children: [
          Container(
            color: const Color(0xFF102A43),
            padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 10, bottom: 38),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet,
                        color: Color(0xFF7FE0D4),
                        size: 28,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Financial App',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Επισκόπηση',
                  selected: selected == 0,
                  onTap: () => onSelect(0),
                ),
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Συναλλαγές',
                  selected: selected == 1,
                  onTap: () => onSelect(1),
                ),
                _NavItem(
                  icon: Icons.insights_outlined,
                  label: 'Reports',
                  selected: selected == 2,
                  onTap: () => onSelect(2),
                ),
                const Divider(color: Color(0x335E7792), height: 26),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: accountTypeOrder
                          .where((type) => balances[type]?.isNotEmpty ?? false)
                          .map(
                            (type) => _NavAccountGroup(
                              type: type,
                              entries: balances[type]!,
                              collapsed: collapsedGroups.contains(type),
                              selectedAccount: selectedAccount,
                              onAccountSelect: onAccountSelect,
                              onToggle: (collapsed) =>
                                  onToggleGroup(type, collapsed),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) =>
                    onWidthChanged(sidebarWidth + details.delta.dx),
                child: const SizedBox(width: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavAccountGroup extends StatelessWidget {
  const _NavAccountGroup({
    required this.type,
    required this.entries,
    required this.collapsed,
    required this.selectedAccount,
    required this.onAccountSelect,
    required this.onToggle,
  });

  final AccountType type;
  final List<MapEntry<String, double>> entries;
  final bool collapsed;
  final String? selectedAccount;
  final ValueChanged<String> onAccountSelect;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final color = accountTypeColor(type);
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onToggle(!collapsed),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 5),
            child: Row(
              children: [
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 17,
                  color: const Color(0xFF9FB3C8),
                ),
                Expanded(
                  child: Text(
                    uppercaseWithoutGreekTones(accountTypeLabel(type)),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9FB3C8),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                Text(
                  NumberFormat.currency(
                    locale: 'el_GR',
                    symbol: '€',
                  ).format(total),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          ...entries.map(
            (entry) => _NavAccountItem(
              name: entry.key,
              balance: entry.value,
              selected: selectedAccount == entry.key,
              onTap: () => onAccountSelect(entry.key),
            ),
          ),
      ],
    );
  }
}

class _NavAccountItem extends StatelessWidget {
  const _NavAccountItem({
    required this.name,
    required this.balance,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final double balance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF2C5870) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFD0DCE7),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            NumberFormat.currency(locale: 'el_GR', symbol: '€').format(balance),
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFFD0DCE7),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: ListTile(
      leading: Icon(
        icon,
        color: selected ? const Color(0xFF7FE0D4) : const Color(0xFFB8C7D8),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : const Color(0xFFB8C7D8),
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: selected,
      selectedTileColor: const Color(0xFF1E4B63),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onImport, required this.loading});
  final VoidCallback onImport;
  final bool loading;
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF102A43),
    padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 16,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Τα οικονομικά σου, καθαρά.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Εισήγαγε το ZIP export από το YNAB για να ξεκινήσεις.',
              style: TextStyle(color: Color(0xFFB8C7D8)),
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: loading ? null : onImport,
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.upload_file),
          label: Text(loading ? 'Εισαγωγή...' : 'Import ZIP'),
        ),
      ],
    ),
  );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w800,
          color: Color(0xFF102A43),
        ),
      ),
      const SizedBox(height: 5),
      Text(subtitle, style: TextStyle(color: Colors.blueGrey.shade600)),
    ],
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.action});
  final String title;
  final String action;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF102A43),
        ),
      ),
      Text(action, style: TextStyle(color: Colors.blueGrey.shade600)),
    ],
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            foregroundColor: color,
            child: Icon(icon),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.name, required this.balance});
  final String name;
  final double balance;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: const CircleAvatar(
      radius: 12,
      backgroundColor: Color(0xFFE8F5F3),
      foregroundColor: Color(0xFF159A9C),
      child: Icon(Icons.account_balance, size: 13),
    ),
    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
    trailing: Text(
      NumberFormat.currency(locale: 'el_GR', symbol: '€').format(balance),
      style: TextStyle(
        fontWeight: FontWeight.w800,
        color: balance < 0 ? const Color(0xFFD45D4C) : const Color(0xFF102A43),
      ),
    ),
  );
}

class _AccountGroupCard extends StatelessWidget {
  const _AccountGroupCard({
    required this.type,
    required this.entries,
    required this.collapsed,
    required this.onToggle,
  });
  final AccountType type;
  final List<MapEntry<String, double>> entries;
  final bool collapsed;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final color = accountTypeColor(type);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: .12),
              foregroundColor: color,
              child: Icon(accountTypeIcon(type)),
            ),
            title: Text(
              accountTypeLabel(type),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: type == AccountType.personalDebts
                ? const Text('Δεν θεωρούνται αυτόματα μετρητά ή υποχρεώσεις')
                : type == AccountType.inactive
                ? const Text('Δεν συμμετέχουν στις ενεργές κατηγορίες')
                : Text('${entries.length} λογαριασμοί'),
            trailing: IconButton(
              tooltip: collapsed ? 'Ανάπτυξη' : 'Σύμπτυξη',
              icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
              onPressed: () => onToggle(!collapsed),
            ),
          ),
          if (!collapsed)
            ...entries.map(
              (entry) => _AccountRow(name: entry.key, balance: entry.value),
            ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButton<String>(
    hint: Text(label),
    value: value,
    items: values
        .map(
          (item) => DropdownMenuItem(
            value: item,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
          ),
        )
        .toList(),
    onChanged: onChanged,
  );
}

String _displaySplitMemo(String memo) => memo
    .replaceFirst(RegExp(r'^Split \(\d+/\d+\)\s*'), '')
    .trim();

class _TransactionTable extends StatelessWidget {
  const _TransactionTable({
    required this.transactions,
    required this.currency,
    required this.dateFormat,
    required this.onStatusChanged,
    required this.columnWidths,
    required this.onColumnWidthChanged,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
    required this.selectedTransactions,
    required this.onTransactionSelected,
    required this.onSplitSelected,
    required this.onFlagPressed,
    required this.transactionImages,
    required this.onImageDoubleTap,
    required this.onContextMenu,
    required this.onEdit,
    required this.editingSplitKey,
    required this.editingSplitDraft,
    required this.editingTransaction,
    required this.onEditChanged,
    required this.onEditSave,
    required this.onEditCancel,
    required this.highlightEditing,
    required this.availableCategories,
    required this.onEditSplitAmount,
    required this.onEditAddSplit,
    required this.collapsedSplits,
    required this.onSplitToggled,
    required this.scheduled,
  });
  final List<Transaction> transactions;
  final NumberFormat currency;
  final DateFormat dateFormat;
  final ValueChanged<Transaction> onStatusChanged;
  final List<double> columnWidths;
  final void Function(int index, double width) onColumnWidthChanged;
  final int sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending) onSort;
  final Set<Transaction> selectedTransactions;
  final void Function(Transaction transaction, bool selected)
  onTransactionSelected;
  final void Function(List<Transaction> transactions, bool selected)
  onSplitSelected;
  final ValueChanged<Transaction> onFlagPressed;
  final Map<Transaction, Uint8List> transactionImages;
  final ValueChanged<Transaction> onImageDoubleTap;
  final void Function(Offset, Transaction, List<Transaction>?) onContextMenu;
  final void Function(Transaction, [String?]) onEdit;
  final String? editingSplitKey;
  final List<Transaction>? editingSplitDraft;
  final Transaction? editingTransaction;
  final ValueChanged<Transaction> onEditChanged;
  final VoidCallback onEditSave;
  final VoidCallback onEditCancel;
  final bool highlightEditing;
  final List<String> availableCategories;
  final void Function(List<Transaction>, double) onEditSplitAmount;
  final VoidCallback onEditAddSplit;
  final Set<String> collapsedSplits;
  final void Function(String key, bool collapsed) onSplitToggled;
  final bool scheduled;


  List<_TransactionDisplayRow> _displayRows() {
    final rows = <_TransactionDisplayRow>[];
    final rowOrders = <int>[];
    final splitGroups = <String, List<Transaction>>{};
    final splitOrder = <String>[];
    final splitFirstOrder = <String, int>{};
    final splitPattern = RegExp(r'^Split \(\d+/\d+\)\s*(.*)$');
    var order = 0;
    for (final transaction in transactions.take(250)) {
      final match = splitPattern.firstMatch(transaction.memo);
      if (match == null) {
        rows.add(_TransactionDisplayRow(transaction));
        rowOrders.add(order);
        order++;
        continue;
      }
      final baseMemo = match.group(1)!.trim();
      final key =
          '${transaction.date.year}-${transaction.date.month}-'
          '${transaction.date.day}|${transaction.account}|$baseMemo';
      if (!splitGroups.containsKey(key)) splitOrder.add(key);
      splitFirstOrder.putIfAbsent(key, () => order);
      splitGroups.putIfAbsent(key, () => []).add(transaction);
      order++;
    }
    for (final key in splitOrder) {
      final children = editingSplitKey == key && editingSplitDraft != null
          ? editingSplitDraft!
          : splitGroups[key]!;
      if (children.length < 2) {
        rows.add(_TransactionDisplayRow(children.first));
        rowOrders.add(splitFirstOrder[key]!);
        continue;
      }
      final first = children.first;
      final parentMemo = children
          .map((child) => _displaySplitMemo(child.memo))
          .firstWhere((memo) => memo.isNotEmpty, orElse: () => '');
      final totalInflow = children.fold<double>(
        0,
        (sum, transaction) => sum + transaction.inflow,
      );
      final totalOutflow = children.fold<double>(
        0,
        (sum, transaction) => sum + transaction.outflow,
      );
      final parent = Transaction(
        account: first.account,
        flag: first.flag,
        date: first.date,
        payee: first.payee,
        category: 'Split (Multiple Categories)...',
        categoryGroup: '',
        memo: parentMemo,
        outflow: totalOutflow,
        inflow: totalInflow,
        cleared: children.every((item) => item.cleared == 'Reconciled')
            ? 'Reconciled'
            : children.every((item) => item.cleared == 'Cleared')
            ? 'Cleared'
            : 'Uncleared',
      );
      rows.add(
        _TransactionDisplayRow(
          parent,
          children: children,
          splitKey: key,
          collapsed: collapsedSplits.contains(key),
        ),
      );
      rowOrders.add(splitFirstOrder[key]!);
    }
    final orderedIndexes = List.generate(rows.length, (index) => index)
      ..sort((first, second) => rowOrders[first].compareTo(rowOrders[second]));
    return orderedIndexes.map((index) => rows[index]).toList();
  }

  List<_TransactionDisplayRow> _renderRows() {
    final rendered = <_TransactionDisplayRow>[];
    for (final row in _displayRows()) {
      rendered.add(row);
      if (row.isSplit && !row.collapsed) {
        rendered.addAll(
          row.children!.map(
            (child) => _TransactionDisplayRow(
              child,
              childOnly: true,
              splitKey: row.splitKey,
            ),
          ),
        );
      }
    }
    return rendered;
  }
  @override
  Widget build(BuildContext context) => Scrollbar(
    thumbVisibility: false,
    interactive: true,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons != kSecondaryMouseButton) return;
          final rowIndex = ((event.localPosition.dy - 34) / 34).floor();
          final rows = _renderRows();
          if (rowIndex < 0 || rowIndex >= rows.length) return;
          final row = rows[rowIndex];
          onContextMenu(event.position, row.transaction, row.children);
        },
        child: GestureDetector(
          onDoubleTapDown: (details) {
            final rowIndex = ((details.localPosition.dy - 34) / 34).floor();
            final rows = _renderRows();
            if (rowIndex < 0 || rowIndex >= rows.length) return;
            onEdit(rows[rowIndex].transaction, rows[rowIndex].splitKey);
          },
          child: DataTable(
      headingRowHeight: 34,
      dataRowMinHeight: 34,
      dataRowMaxHeight: 34,
      horizontalMargin: 8,
      columnSpacing: 12,
      checkboxHorizontalMargin: 8,
      dataRowColor: scheduled
          ? const MaterialStatePropertyAll(Color(0xFFFBF8F0))
          : null,
      headingRowColor: scheduled
          ? const MaterialStatePropertyAll(Color(0xFFF3F0E7))
          : null,
      sortColumnIndex: sortColumnIndex,
      sortAscending: sortAscending,
      columns: [
        DataColumn(label: _iconColumnHeader(0, Icons.flag_outlined)),
        DataColumn(label: _iconColumnHeader(1, Icons.image_outlined)),
        DataColumn(label: _columnHeader(2, 'Ημερομηνία')),
        DataColumn(label: _columnHeader(3, 'Πληρωτής / Έμπορος')),
        DataColumn(label: _columnHeader(4, 'Κατηγορία')),
        DataColumn(label: _columnHeader(5, 'Memo')),
        DataColumn(label: _columnHeader(6, 'Outflow')),
        DataColumn(label: _columnHeader(7, 'Inflow')),
        DataColumn(label: _columnHeader(8, 'Κατάσταση')),
      ],
      rows: _displayRows().expand((displayRow) {
            final parent = displayRow.toDataRow(
              columnWidths: columnWidths,
              dateFormat: dateFormat,
              currency: currency,
              onStatusChanged: onStatusChanged,
              onFlagPressed: onFlagPressed,
              transactionImages: transactionImages,
              onImageDoubleTap: onImageDoubleTap,
              onContextMenu: onContextMenu,
              editingTransaction: editingTransaction,
              editingSplitKey: editingSplitKey,
              highlightEditing: displayRow.isSplit &&
                  editingTransaction == displayRow.transaction,
              onEditChanged: onEditChanged,
              onEditSave: onEditSave,
              onEditCancel: onEditCancel,
              availableCategories: availableCategories,
              onEditSplitAmount: onEditSplitAmount,
              selected: displayRow.isSplit
                  ? displayRow.children!.every(selectedTransactions.contains)
                  : selectedTransactions.contains(displayRow.transaction),
              onSelected: (selected) => displayRow.isSplit
                  ? onSplitSelected(displayRow.children!, selected)
                  : onTransactionSelected(displayRow.transaction, selected),
              enabled: true,
              onSplitToggled: displayRow.isSplit
                  ? () => onSplitToggled(
                      displayRow.splitKey!,
                      !displayRow.collapsed,
                    )
                  : null,
            );
            if (!displayRow.isSplit || displayRow.collapsed) return [parent];
            final childRows = [
              parent,
              ...displayRow.children!.map(
                (child) => _TransactionDisplayRow(
                  child,
                  childOnly: true,
                  splitKey: displayRow.splitKey,
                ).toDataRow(
                  columnWidths: columnWidths,
                  currency: currency,
                  dateFormat: dateFormat,
                  onStatusChanged: onStatusChanged,
                  onFlagPressed: onFlagPressed,
                  transactionImages: transactionImages,
                  onImageDoubleTap: onImageDoubleTap,
                  onContextMenu: onContextMenu,
                  editingTransaction: editingTransaction,
                  editingSplitKey: editingSplitKey,
                  highlightEditing: displayRow.isSplit &&
                      editingTransaction == displayRow.transaction,
                  onEditChanged: onEditChanged,
                  onEditSave: onEditSave,
                  onEditCancel: onEditCancel,
                  availableCategories: availableCategories,
                  onEditSplitAmount: onEditSplitAmount,
                  selected: selectedTransactions.contains(child),
                  onSelected: (selected) =>
                      onTransactionSelected(child, selected),
                  enabled: true,
                  onSplitToggled: null,
                ),
              ),
            ];
            final isEditingSplit = editingSplitKey == displayRow.splitKey;
            if (!isEditingSplit) return childRows;
            return [
              ...childRows,
              _splitEditFooterRow(
                parent: displayRow.transaction,
                parts: displayRow.children!,
                onAddSplit: onEditAddSplit,
                onSave: onEditSave,
                onCancel: onEditCancel,
              ),
            ];
          })
          .toList(),
          ),
        ),
      ),
    ),
  );

  DataRow _splitEditFooterRow({
    required Transaction parent,
    required List<Transaction> parts,
    required VoidCallback onAddSplit,
    required VoidCallback onSave,
    required VoidCallback onCancel,
  }) {
    final remainingOutflow = (parent.outflow -
            parts.fold<double>(0, (sum, part) => sum + part.outflow))
        .abs();
    final remainingInflow = (parent.inflow -
            parts.fold<double>(0, (sum, part) => sum + part.inflow))
        .abs();
    final amount = (double value) => Text(
          value.toStringAsFixed(2).replaceAll('.', ','),
          style: const TextStyle(fontSize: 13, color: Color(0xFF102A43)),
        );
    return DataRow(
      color: const MaterialStatePropertyAll(Color(0xFFDAD9FF)),
      cells: [
        DataCell(
          SizedBox(
            width: 180,
            child: TextButton.icon(
              onPressed: onAddSplit,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              icon: const Icon(Icons.add_circle, size: 16),
              label: const Text('Add another split'),
            ),
          ),
        ),
        for (var index = 1; index < 5; index++)
          DataCell(const SizedBox.shrink()),
        DataCell(
          Row(
            children: [
              const Spacer(),
              const Text(
                'Amount remaining to assign:',
                style: TextStyle(fontSize: 13, color: Color(0xFF102A43)),
              ),
            ],
          ),
        ),
        DataCell(Align(alignment: Alignment.centerRight, child: amount(remainingOutflow))),
        DataCell(Align(alignment: Alignment.centerRight, child: amount(remainingInflow))),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
              const SizedBox(width: 6),
              FilledButton(onPressed: onSave, child: const Text('Save')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _columnHeader(int index, String label) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onSort(
      index,
      sortColumnIndex == index ? !sortAscending : true,
    ),
    onHorizontalDragUpdate: (details) => onColumnWidthChanged(
      index,
      columnWidths[index] + details.delta.dx,
    ),
    child: SizedBox(
      height: 34,
      width: columnWidths[index],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (sortColumnIndex == index)
            Icon(
              sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 20,
              color: const Color(0xFF52606D),
            ),
          Container(width: 2, color: const Color(0xFFD8E0E8)),
        ],
      ),
    ),
    ),
  );

  Widget _iconColumnHeader(int index, IconData icon) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragUpdate: (details) => onColumnWidthChanged(
      index,
      columnWidths[index] + details.delta.dx,
    ),
    child: SizedBox(
      height: 34,
      width: columnWidths[index],
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF52606D)),
          Align(
            alignment: Alignment.centerRight,
            child: Container(width: 2, color: const Color(0xFFD8E0E8)),
          ),
        ],
      ),
    ),
    ),
  );
}

class _TransactionDisplayRow {
  _TransactionDisplayRow(
    this.transaction, {
    this.children,
    this.childOnly = false,
    this.collapsed = false,
    this.splitKey,
  });
  final Transaction transaction;
  final List<Transaction>? children;
  final bool childOnly;
  final bool collapsed;
  final String? splitKey;

  bool get isChild => childOnly;
  bool get isSplit => children != null;

  DataRow toDataRow({
    required List<double> columnWidths,
    required NumberFormat currency,
    required DateFormat dateFormat,
    required ValueChanged<Transaction> onStatusChanged,
    required ValueChanged<Transaction> onFlagPressed,
    required Map<Transaction, Uint8List> transactionImages,
    required ValueChanged<Transaction> onImageDoubleTap,
    required void Function(Offset, Transaction, List<Transaction>?) onContextMenu,
    required Transaction? editingTransaction,
    required String? editingSplitKey,
    required ValueChanged<Transaction> onEditChanged,
    required VoidCallback onEditSave,
    required VoidCallback onEditCancel,
    required bool highlightEditing,
    required List<String> availableCategories,
    required void Function(List<Transaction>, double) onEditSplitAmount,
    required bool selected,
    required ValueChanged<bool> onSelected,
    required bool enabled,
    required VoidCallback? onSplitToggled,
  }) {
    final editing = editingTransaction == transaction ||
        (editingSplitKey != null && editingSplitKey == splitKey);
    final splitPrefix = RegExp(r'^(Split \(\d+/\d+\)\s*)').firstMatch(transaction.memo)?.group(1) ?? '';
    Widget editor(String value, ValueChanged<String> onChanged) => TextFormField(
      initialValue: value,
      style: const TextStyle(fontSize: 13, color: Color(0xFF102A43)),
      onChanged: onChanged,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      ),
    );
    void updateColumnAmount(String value, bool outflowColumn) {
      final parsed = double.tryParse(value.replaceAll(',', '.'));
      if (parsed == null) return;
      final signed = outflowColumn ? parsed : -parsed;
      if (children != null) {
        onEditSplitAmount(children!, signed);
      } else {
        onEditChanged(transaction.copyWith(
          outflow: signed >= 0 ? signed : 0,
          inflow: signed < 0 ? signed.abs() : 0,
        ));
      }
    }
    String editAmount(double value) => value.toStringAsFixed(2).replaceAll('.', ',');
    Widget displayAmount(double value, Color color) => value == 0
        ? const SizedBox.shrink()
        : Text(currency.format(value), style: TextStyle(color: color, fontWeight: FontWeight.w700));
    final category = transaction.categoryGroup.isEmpty
        ? transaction.category
        : '${transaction.categoryGroup}: ${transaction.category}';
    return DataRow(
      color: editing || highlightEditing
          ? const MaterialStatePropertyAll(Color(0xFFDAD9FF))
          : null,
      selected: selected,
      onSelectChanged: enabled ? (value) => onSelected(value ?? false) : null,
      cells: [
        DataCell(
          SizedBox(
            width: columnWidths[0],
            child: _TransactionFlagIcon(
              flag: transaction.flag,
              onPressed: () => onFlagPressed(transaction),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: columnWidths[1],
            child: _TransactionImageCell(
              bytes: transactionImages[transaction],
              onDoubleTap: () => onImageDoubleTap(transaction),
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: columnWidths[2],
            child: editing
                ? editor(dateFormat.format(transaction.date), (value) {
                    final parsed = DateTime.tryParse(
                      value.split('/').reversed.join('-'),
                    );
                    if (parsed != null) {
                      onEditChanged(transaction.copyWith(date: parsed));
                    }
                  })
                : Text(isChild ? '' : dateFormat.format(transaction.date)),
          ),
        ),
        DataCell(
          SizedBox(
            width: columnWidths[3],
            child: editing
                ? editor(transaction.payee, (value) => onEditChanged(
                    transaction.copyWith(payee: value),
                  ))
                : Text(
                    transaction.payee.isEmpty ? 'Χωρίς όνομα' : transaction.payee,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
        DataCell(
          SizedBox(
            width: columnWidths[4],
            child: editing
                ? Autocomplete<String>(
                    initialValue: TextEditingValue(text: category),
                    optionsBuilder: (value) {
                      final query = value.text.toLowerCase();
                      return availableCategories.where(
                        (item) => item.toLowerCase().contains(query),
                      );
                    },
                    onSelected: (value) {
                      final separator = value.indexOf(':');
                      onEditChanged(
                        transaction.copyWith(
                          categoryGroup: separator < 0
                              ? ''
                              : value.substring(0, separator).trim(),
                          category: separator < 0
                              ? value
                              : value.substring(separator + 1).trim(),
                        ),
                      );
                    },
                    fieldViewBuilder: (context, controller, focusNode, _) =>
                        TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF102A43)),
                          onChanged: (value) => onEditChanged(
                            transaction.copyWith(category: value),
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                            suffixIcon: Icon(Icons.arrow_drop_down, size: 18),
                          ),
                        ),
                  )
                : Row(
              children: [
                if (isSplit)
                  GestureDetector(
                    onTap: onSplitToggled,
                    child: Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 18,
                    ),
                  ),
                Expanded(
                  child: Text(category, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: columnWidths[5],
            child: editing
                ? editor(transaction.memo.replaceFirst(splitPrefix, ''), (value) =>
                    onEditChanged(transaction.copyWith(memo: '$splitPrefix$value')))
                : Text(
                    _displaySplitMemo(transaction.memo),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
        DataCell(
          SizedBox(
            width: columnWidths[6],
            child: editing
                ? editor(editAmount(transaction.outflow), (value) => updateColumnAmount(value, true))
                : displayAmount(transaction.outflow, const Color(0xFFD45D4C)),
          ),
        ),
        DataCell(
          SizedBox(
            width: columnWidths[7],
            child: editing
                ? editor(editAmount(transaction.inflow), (value) => updateColumnAmount(value, false))
                : displayAmount(transaction.inflow, const Color(0xFF2D8A5F)),
          ),
        ),
        DataCell(
          SizedBox(
            width: columnWidths[8],
            child: editing
                ? const SizedBox.shrink()
                : _TransactionStatusIcon(
              status: transaction.cleared,
              onPressed: () => onStatusChanged(transaction),
              enabled: enabled && !isSplit,
            ),
          ),
        ),
      ],
    );
  }
}

class _TransactionImageCell extends StatelessWidget {
  const _TransactionImageCell({required this.bytes, required this.onDoubleTap});
  final Uint8List? bytes;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final image = bytes == null
        ? const Icon(Icons.image_outlined, size: 17)
        : Image.memory(bytes!, width: 24, height: 24, fit: BoxFit.contain);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: bytes == null
          ? null
          : (_) => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.memory(bytes!, fit: BoxFit.contain),
                  ),
                ),
              ),
      child: GestureDetector(
        onDoubleTap: onDoubleTap,
        child: Center(child: image),
      ),
    );
  }
}

class _TransactionFlagIcon extends StatelessWidget {
  const _TransactionFlagIcon({required this.flag, required this.onPressed});
  final String flag;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const colors = {
      'red': Color(0xFFF44336),
      'orange': Color(0xFFFF9800),
      'yellow': Color(0xFFFFC107),
      'green': Color(0xFF4CAF50),
      'blue': Color(0xFF42A5F5),
      'purple': Color(0xFFAB47BC),
    };
    final color = colors[flag.toLowerCase()];
    return IconButton(
      tooltip: color == null ? 'Flag' : '$flag flag - κλικ για αλλαγή',
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(
        Icons.flag,
        size: 18,
        color: color ?? const Color(0xFFB0B7C3),
      ),
    );
  }
}

class _TransactionStatusIcon extends StatelessWidget {
  const _TransactionStatusIcon({
    required this.status,
    required this.onPressed,
    this.enabled = true,
  });
  final String status;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final reconciled = normalized == 'reconciled';
    final cleared = normalized == 'cleared';
    return IconButton(
      tooltip: reconciled
          ? 'Reconciled'
          : cleared
          ? 'Cleared - κλικ για Uncleared'
          : 'Uncleared - κλικ για Cleared',
      onPressed: reconciled || !enabled ? null : onPressed,
      icon: Icon(
        reconciled
            ? Icons.lock
            : cleared
            ? Icons.check_circle
            : Icons.radio_button_unchecked,
        size: 18,
        color: reconciled
            ? const Color(0xFF5B8F29)
            : cleared
            ? const Color(0xFF2D8A5F)
            : const Color(0xFF9AA5B1),
      ),
    );
  }
}

class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({required this.count, required this.onClear});
  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF1D1D4F),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onClear,
          tooltip: 'Καθαρισμός επιλογής',
          icon: const Icon(Icons.close, color: Colors.white, size: 16),
        ),
        Text(
          '$count ${count == 1 ? 'Transaction' : 'Transactions'}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 22),
        TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.category, color: Colors.white, size: 16),
          label: const Text('Categorize', style: TextStyle(color: Colors.white)),
        ),
        TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.flag, color: Colors.white, size: 16),
          label: const Text('Flag', style: TextStyle(color: Colors.white)),
        ),
        TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.more_horiz, color: Colors.white, size: 16),
          label: const Text('More', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class _TransactionGroupHeader extends StatelessWidget {
  const _TransactionGroupHeader({
    required this.title,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });
  final String title;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onToggle,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
        color: Color(0xFFF3F0E7),
        border: Border(
          top: BorderSide(color: Color(0xFFE0D9CA)),
          bottom: BorderSide(color: Color(0xFFE0D9CA)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            color: Color(0xFF6B6254),
            size: 19,
          ),
          const SizedBox(width: 5),
          const Icon(
            Icons.calendar_month_outlined,
            size: 18,
            color: Color(0xFF6B6254),
          ),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text(
            '$count συναλλαγές',
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _AccountBalanceMetric extends StatelessWidget {
  const _AccountBalanceMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 155,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.blueGrey.shade600)),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 20 : 17,
            fontWeight: FontWeight.w800,
            color: emphasized
                ? const Color(0xFF159A9C)
                : const Color(0xFF102A43),
          ),
        ),
      ],
    ),
  );
}

class _BalanceOperator extends StatelessWidget {
  const _BalanceOperator({required this.operator});
  final String operator;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Text(
      operator,
      style: TextStyle(fontSize: 20, color: Colors.blueGrey.shade400),
    ),
  );
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.name,
    required this.amount,
    required this.maximum,
    required this.currency,
  });
  final String name;
  final double amount;
  final double maximum;
  final NumberFormat currency;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            currency.format(amount),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 7),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: amount / maximum,
          minHeight: 10,
          backgroundColor: const Color(0xFFE8EEF3),
          color: const Color(0xFF159A9C),
        ),
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 56),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.upload_file, size: 54, color: Color(0xFF159A9C)),
            const SizedBox(height: 16),
            const Text(
              'Δεν υπάρχουν δεδομένα ακόμη',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Color(0xFF102A43),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ξεκίνα εισάγοντας το ZIP export από το YNAB.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.upload_file),
              label: const Text('Εισαγωγή ZIP export'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE8E5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message, style: const TextStyle(color: Color(0xFF9E3427))),
  );
}
