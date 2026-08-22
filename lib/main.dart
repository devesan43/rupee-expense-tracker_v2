import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as ex;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TransactionType {
  expense,
  income,
  transfer,
}

enum AccountType {
  cash,
  bank,
  creditCard,
  loan,
}

class AccountModel {
  String id;
  String name;
  AccountType type;
  double openingBalance;

  AccountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'openingBalance': openingBalance,
    };
  }

  factory AccountModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return AccountModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: AccountType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AccountType.bank,
      ),
      openingBalance:
          (json['openingBalance'] ?? 0).toDouble(),
    );
  }
}

class TransactionModel {
  String id;
  DateTime date;
  String accountId;
  String category;
  String subCategory;
  String merchant;
  double amount;
  TransactionType type;
  String note;
  String? smsId;
  String? transferToAccountId;

  TransactionModel({
    required this.id,
    required this.date,
    required this.accountId,
    required this.category,
    required this.subCategory,
    required this.merchant,
    required this.amount,
    required this.type,
    required this.note,
    this.smsId,
    this.transferToAccountId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'accountId': accountId,
      'category': category,
      'subCategory': subCategory,
      'merchant': merchant,
      'amount': amount,
      'type': type.name,
      'note': note,
      'smsId': smsId,
      'transferToAccountId': transferToAccountId,
    };
  }

  factory TransactionModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return TransactionModel(
      id: json['id'] ?? '',
      date: DateTime.tryParse(
            json['date'] ?? '',
          ) ??
          DateTime.now(),
      accountId: json['accountId'] ?? '',
      category: json['category'] ?? 'Other',
      subCategory:
          json['subCategory'] ?? '',
      merchant: json['merchant'] ?? '',
      amount:
          (json['amount'] ?? 0).toDouble(),
      type: TransactionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () =>
            TransactionType.expense,
      ),
      note: json['note'] ?? '',
      smsId: json['smsId'],
      transferToAccountId:
          json['transferToAccountId'],
    );
  }
}

class BudgetModel {
  String category;
  double amount;
  int month;
  int year;

  BudgetModel({
    required this.category,
    required this.amount,
    required this.month,
    required this.year,
  });

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'amount': amount,
      'month': month,
      'year': year,
    };
  }

  factory BudgetModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return BudgetModel(
      category:
          json['category'] ?? 'Other',
      amount:
          (json['amount'] ?? 0).toDouble(),
      month: json['month'] ?? 1,
      year: json['year'] ?? 2026,
    );
  }
}

class RecurringModel {
  String id;
  String title;
  String category;
  double amount;
  String accountId;
  int day;
  bool active;
  DateTime? lastCreated;

  RecurringModel({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.accountId,
    required this.day,
    required this.active,
    this.lastCreated,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'amount': amount,
      'accountId': accountId,
      'day': day,
      'active': active,
      'lastCreated':
          lastCreated?.toIso8601String(),
    };
  }

  factory RecurringModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return RecurringModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      category:
          json['category'] ?? 'Other',
      amount:
          (json['amount'] ?? 0).toDouble(),
      accountId:
          json['accountId'] ?? '',
      day: json['day'] ?? 1,
      active: json['active'] ?? true,
      lastCreated:
          json['lastCreated'] == null
              ? null
              : DateTime.tryParse(
                  json['lastCreated'],
                ),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ExpenseTrackerApp(),
  );
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Expense Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      home: const ExpenseTrackerHome(),
    );
  }
}

class ExpenseTrackerHome
    extends StatefulWidget {
  const ExpenseTrackerHome({
    super.key,
  });

  @override
  State<ExpenseTrackerHome> createState() =>
      _ExpenseTrackerHomeState();
}

