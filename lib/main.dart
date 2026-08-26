import 'dart:convert';
import 'dart:async';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

const appVersion = 'v0.1.3';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final DateTime date;
  final String payee;
  final String category;
  final String categoryGroup;
  final String memo;
  final double outflow;
  final double inflow;
  final String cleared;

  double get net => inflow - outflow;
}

enum AccountType {
  liquid,
  creditCard,
  investment,
  asset,
  personalDebts,
  loan,
  inactive,
}

const accountTypeOrder = [
  AccountType.liquid,
  AccountType.creditCard,
  AccountType.investment,
  AccountType.asset,
  AccountType.personalDebts,
  AccountType.loan,
  AccountType.inactive,
];

AccountType classifyAccount(String account) {
  final name = account.toLowerCase();
  if (name.contains('diners') ||
      name.contains('highlow') ||
      name == 'σπίτι 2' ||
      name == 'tdm900') {
    return AccountType.inactive;
  }
  if (name == 'δανεικά') return AccountType.personalDebts;
  if (name.contains('δάνειο')) return AccountType.loan;
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
  AccountType.loan => 'Δάνεια / Υποχρεώσεις',
  AccountType.inactive => 'Μη Ενεργά',
};

IconData accountTypeIcon(AccountType type) => switch (type) {
  AccountType.liquid => Icons.account_balance,
  AccountType.creditCard => Icons.credit_card,
  AccountType.investment => Icons.trending_up,
  AccountType.asset => Icons.home_work_outlined,
  AccountType.personalDebts => Icons.people_outline,
  AccountType.loan => Icons.request_quote_outlined,
  AccountType.inactive => Icons.archive_outlined,
};

Color accountTypeColor(AccountType type) => switch (type) {
  AccountType.liquid => const Color(0xFF159A9C),
  AccountType.creditCard => const Color(0xFFD45D4C),
  AccountType.investment => const Color(0xFF356AE6),
  AccountType.asset => const Color(0xFF8A5A44),
  AccountType.personalDebts => const Color(0xFF8A63B8),
  AccountType.loan => const Color(0xFFB5533C),
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
  final Set<AccountType> _collapsedGroups = {};
  double _sidebarWidth = 300;
  Timer? _windowSaveTimer;

  @override
  void initState() {
    super.initState();
    _loadSeedRegister();
    _loadCollapsedGroups();
    _loadSidebarWidth();
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
    return _transactions.where((transaction) {
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
  }

  double get _totalInflow =>
      _transactions.fold(0, (sum, item) => sum + item.inflow);
  double get _totalOutflow =>
      _transactions.fold(0, (sum, item) => sum + item.outflow);
  double get _netChange => _totalInflow - _totalOutflow;

  Map<String, double> get _accountBalances {
    final balances = <String, double>{};
    for (final transaction in _transactions) {
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

  Future<void> _importRegister() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (file == null) {
        setState(() => _loading = false);
        return;
      }
      final text = utf8.decode(await file.readAsBytes());
      final imported = _parseRegister(text);
      setState(() {
        _transactions = imported;
        _loading = false;
        _selectedAccount = null;
        _selectedCategory = null;
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = 'Αποτυχία εισαγωγής: $error';
      });
    }
  }

  Future<void> _loadSeedRegister() async {
    try {
      final text = await rootBundle.loadString('data/private/register.csv');
      final imported = _parseRegister(text);
      if (!mounted) return;
      setState(() => _transactions = imported);
    } catch (_) {
      // The private seed is intentionally optional for other machines.
    }
  }

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

  Widget _buildContent(bool wide) {
    return CustomScrollView(
      slivers: [
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
    final transactions = _filteredTransactions;
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
        const SizedBox(height: 10),
        Card(
          child: transactions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: Text('Δεν βρέθηκαν συναλλαγές.')),
                )
              : _TransactionTable(
                  transactions: transactions,
                  currency: _currency,
                  dateFormat: _dateFormat,
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

  Widget _buildReports() {
    if (_transactions.isEmpty) return _EmptyState(onImport: _importRegister);
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
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'MVP • YNAB CSV import\n$appVersion',
                    style: TextStyle(color: Color(0xFF9FB3C8), fontSize: 12),
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
                    fontSize: 11,
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
              'Εισήγαγε το Register.csv από το YNAB για να ξεκινήσεις.',
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
          label: Text(loading ? 'Εισαγωγή...' : 'Import CSV'),
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

class _TransactionTable extends StatelessWidget {
  const _TransactionTable({
    required this.transactions,
    required this.currency,
    required this.dateFormat,
  });
  final List<Transaction> transactions;
  final NumberFormat currency;
  final DateFormat dateFormat;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: const [
        DataColumn(label: Text('Ημερομηνία')),
        DataColumn(label: Text('Πληρωτής / Έμπορος')),
        DataColumn(label: Text('Κατηγορία')),
        DataColumn(label: Text('Λογαριασμός')),
        DataColumn(label: Text('Ποσό')),
        DataColumn(label: Text('Κατάσταση')),
      ],
      rows: transactions
          .take(250)
          .map(
            (transaction) => DataRow(
              cells: [
                DataCell(Text(dateFormat.format(transaction.date))),
                DataCell(
                  SizedBox(
                    width: 190,
                    child: Text(
                      transaction.payee.isEmpty
                          ? 'Χωρίς όνομα'
                          : transaction.payee,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 180,
                    child: Text(
                      transaction.category.isEmpty
                          ? 'Χωρίς κατηγορία'
                          : transaction.category,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(transaction.account)),
                DataCell(
                  Text(
                    transaction.outflow > 0
                        ? '-${currency.format(transaction.outflow)}'
                        : '+${currency.format(transaction.inflow)}',
                    style: TextStyle(
                      color: transaction.outflow > 0
                          ? const Color(0xFFD45D4C)
                          : const Color(0xFF2D8A5F),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DataCell(Text(transaction.cleared)),
              ],
            ),
          )
          .toList(),
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
              'Ξεκίνα εισάγοντας το Register.csv export από το YNAB.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.upload_file),
              label: const Text('Εισαγωγή Register.csv'),
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