class _ExpenseTrackerHomeState
    extends State<ExpenseTrackerHome>
    with WidgetsBindingObserver {
  final SmsQuery smsQuery = SmsQuery();

  final LocalAuthentication auth =
      LocalAuthentication();

  final NumberFormat moneyFormat =
      NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  final DateFormat dateFormat =
      DateFormat('dd-MM-yyyy');

  List<AccountModel> accounts = [];

  List<TransactionModel> transactions = [];

  List<BudgetModel> budgets = [];

  List<RecurringModel> recurring = [];

  // ============================================================
  // DEFAULT EXPENSE CATEGORIES
  // ============================================================

  List<String> expenseCategories = [
    'Food',
    'Travel',
    'Bills',
    'Shopping',
    'Education',
    'Medical',
    'EMI',
    'Rent',
    'Insurance',
    'Fuel',
    'Entertainment',
    'Groceries',
    'Recharge',
    'Subscription',
    'Other',
  ];

  // ============================================================
  // DEFAULT INCOME CATEGORIES
  // ============================================================

  List<String> incomeCategories = [
    'Salary',
    'Business Income',
    'Freelance',
    'Interest',
    'Dividend',
    'Bonus',
    'Gift',
    'Refund',
    'Other Income',
  ];

  int selectedTab = 0;

  String searchText = '';

  DateTime? filterFrom;

  DateTime? filterTo;

  String? pin;

  bool biometricEnabled = false;

  int autoLockMinutes = 5;

  bool locked = false;

  DateTime? backgroundTime;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addObserver(this);

    loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .removeObserver(this);

    super.dispose();
  }

  // ============================================================
  // CATEGORY GETTERS
  // ============================================================

  List<String> get categories =>
      expenseCategories;

  List<String> get incomeCategoryList =>
      incomeCategories;

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> loadData() async {
    final prefs =
        await SharedPreferences.getInstance();

    final accountsJson =
        prefs.getString('accounts');

    final transactionsJson =
        prefs.getString('transactions');

    final budgetsJson =
        prefs.getString('budgets');

    final recurringJson =
        prefs.getString('recurring');

    final expenseCategoriesJson =
        prefs.getString(
      'expenseCategories',
    );

    final incomeCategoriesJson =
        prefs.getString(
      'incomeCategories',
    );

    if (accountsJson != null) {
      accounts =
          (jsonDecode(accountsJson) as List)
              .map(
                (e) => AccountModel.fromJson(e),
              )
              .toList();
    }

    if (transactionsJson != null) {
      transactions =
          (jsonDecode(transactionsJson) as List)
              .map(
                (e) =>
                    TransactionModel.fromJson(e),
              )
              .toList();
    }

    if (budgetsJson != null) {
      budgets =
          (jsonDecode(budgetsJson) as List)
              .map(
                (e) =>
                    BudgetModel.fromJson(e),
              )
              .toList();
    }

    if (recurringJson != null) {
      recurring =
          (jsonDecode(recurringJson) as List)
              .map(
                (e) =>
                    RecurringModel.fromJson(e),
              )
              .toList();
    }

    if (expenseCategoriesJson != null) {
      final loaded =
          (jsonDecode(
                expenseCategoriesJson,
              ) as List)
              .map(
                (e) => e.toString(),
              )
              .toList();

      if (loaded.isNotEmpty) {
        expenseCategories = loaded;
      }
    }

    if (incomeCategoriesJson != null) {
      final loaded =
          (jsonDecode(
                incomeCategoriesJson,
              ) as List)
              .map(
                (e) => e.toString(),
              )
              .toList();

      if (loaded.isNotEmpty) {
        incomeCategories = loaded;
      }
    }

    pin = prefs.getString('pin');

    biometricEnabled =
        prefs.getBool('biometric') ?? false;

    autoLockMinutes =
        prefs.getInt('autolock') ?? 5;

    if (accounts.isEmpty) {
      accounts = [
        AccountModel(
          id: 'cash',
          name: 'Cash',
          type: AccountType.cash,
          openingBalance: 0,
        ),
        AccountModel(
          id: 'bank',
          name: 'Bank Account',
          type: AccountType.bank,
          openingBalance: 0,
        ),
        AccountModel(
          id: 'credit',
          name: 'Credit Card',
          type: AccountType.creditCard,
          openingBalance: 0,
        ),
      ];
    }

    await processRecurring();

    await saveData();

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // SAVE DATA
  // ============================================================

  Future<void> saveData() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      'accounts',
      jsonEncode(
        accounts
            .map((e) => e.toJson())
            .toList(),
      ),
    );

    await prefs.setString(
      'transactions',
      jsonEncode(
        transactions
            .map((e) => e.toJson())
            .toList(),
      ),
    );

    await prefs.setString(
      'budgets',
      jsonEncode(
        budgets
            .map((e) => e.toJson())
            .toList(),
      ),
    );

    await prefs.setString(
      'recurring',
      jsonEncode(
        recurring
            .map((e) => e.toJson())
            .toList(),
      ),
    );

    await prefs.setString(
      'expenseCategories',
      jsonEncode(expenseCategories),
    );

    await prefs.setString(
      'incomeCategories',
      jsonEncode(incomeCategories),
    );

    if (pin == null) {
      await prefs.remove('pin');
    } else {
      await prefs.setString(
        'pin',
        pin!,
      );
    }

    await prefs.setBool(
      'biometric',
      biometricEnabled,
    );

    await prefs.setInt(
      'autolock',
      autoLockMinutes,
    );
  }

  // ============================================================
  // AUTO LOCK
  // ============================================================

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.paused ||
        state ==
            AppLifecycleState.inactive) {
      backgroundTime = DateTime.now();
    }

    if (state ==
        AppLifecycleState.resumed) {
      if (backgroundTime != null &&
          pin != null) {
        final difference =
            DateTime.now()
                .difference(
                  backgroundTime!,
                )
                .inMinutes;

        if (difference >=
            autoLockMinutes) {
          setState(() {
            locked = true;
          });
        }
      }
    }
  }

  // ============================================================
  // ACCOUNT BALANCE
  // ============================================================

  double getAccountBalance(
    String accountId,
  ) {
    final account = accounts.firstWhere(
      (a) => a.id == accountId,
      orElse: () => AccountModel(
        id: accountId,
        name: '',
        type: AccountType.bank,
        openingBalance: 0,
      ),
    );

    double balance =
        account.openingBalance;

    for (final transaction
        in transactions) {
      if (transaction.type ==
          TransactionType.transfer) {
        if (transaction.accountId ==
            accountId) {
          balance -= transaction.amount;
        }

        if (transaction.transferToAccountId ==
            accountId) {
          balance += transaction.amount;
        }

        continue;
      }

      if (transaction.accountId ==
          accountId) {
        if (transaction.type ==
            TransactionType.income) {
          balance += transaction.amount;
        } else if (transaction.type ==
            TransactionType.expense) {
          balance -= transaction.amount;
        }
      }
    }

    return balance;
  }

  // ============================================================
  // TOTAL INCOME
  // ============================================================

  double get totalIncome {
    return transactions
        .where(
          (t) =>
              t.type ==
              TransactionType.income,
        )
        .fold(
          0,
          (sum, t) => sum + t.amount,
        );
  }

  // ============================================================
  // TOTAL EXPENSE
  // ============================================================

  double get totalExpense {
    return transactions
        .where(
          (t) =>
              t.type ==
              TransactionType.expense,
        )
        .fold(
          0,
          (sum, t) => sum + t.amount,
        );
  }

  double get savings {
    return totalIncome - totalExpense;
  }

  // ============================================================
  // CREDIT CARD / LOAN OUTSTANDING
  // ============================================================

  double creditOutstanding(
    AccountModel account,
  ) {
    if (account.type !=
            AccountType.creditCard &&
        account.type != AccountType.loan) {
      return 0;
    }

    double outstanding = 0;

    for (final transaction
        in transactions) {
      if (transaction.accountId !=
          account.id) {
        continue;
      }

      if (transaction.type ==
          TransactionType.expense) {
        outstanding += transaction.amount;
      }

      if (transaction.type ==
          TransactionType.income) {
        outstanding -= transaction.amount;
      }
    }

    return outstanding < 0
        ? 0
        : outstanding;
  }

  // ============================================================
  // RECURRING PROCESS
  // ============================================================

  Future<void> processRecurring() async {
    final now = DateTime.now();

    for (final item in recurring) {
      if (!item.active) {
        continue;
      }

      if (now.day < item.day) {
        continue;
      }

      bool create = false;

      if (item.lastCreated == null) {
        create = true;
      } else if (item.lastCreated!.year !=
              now.year ||
          item.lastCreated!.month !=
              now.month) {
        create = true;
      }

      if (!create) {
        continue;
      }

      transactions.add(
        TransactionModel(
          id: DateTime.now()
              .microsecondsSinceEpoch
              .toString(),
          date: DateTime(
            now.year,
            now.month,
            item.day,
          ),
          accountId: item.accountId,
          category: item.category,
          subCategory: 'Recurring',
          merchant: item.title,
          amount: item.amount,
          type: TransactionType.expense,
          note: 'Automatically created',
        ),
      );

      item.lastCreated = DateTime(
        now.year,
        now.month,
        item.day,
      );
    }
  }

  // ============================================================
  // FILTERED TRANSACTIONS
  // ============================================================

  List<TransactionModel>
      get filteredTransactions {
    return transactions.where((t) {
      final query =
          searchText.toLowerCase();

      final searchMatch =
          query.isEmpty ||
              t.category
                  .toLowerCase()
                  .contains(query) ||
              t.subCategory
                  .toLowerCase()
                  .contains(query) ||
              t.merchant
                  .toLowerCase()
                  .contains(query) ||
              t.note
                  .toLowerCase()
                  .contains(query);

      final fromMatch =
          filterFrom == null ||
              !t.date.isBefore(
                filterFrom!,
              );

      final toMatch =
          filterTo == null ||
              !t.date.isAfter(
                DateTime(
                  filterTo!.year,
                  filterTo!.month,
                  filterTo!.day,
                  23,
                  59,
                  59,
                ),
              );

      return searchMatch &&
          fromMatch &&
          toMatch;
    }).toList()
      ..sort(
        (a, b) =>
            b.date.compareTo(a.date),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (locked) {
      return LockScreen(
        biometricEnabled:
            biometricEnabled,
        onBiometric:
            unlockBiometric,
        onPin: (enteredPin) {
          if (enteredPin == pin) {
            setState(() {
              locked = false;
            });
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(
              const SnackBar(
                content:
                    Text('Wrong PIN'),
              ),
            );
          }
        },
      );
    }

    final pages = [
      dashboardPage(),
      transactionsPage(),
      budgetPage(),
      recurringPage(),
      reportsPage(),
      settingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Expense Tracker',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.add),
            onPressed:
                showAddTransaction,
          ),
        ],
      ),
      body: pages[selectedTab],
      bottomNavigationBar:
          NavigationBar(
        selectedIndex:
            selectedTab,
        onDestinationSelected:
            (index) {
          setState(() {
            selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(
              Icons.dashboard_outlined,
            ),
            selectedIcon:
                Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.receipt_long_outlined,
            ),
            selectedIcon: Icon(
              Icons.receipt_long,
            ),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.account_balance_wallet_outlined,
            ),
            selectedIcon: Icon(
              Icons.account_balance_wallet,
            ),
            label: 'Budget',
          ),
          NavigationDestination(
            icon: Icon(Icons.repeat),
            label: 'Recurring',
          ),
          NavigationDestination(
            icon:
                Icon(Icons.bar_chart),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.settings_outlined,
            ),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
    // ============================================================
  // DASHBOARD
  // ============================================================

  Widget dashboardPage() {
    final balances = accounts
        .where(
          (a) =>
              a.type !=
              AccountType.creditCard,
        )
        .fold<double>(
          0,
          (sum, account) =>
              sum +
              getAccountBalance(
                account.id,
              ),
        );

    final totalOutstanding =
        accounts
            .where(
              (a) =>
                  a.type ==
                      AccountType.creditCard ||
                  a.type ==
                      AccountType.loan,
            )
            .fold<double>(
              0,
              (sum, account) =>
                  sum +
                  creditOutstanding(
                    account,
                  ),
            );

    return RefreshIndicator(
      onRefresh: () async {
        await processRecurring();
        await saveData();

        if (mounted) {
          setState(() {});
        }
      },
      child: ListView(
        padding:
            const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Current Balance',
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    moneyFormat.format(
                      balances,
                    ),
                    style:
                        const TextStyle(
                      fontSize: 30,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Savings: ${moneyFormat.format(savings)}',
                    style: TextStyle(
                      color: savings >= 0
                          ? Colors.green
                          : Colors.red,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          if (totalOutstanding > 0)
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.credit_card,
                  color: Colors.red,
                ),
                title: const Text(
                  'Total Outstanding',
                ),
                trailing: Text(
                  moneyFormat.format(
                    totalOutstanding,
                  ),
                  style:
                      const TextStyle(
                    color: Colors.red,
                    fontWeight:
                        FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),

          const SizedBox(
            height: 12,
          ),

          const Text(
            'Accounts & Balances',
            style: TextStyle(
              fontSize: 20,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          ...accounts.map(
            (account) {
              final balance =
                  getAccountBalance(
                account.id,
              );

              final isCredit =
                  account.type ==
                          AccountType
                              .creditCard ||
                      account.type ==
                          AccountType.loan;

              final outstanding =
                  creditOutstanding(
                account,
              );

              return Card(
                child: ListTile(
                  leading:
                      CircleAvatar(
                    child: Icon(
                      accountIcon(
                        account.type,
                      ),
                    ),
                  ),
                  title: Text(
                    account.name,
                  ),
                  subtitle: Text(
                    isCredit
                        ? 'Outstanding: ${moneyFormat.format(outstanding)}'
                        : 'Opening: ${moneyFormat.format(account.openingBalance)}',
                  ),
                  trailing: Text(
                    moneyFormat.format(
                      isCredit
                          ? outstanding
                          : balance,
                    ),
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      color: isCredit ||
                              balance < 0
                          ? Colors.red
                          : null,
                    ),
                  ),
                  onTap: () =>
                      editAccount(
                    account,
                  ),
                ),
              );
            },
          ),

          const SizedBox(
            height: 12,
          ),

          Row(
            children: [
              Expanded(
                child: summaryCard(
                  'Income',
                  totalIncome,
                  Colors.green,
                  Icons
                      .arrow_downward,
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: summaryCard(
                  'Expense',
                  totalExpense,
                  Colors.red,
                  Icons.arrow_upward,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          Card(
            child: ListTile(
              leading: const Icon(
                Icons.sms,
              ),
              title: const Text(
                'Scan Bank SMS',
              ),
              subtitle: const Text(
                'Detect debit, credit and UPI transactions',
              ),
              trailing:
                  const Icon(
                Icons.chevron_right,
              ),
              onTap: scanSms,
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          Card(
            child: ListTile(
              leading: const Icon(
                Icons.add_circle_outline,
              ),
              title: const Text(
                'Add Transaction',
              ),
              subtitle: const Text(
                'Manually add income or expense',
              ),
              trailing:
                  const Icon(
                Icons.chevron_right,
              ),
              onTap:
                  showAddTransaction,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY CARD
  // ============================================================

  Widget summaryCard(
    String title,
    double value,
    Color color,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(14),
        child: Column(
          children: [
            Icon(
              icon,
              color: color,
            ),
            const SizedBox(
              height: 5,
            ),
            Text(title),
            const SizedBox(
              height: 5,
            ),
            Text(
              moneyFormat.format(
                value,
              ),
              style: TextStyle(
                color: color,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ACCOUNT ICON
  // ============================================================

  IconData accountIcon(
    AccountType type,
  ) {
    switch (type) {
      case AccountType.cash:
        return Icons.payments;

      case AccountType.bank:
        return Icons.account_balance;

      case AccountType.creditCard:
        return Icons.credit_card;

      case AccountType.loan:
        return Icons.request_quote;
    }
  }

  // ============================================================
  // TRANSACTIONS PAGE
  // ============================================================

  Widget transactionsPage() {
    final list =
        filteredTransactions;

    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.all(12),
          child: TextField(
            decoration:
                InputDecoration(
              prefixIcon:
                  const Icon(
                Icons.search,
              ),
              suffixIcon:
                  IconButton(
                icon: const Icon(
                  Icons.date_range,
                ),
                onPressed:
                    selectDateRange,
              ),
              hintText:
                  'Search transactions',
              border:
                  const OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                searchText = value;
              });
            },
          ),
        ),

        if (filterFrom != null ||
            filterTo != null)
          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter: '
                    '${filterFrom == null ? '' : dateFormat.format(filterFrom!)}'
                    ' - '
                    '${filterTo == null ? '' : dateFormat.format(filterTo!)}',
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.clear,
                  ),
                  onPressed: () {
                    setState(() {
                      filterFrom = null;
                      filterTo = null;
                    });
                  },
                ),
              ],
            ),
          ),

        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text(
                    'No transactions',
                  ),
                )
              : ListView.builder(
                  itemCount:
                      list.length,
                  itemBuilder:
                      (context, index) {
                    final transaction =
                        list[index];

                    final income =
                        transaction.type ==
                            TransactionType
                                .income;

                    final transfer =
                        transaction.type ==
                            TransactionType
                                .transfer;

                    return Card(
                      margin:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: ListTile(
                        leading:
                            CircleAvatar(
                          child: Icon(
                            transfer
                                ? Icons
                                    .swap_horiz
                                : income
                                    ? Icons
                                        .arrow_downward
                                    : Icons
                                        .arrow_upward,
                          ),
                        ),
                        title: Text(
                          transaction
                                  .merchant
                                  .isEmpty
                              ? transaction
                                  .category
                              : transaction
                                  .merchant,
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                        ),
                        subtitle:
                            Text(
                          '${transaction.category}'
                          '${transaction.subCategory.isEmpty ? '' : ' • ${transaction.subCategory}'}'
                          '\n${dateFormat.format(transaction.date)}',
                          maxLines: 2,
                        ),
                        isThreeLine:
                            true,
                        trailing:
                            Text(
                          transfer
                              ? moneyFormat.format(
                                  transaction
                                      .amount,
                                )
                              : '${income ? '+' : '-'}${moneyFormat.format(transaction.amount)}',
                          style: TextStyle(
                            color: transfer
                                ? Colors
                                    .blue
                                : income
                                    ? Colors
                                        .green
                                    : Colors
                                        .red,
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                        ),
                        onTap: () =>
                            editTransaction(
                          transaction,
                        ),
                        onLongPress: () =>
                            deleteTransaction(
                          transaction,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ============================================================
  // CATEGORY SELECTION
  // ============================================================

  List<String> categoriesForType(
    TransactionType type,
  ) {
    if (type ==
        TransactionType.income) {
      return incomeCategories;
    }

    return expenseCategories;
  }

  // ============================================================
  // ADD CATEGORY
  // ============================================================

  Future<String?> addCategoryDialog({
    required TransactionType type,
    String? currentCategory,
  }) async {
    final controller =
        TextEditingController();

    final list =
        categoriesForType(type);

    final categoryName =
        type == TransactionType.income
            ? 'Income'
            : 'Expense';

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Add $categoryName Category',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization:
                TextCapitalization
                    .words,
            decoration:
                InputDecoration(
              labelText:
                  'Category name',
              hintText:
                  'Example: Salary / Food',
              border:
                  const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                dialogContext,
              ),
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name =
                    controller.text
                        .trim();

                if (name.isEmpty) {
                  return;
                }

                final exists =
                    list.any(
                  (item) =>
                      item.toLowerCase() ==
                      name.toLowerCase(),
                );

                if (exists) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Category already exists.',
                      ),
                    ),
                  );
                  return;
                }

                if (type ==
                    TransactionType
                        .income) {
                  incomeCategories
                      .add(name);
                } else {
                  expenseCategories
                      .add(name);
                }

                await saveData();

                if (mounted) {
                  Navigator.pop(
                    dialogContext,
                    name,
                  );

                  setState(() {});
                }
              },
              child:
                  const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // MANAGE CATEGORIES
  // ============================================================

  Future<void>
      manageCategories() async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            title:
                const Text(
              'Manage Categories',
            ),
            content: SizedBox(
              width:
                  double.maxFinite,
              height: 450,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(
                        text: 'Expense',
                      ),
                      Tab(
                        text: 'Income',
                      ),
                    ],
                  ),
                  Expanded(
                    child:
                        TabBarView(
                      children: [
                        categoryManagementList(
                          expenseCategories,
                          false,
                        ),
                        categoryManagementList(
                          incomeCategories,
                          true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                  dialogContext,
                ),
                child:
                    const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget categoryManagementList(
    List<String> list,
    bool income,
  ) {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.only(
            top: 8,
            bottom: 8,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await addCategoryDialog(
                  type: income
                      ? TransactionType
                          .income
                      : TransactionType
                          .expense,
                );

                if (mounted) {
                  setState(() {});
                }
              },
              icon: const Icon(
                Icons.add,
              ),
              label: const Text(
                'Add Category',
              ),
            ),
          ),
        ),

        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder:
                (context, index) {
              final category =
                  list[index];

              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    category
                        .substring(
                          0,
                          1,
                        )
                        .toUpperCase(),
                  ),
                ),
                title:
                    Text(category),
                trailing:
                    IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                  onPressed:
                      () async {
                    await deleteCategory(
                      category,
                      income,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DELETE CATEGORY
  // ============================================================

  Future<void> deleteCategory(
    String category,
    bool income,
  ) async {
    final used =
        transactions.any(
      (transaction) =>
          transaction.category ==
          category,
    );

    if (used) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'This category is already used in transactions and cannot be deleted.',
            ),
          ),
        );
      }

      return;
    }

    final result =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          AlertDialog(
        title: const Text(
          'Delete Category?',
        ),
        content: Text(
          'Delete "$category"?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              false,
            ),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              true,
            ),
            child:
                const Text('Delete'),
          ),
        ],
      ),
    );

    if (result != true) {
      return;
    }

    if (income) {
      incomeCategories
          .remove(category);
    } else {
      expenseCategories
          .remove(category);
    }

    await saveData();

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // ADD / EDIT TRANSACTION
  // ============================================================

  Future<void>
      showAddTransaction() async {
    await transactionDialog();
  }

  Future<void> transactionDialog({
    TransactionModel? existing,
  }) async {
    if (accounts.isEmpty) {
      return;
    }

    TransactionType type =
        existing?.type ??
            TransactionType.expense;

    if (type ==
        TransactionType.transfer) {
      type = TransactionType.expense;
    }

    AccountModel account =
        accounts.firstWhere(
      (a) =>
          a.id ==
          (existing?.accountId ??
              accounts.first.id),
      orElse: () =>
          accounts.first,
    );

    final initialCategories =
        categoriesForType(type);

    String category =
        existing?.category ??
            (initialCategories.isNotEmpty
                ? initialCategories.first
                : 'Other');

    if (!categoriesForType(type)
        .contains(category)) {
      category =
          categoriesForType(type)
              .first;
    }

    final subController =
        TextEditingController(
      text:
          existing?.subCategory ?? '',
    );

    final amountController =
        TextEditingController(
      text: existing == null
          ? ''
          : existing.amount
              .toString(),
    );

    final merchantController =
        TextEditingController(
      text:
          existing?.merchant ?? '',
    );

    final noteController =
        TextEditingController(
      text:
          existing?.note ?? '',
    );

    DateTime date =
        existing?.date ??
            DateTime.now();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder:
              (
                context,
                setDialogState,
              ) {
            final availableCategories =
                categoriesForType(
              type,
            );

            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Add Transaction'
                    : 'Edit Transaction',
              ),
              content:
                  SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<
                        TransactionType>(
                      value: type,
                      items: const [
                        DropdownMenuItem(
                          value:
                              TransactionType
                                  .expense,
                          child: Text(
                            'Expense',
                          ),
                        ),
                        DropdownMenuItem(
                          value:
                              TransactionType
                                  .income,
                          child: Text(
                            'Income',
                          ),
                        ),
                      ],
                      onChanged:
                          (value) {
                        if (value !=
                            null) {
                          setDialogState(
                            () {
                              type =
                                  value;

                              final cats =
                                  categoriesForType(
                                type,
                              );

                              if (!cats
                                  .contains(
                                category,
                              )) {
                                category =
                                    cats.first;
                              }
                            },
                          );
                        }
                      },
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Type',
                      ),
                    ),

                    DropdownButtonFormField<
                        AccountModel>(
                      value: account,
                      items: accounts
                          .map(
                            (a) =>
                                DropdownMenuItem(
                              value: a,
                              child:
                                  Text(
                                a.name,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged:
                          (value) {
                        if (value !=
                            null) {
                          setDialogState(
                            () =>
                                account =
                                    value,
                          );
                        }
                      },
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Account',
                      ),
                    ),

                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .end,
                      children: [
                        Expanded(
                          child:
                              DropdownButtonFormField<
                                  String>(
                            value:
                                availableCategories
                                        .contains(
                                      category,
                                    )
                                    ? category
                                    : null,
                            items:
                                availableCategories
                                    .map(
                                      (
                                        c,
                                      ) =>
                                          DropdownMenuItem(
                                        value:
                                            c,
                                        child:
                                            Text(
                                          c,
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                (value) {
                              if (value !=
                                  null) {
                                setDialogState(
                                  () =>
                                      category =
                                          value,
                                );
                              }
                            },
                            decoration:
                                const InputDecoration(
                              labelText:
                                  'Category',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip:
                              'Add Category',
                          icon:
                              const Icon(
                            Icons
                                .add_circle,
                          ),
                          onPressed:
                              () async {
                            final result =
                                await addCategoryDialog(
                              type: type,
                              currentCategory:
                                  category,
                            );

                            if (result !=
                                null) {
                              setDialogState(
                                () =>
                                    category =
                                        result,
                              );
                            }
                          },
                        ),
                      ],
                    ),

                    TextField(
                      controller:
                          subController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Sub-category',
                      ),
                    ),

                    TextField(
                      controller:
                          amountController,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal:
                            true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Amount',
                        prefixText:
                            '₹ ',
                      ),
                    ),

                    TextField(
                      controller:
                          merchantController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Merchant',
                      ),
                    ),

                    TextField(
                      controller:
                          noteController,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Note',
                      ),
                    ),

                    ListTile(
                      contentPadding:
                          EdgeInsets.zero,
                      title: const Text(
                        'Date',
                      ),
                      subtitle:
                          Text(
                        dateFormat
                            .format(
                          date,
                        ),
                      ),
                      trailing:
                          const Icon(
                        Icons
                            .calendar_today,
                      ),
                      onTap:
                          () async {
                        final result =
                            await showDatePicker(
                          context:
                              context,
                          firstDate:
                              DateTime(
                            2020,
                          ),
                          lastDate:
                              DateTime(
                            2100,
                          ),
                          initialDate:
                              date,
                        );

                        if (result !=
                            null) {
                          setDialogState(
                            () =>
                                date =
                                    result,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(
                    dialogContext,
                  ),
                  child:
                      const Text(
                    'Cancel',
                  ),
                ),
                FilledButton(
                  onPressed:
                      () async {
                    final amount =
                        double.tryParse(
                              amountController
                                  .text
                                  .replaceAll(
                                ',',
                                '',
                              ),
                            ) ??
                            0;

                    if (amount <= 0) {
                      ScaffoldMessenger
                              .of(
                        context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enter a valid amount.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (existing ==
                        null) {
                      transactions.add(
                        TransactionModel(
                          id: DateTime
                              .now()
                              .microsecondsSinceEpoch
                              .toString(),
                          date: date,
                          accountId:
                              account.id,
                          category:
                              category,
                          subCategory:
                              subController
                                  .text
                                  .trim(),
                          merchant:
                              merchantController
                                  .text
                                  .trim(),
                          amount:
                              amount,
                          type: type,
                          note:
                              noteController
                                  .text
                                  .trim(),
                        ),
                      );
                    } else {
                      existing.date =
                          date;

                      existing
                              .accountId =
                          account.id;

                      existing.category =
                          category;

                      existing
                              .subCategory =
                          subController
                              .text
                              .trim();

                      existing.merchant =
                          merchantController
                              .text
                              .trim();

                      existing.amount =
                          amount;

                      existing.type =
                          type;

                      existing.note =
                          noteController
                              .text
                              .trim();
                    }

                    await saveData();

                    if (mounted) {
                      Navigator.pop(
                        dialogContext,
                      );

                      setState(
                        () {},
                      );
                    }
                  },
                  child:
                      const Text(
                    'Save',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // EDIT TRANSACTION
  // ============================================================

  Future<void> editTransaction(
    TransactionModel transaction,
  ) async {
    await transactionDialog(
      existing: transaction,
    );
  }

  // ============================================================
  // DELETE TRANSACTION
  // ============================================================

  Future<void>
      deleteTransaction(
    TransactionModel transaction,
  ) async {
    final result =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          AlertDialog(
        title: const Text(
          'Delete transaction?',
        ),
        content: Text(
          '${transaction.merchant.isEmpty ? transaction.category : transaction.merchant}\n'
          '${moneyFormat.format(transaction.amount)}',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              false,
            ),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              dialogContext,
              true,
            ),
            child:
                const Text('Delete'),
          ),
        ],
      ),
    );

    if (result != true) {
      return;
    }

    transactions.removeWhere(
      (t) => t.id == transaction.id,
    );

    await saveData();

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // DATE FILTER
  // ============================================================

  Future<void>
      selectDateRange() async {
    final range =
        await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange:
          filterFrom != null &&
                  filterTo != null
              ? DateTimeRange(
                  start: filterFrom!,
                  end: filterTo!,
                )
              : null,
    );

    if (range != null) {
      setState(() {
        filterFrom =
            range.start;

        filterTo =
            range.end;
      });
    }  Widget reportsPage() {
    final categoryTotals = <String, double>{};

    for (final transaction in transactions) {
      if (transaction.type == TransactionType.expense) {
        categoryTotals[transaction.category] =
            (categoryTotals[transaction.category] ?? 0) +
                transaction.amount;
      }
    }

    final entries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: exportExcel,
                icon: const Icon(Icons.table_chart),
                label: const Text('Excel'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: exportPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 15),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Financial Summary',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 15),

                summaryCard(
                  'Total Income',
                  totalIncome,
                  Colors.green,
                  Icons.arrow_downward,
                ),

                const SizedBox(height: 8),

                summaryCard(
                  'Total Expense',
                  totalExpense,
                  Colors.red,
                  Icons.arrow_upward,
                ),

                const SizedBox(height: 8),

                summaryCard(
                  'Savings',
                  savings,
                  savings >= 0 ? Colors.green : Colors.red,
                  Icons.savings,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 15),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Income vs Expense',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      borderData: FlBorderData(
                        show: false,
                      ),
                      gridData: const FlGridData(
                        show: false,
                      ),
                      titlesData: const FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                          ),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                      ),
                      barGroups: [
                        BarChartGroupData(
                          x: 0,
                          barRods: [
                            BarChartRodData(
                              toY: totalIncome,
                              width: 40,
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                          ],
                        ),
                        BarChartGroupData(
                          x: 1,
                          barRods: [
                            BarChartRodData(
                              toY: totalExpense,
                              width: 40,
                              borderRadius:
                                  BorderRadius.circular(4),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                const Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceEvenly,
                  children: [
                    Text('Income'),
                    Text('Expense'),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 15),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Category-wise Expense',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(15),
                    child: Center(
                      child: Text(
                        'No expense data',
                      ),
                    ),
                  ),

                ...entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: const Icon(
                        Icons.category,
                      ),
                    ),
                    title: Text(entry.key),
                    trailing: Text(
                      moneyFormat.format(entry.value),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget settingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.account_balance,
            ),
            title: const Text(
              'Accounts',
            ),
            subtitle: const Text(
              'Cash, bank, credit card and loan',
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: manageAccounts,
          ),
        ),

        Card(
          child: ListTile(
            leading: const Icon(
              Icons.swap_horiz,
            ),
            title: const Text(
              'Account Transfer',
            ),
            subtitle: const Text(
              'Transfer money between accounts',
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: transferMoney,
          ),
        ),

        Card(
          child: ListTile(
            leading: const Icon(
              Icons.sms,
            ),
            title: const Text(
              'SMS Automation',
            ),
            subtitle: const Text(
              'Scan bank SMS for debit and credit transactions',
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: scanSms,
          ),
        ),

        Card(
          child: ListTile(
            leading: const Icon(
              Icons.lock,
            ),
            title: const Text(
              'Security',
            ),
            subtitle: Text(
              pin == null
                  ? 'PIN not configured'
                  : 'PIN enabled • Auto-lock $autoLockMinutes min',
            ),
            trailing: const Icon(
              Icons.chevron_right,
            ),
            onTap: securitySettings,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TRANSACTION DIALOG
  // ============================================================

  Future<void> showAddTransaction() async {
    await transactionDialog();
  }

  Future<void> transactionDialog({
    TransactionModel? existing,
  }) async {
    if (accounts.isEmpty) {
      return;
    }

    TransactionType type =
        existing?.type ?? TransactionType.expense;

    AccountModel account = accounts.firstWhere(
      (a) => a.id == (existing?.accountId ?? accounts.first.id),
      orElse: () => accounts.first,
    );

    String category =
        existing?.category ?? categories.first;

    final subController = TextEditingController(
      text: existing?.subCategory ?? '',
    );

    final amountController = TextEditingController(
      text: existing == null
          ? ''
          : existing.amount.toString(),
    );

    final merchantController = TextEditingController(
      text: existing?.merchant ?? '',
    );

    final noteController = TextEditingController(
      text: existing?.note ?? '',
    );

    DateTime date =
        existing?.date ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Add Transaction'
                    : 'Edit Transaction',
              ),

              content: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<TransactionType>(
                      value: type,
                      items: const [
                        DropdownMenuItem(
                          value: TransactionType.expense,
                          child: Text('Expense'),
                        ),
                        DropdownMenuItem(
                          value: TransactionType.income,
                          child: Text('Income'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            type = value;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Transaction Type',
                      ),
                    ),

                    DropdownButtonFormField<AccountModel>(
                      value: account,
                      items: accounts.map(
                        (a) {
                          return DropdownMenuItem(
                            value: a,
                            child: Text(a.name),
                          );
                        },
                      ).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            account = value;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Account',
                      ),
                    ),

                    DropdownButtonFormField<String>(
                      value: category,
                      items: categories.map(
                        (c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(c),
                          );
                        },
                      ).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            category = value;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Category',
                      ),
                    ),

                    TextField(
                      controller: subController,
                      decoration: const InputDecoration(
                        labelText: 'Sub-category',
                      ),
                    ),

                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '₹ ',
                      ),
                    ),

                    TextField(
                      controller: merchantController,
                      decoration: const InputDecoration(
                        labelText: 'Merchant',
                      ),
                    ),

                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                      ),
                    ),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(
                        dateFormat.format(date),
                      ),
                      trailing: const Icon(
                        Icons.calendar_today,
                      ),
                      onTap: () async {
                        final result =
                            await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: date,
                        );

                        if (result != null) {
                          setDialogState(() {
                            date = result;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),

                FilledButton(
                  onPressed: () async {
                    final amount =
                        double.tryParse(
                              amountController.text
                                  .trim(),
                            ) ??
                            0;

                    if (amount <= 0) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enter a valid amount.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (existing == null) {
                      transactions.add(
                        TransactionModel(
                          id: DateTime.now()
                              .microsecondsSinceEpoch
                              .toString(),
                          date: date,
                          accountId: account.id,
                          category: category,
                          subCategory:
                              subController.text.trim(),
                          merchant:
                              merchantController.text.trim(),
                          amount: amount,
                          type: type,
                          note:
                              noteController.text.trim(),
                        ),
                      );
                    } else {
                      existing.date = date;
                      existing.accountId = account.id;
                      existing.category = category;
                      existing.subCategory =
                          subController.text.trim();
                      existing.merchant =
                          merchantController.text.trim();
                      existing.amount = amount;
                      existing.type = type;
                      existing.note =
                          noteController.text.trim();
                    }

                    await saveData();

                    if (!mounted) return;

                    Navigator.pop(dialogContext);

                    setState(() {});
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> editTransaction(
    TransactionModel transaction,
  ) async {
    await transactionDialog(
      existing: transaction,
    );
  }

  Future<void> deleteTransaction(
    TransactionModel transaction,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Delete transaction?',
          ),
          content: Text(
            '${transaction.merchant.isEmpty ? transaction.category : transaction.merchant}\n'
            '${moneyFormat.format(transaction.amount)}',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      transactions.removeWhere(
        (t) => t.id == transaction.id,
      );

      await saveData();

      if (mounted) {
        setState(() {});
      }
    }
  }

  // ============================================================
  // ACCOUNT MANAGEMENT
  // ============================================================

  Future<void> manageAccounts() async {
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Accounts'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ...accounts.map(
                  (account) {
                    return ListTile(
                      leading: Icon(
                        accountIcon(account.type),
                      ),
                      title: Text(account.name),
                      subtitle: Text(
                        moneyFormat.format(
                          getAccountBalance(
                            account.id,
                          ),
                        ),
                      ),
                      trailing: const Icon(
                        Icons.edit,
                      ),
                      onTap: () async {
                        Navigator.pop(context);

                        await editAccount(
                          account,
                        );
                      },
                    );
                  },
                ),

                const Divider(),

                ListTile(
                  leading: const Icon(
                    Icons.add,
                  ),
                  title: const Text(
                    'Add Account',
                  ),
                  onTap: () async {
                    Navigator.pop(context);

                    await addAccount();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> addAccount() async {
    final nameController =
        TextEditingController();

    final balanceController =
        TextEditingController();

    AccountType type =
        AccountType.bank;

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Add Account',
              ),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller:
                          nameController,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Account name',
                      ),
                    ),

                    DropdownButtonFormField<
                        AccountType>(
                      value: type,
                      items: AccountType.values.map(
                        (item) {
                          return DropdownMenuItem(
                            value: item,
                            child: Text(
                              accountTypeName(
                                item,
                              ),
                            ),
                          );
                        },
                      ).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            type = value;
                          });
                        }
                      },
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Account type',
                      ),
                    ),

                    TextField(
                      controller:
                          balanceController,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Opening balance',
                        prefixText: '₹ ',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Cancel',
                  ),
                ),

                FilledButton(
                  onPressed: () async {
                    final balance =
                        double.tryParse(
                              balanceController
                                  .text
                                  .trim(),
                            ) ??
                            0;

                    accounts.add(
                      AccountModel(
                        id: DateTime.now()
                            .microsecondsSinceEpoch
                            .toString(),
                        name: nameController
                                .text
                                .trim()
                                .isEmpty
                            ? 'Account'
                            : nameController
                                .text
                                .trim(),
                        type: type,
                        openingBalance:
                            balance,
                      ),
                    );

                    await saveData();

                    if (!mounted) return;

                    Navigator.pop(context);

                    setState(() {});
                  },
                  child: const Text(
                    'Save',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> editAccount(
    AccountModel account,
  ) async {
    final nameController =
        TextEditingController(
      text: account.name,
    );

    final balanceController =
        TextEditingController(
      text: account.openingBalance
          .toString(),
    );

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Edit Account',
          ),
          content: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              TextField(
                controller:
                    nameController,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Account name',
                ),
              ),

              TextField(
                controller:
                    balanceController,
                keyboardType:
                    const TextInputType
                        .numberWithOptions(
                  decimal: true,
                ),
                decoration:
                    const InputDecoration(
                  labelText:
                      'Opening balance',
                  prefixText: '₹ ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'Cancel',
              ),
            ),

            FilledButton(
              onPressed: () async {
                account.name =
                    nameController.text.trim();

                account.openingBalance =
                    double.tryParse(
                          balanceController
                              .text
                              .trim(),
                        ) ??
                        0;

                await saveData();

                if (!mounted) return;

                Navigator.pop(context);

                setState(() {});
              },
              child: const Text(
                'Save',
              ),
            ),
          ],
        );
      },
    );
  }

  String accountTypeName(
    AccountType type,
  ) {
    switch (type) {
      case AccountType.cash:
        return 'Cash';

      case AccountType.bank:
        return 'Bank Account';

      case AccountType.creditCard:
        return 'Credit Card';

      case AccountType.loan:
        return 'Loan';
    }
  }

  IconData accountIcon(
    AccountType type,
  ) {
    switch (type) {
      case AccountType.cash:
        return Icons.payments;

      case AccountType.bank:
        return Icons.account_balance;

      case AccountType.creditCard:
        return Icons.credit_card;

      case AccountType.loan:
        return Icons.request_quote;
    }
  } 
    // ============================================================
  // EXPORT
  // ============================================================

  Future<void> exportExcel() async {
    try {
      final workbook = ex.Excel.createExcel();

      final sheet = workbook['Transactions'];

      sheet.appendRow([
        ex.TextCellValue('Date'),
        ex.TextCellValue('Account'),
        ex.TextCellValue('Type'),
        ex.TextCellValue('Category'),
        ex.TextCellValue('Sub-category'),
        ex.TextCellValue('Merchant'),
        ex.TextCellValue('Amount'),
        ex.TextCellValue('Note'),
      ]);

      for (final transaction in transactions) {
        final matchingAccounts = accounts.where(
          (a) => a.id == transaction.accountId,
        );

        final account = matchingAccounts.isNotEmpty
            ? matchingAccounts.first
            : null;

        sheet.appendRow([
          ex.TextCellValue(
            dateFormat.format(transaction.date),
          ),
          ex.TextCellValue(
            account?.name ?? 'Unknown',
          ),
          ex.TextCellValue(
            transaction.type.name,
          ),
          ex.TextCellValue(
            transaction.category,
          ),
          ex.TextCellValue(
            transaction.subCategory,
          ),
          ex.TextCellValue(
            transaction.merchant,
          ),
          ex.DoubleCellValue(
            transaction.amount,
          ),
          ex.TextCellValue(
            transaction.note,
          ),
        ]);
      }

      final bytes = workbook.encode();

      if (bytes == null) {
        return;
      }

      final directory =
          await getApplicationDocumentsDirectory();

      final file = File(
        '${directory.path}/Expense_Tracker.xlsx',
      );

      await file.writeAsBytes(bytes);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Excel file created:\n${file.path}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Excel export failed: $e',
          ),
        ),
      );
    }
  }

  Future<void> exportPdf() async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          build: (context) {
            return [
              pw.Text(
                'Expense Tracker',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 12),

              pw.Text(
                'Financial Summary',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 8),

              pw.Text(
                'Income: ${moneyFormat.format(totalIncome)}',
              ),

              pw.Text(
                'Expense: ${moneyFormat.format(totalExpense)}',
              ),

              pw.Text(
                'Savings: ${moneyFormat.format(savings)}',
              ),

              pw.SizedBox(height: 20),

              pw.TableHelper.fromTextArray(
                headers: [
                  'Date',
                  'Category',
                  'Merchant',
                  'Type',
                  'Amount',
                ],
                data: transactions.map(
                  (transaction) {
                    return [
                      dateFormat.format(
                        transaction.date,
                      ),
                      transaction.category,
                      transaction.merchant,
                      transaction.type.name,
                      moneyFormat.format(
                        transaction.amount,
                      ),
                    ];
                  },
                ).toList(),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async {
          return pdf.save();
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PDF export failed: $e',
          ),
        ),
      );
    }
  }
}

// ============================================================
// LOCK SCREEN
// ============================================================

class LockScreen extends StatefulWidget {
  final bool biometricEnabled;

  final Future<void> Function()
      onBiometric;

  final void Function(String)
      onPin;

  const LockScreen({
    super.key,
    required this.biometricEnabled,
    required this.onBiometric,
    required this.onPin,
  });

  @override
  State<LockScreen> createState() =>
      _LockScreenState();
}

class _LockScreenState
    extends State<LockScreen> {
  final TextEditingController controller =
      TextEditingController();

  @override
  void initState() {
    super.initState();

    if (widget.biometricEnabled) {
      WidgetsBinding.instance
          .addPostFrameCallback(
        (_) async {
          await widget.onBiometric();
        },
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock,
                  size: 80,
                ),

                const SizedBox(height: 20),

                const Text(
                  'Expense Tracker',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'Enter your PIN to continue',
                  style: TextStyle(
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: controller,
                  keyboardType:
                      TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter
                        .digitsOnly,
                  ],
                  decoration:
                      const InputDecoration(
                    labelText: 'PIN',
                    border:
                        OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    widget.onPin(value);
                  },
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      widget.onPin(
                        controller.text,
                      );
  // ============================================================
  // EXPORT
  // ============================================================

  Future<void> exportExcel() async {
    try {
      final workbook = ex.Excel.createExcel();

      final sheet = workbook['Transactions'];

      sheet.appendRow([
        ex.TextCellValue('Date'),
        ex.TextCellValue('Account'),
        ex.TextCellValue('Type'),
        ex.TextCellValue('Category'),
        ex.TextCellValue('Sub-category'),
        ex.TextCellValue('Merchant'),
        ex.TextCellValue('Amount'),
        ex.TextCellValue('Note'),
      ]);

      for (final transaction in transactions) {
        final matchingAccounts = accounts.where(
          (a) => a.id == transaction.accountId,
        );

        final account =
            matchingAccounts.isNotEmpty
                ? matchingAccounts.first
                : null;

        sheet.appendRow([
          ex.TextCellValue(
            dateFormat.format(transaction.date),
          ),
          ex.TextCellValue(
            account?.name ?? 'Unknown',
          ),
          ex.TextCellValue(
            transaction.type.name,
          ),
          ex.TextCellValue(
            transaction.category,
          ),
          ex.TextCellValue(
            transaction.subCategory,
          ),
          ex.TextCellValue(
            transaction.merchant,
          ),
          ex.DoubleCellValue(
            transaction.amount,
          ),
          ex.TextCellValue(
            transaction.note,
          ),
        ]);
      }

      final bytes = workbook.encode();

      if (bytes == null) {
        return;
      }

      final directory =
          await getApplicationDocumentsDirectory();

      final file = File(
        '${directory.path}/Expense_Tracker.xlsx',
      );

      await file.writeAsBytes(bytes);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Excel file created successfully.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Excel export failed: $e',
          ),
        ),
      );
    }
  }

  Future<void> exportPdf() async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          build: (context) {
            return [
              pw.Text(
                'Expense Tracker',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 12),

              pw.Text(
                'Financial Summary',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 8),

              pw.Text(
                'Income: ${moneyFormat.format(totalIncome)}',
              ),

              pw.Text(
                'Expense: ${moneyFormat.format(totalExpense)}',
              ),

              pw.Text(
                'Savings: ${moneyFormat.format(savings)}',
              ),

              pw.SizedBox(height: 20),

              pw.TableHelper.fromTextArray(
                headers: [
                  'Date',
                  'Category',
                  'Merchant',
                  'Type',
                  'Amount',
                ],
                data: transactions.map(
                  (transaction) => [
                    dateFormat.format(
                      transaction.date,
                    ),
                    transaction.category,
                    transaction.merchant,
                    transaction.type.name,
                    moneyFormat.format(
                      transaction.amount,
                    ),
                  ],
                ).toList(),
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async {
          return pdf.save();
        },
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PDF export failed: $e',
          ),
        ),
      );
    }
  }
} // <-- THIS closes ExpenseTrackerHome State


// ============================================================
// LOCK SCREEN
// ============================================================

class LockScreen extends StatefulWidget {
  final bool biometricEnabled;
  final Future<void> Function() onBiometric;
  final void Function(String) onPin;

  const LockScreen({
    super.key,
    required this.biometricEnabled,
    required this.onBiometric,
    required this.onPin,
  });

  @override
  State<LockScreen> createState() =>
      _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final TextEditingController controller =
      TextEditingController();

  @override
  void initState() {
    super.initState();

    if (widget.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) async {
          await widget.onBiometric();
        },
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock,
                  size: 80,
                ),

                const SizedBox(height: 20),

                const Text(
                  'Expense Tracker',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'Enter your PIN to continue',
                  style: TextStyle(
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    widget.onPin(value);
                  },
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      widget.onPin(
                        controller.text,
                      );
                    },
                    icon: const Icon(
                      Icons.lock_open,
                    ),
                    label: const Text(
                      'Unlock',
                    ),
                  ),
                ),

                if (widget.biometricEnabled)
                  const SizedBox(height: 10),

                if (widget.biometricEnabled)
                  TextButton.icon(
                    onPressed: () async {
                      await widget.onBiometric();
                    },
                    icon: const Icon(
                      Icons.fingerprint,
                      size: 28,
                    ),
                    label: const Text(
                      'Use fingerprint',
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
