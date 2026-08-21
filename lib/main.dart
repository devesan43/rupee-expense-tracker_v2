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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ExpenseTrackerApp());
}

final NumberFormat moneyFormat = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

final DateFormat dateFormat = DateFormat('dd-MM-yyyy');

enum AccountType {
  cash,
  bank,
  creditCard,
  loan,
}

enum TransactionType {
  expense,
  income,
  transfer,
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

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    return AccountModel(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Account',
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
  String? transferToAccountId;
  String? smsId;

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
    this.transferToAccountId,
    this.smsId,
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
      'transferToAccountId': transferToAccountId,
      'smsId': smsId,
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
      subCategory: json['subCategory'] ?? '',
      merchant: json['merchant'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      type: TransactionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TransactionType.expense,
      ),
      note: json['note'] ?? '',
      transferToAccountId:
          json['transferToAccountId'],
      smsId: json['smsId'],
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
      category: json['category'] ?? 'Other',
      amount: (json['amount'] ?? 0).toDouble(),
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
      category: json['category'] ?? 'Other',
      amount: (json['amount'] ?? 0).toDouble(),
      accountId: json['accountId'] ?? '',
      day: json['day'] ?? 1,
      active: json['active'] ?? true,
      lastCreated: json['lastCreated'] == null
          ? null
          : DateTime.tryParse(
              json['lastCreated'],
            ),
    );
  }
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const ExpenseHome(),
    );
  }
}

class ExpenseHome extends StatefulWidget {
  const ExpenseHome({super.key});

  @override
  State<ExpenseHome> createState() =>
      _ExpenseHomeState();
}

class _ExpenseHomeState extends State<ExpenseHome>
    with WidgetsBindingObserver {
  final LocalAuthentication auth =
      LocalAuthentication();

  final SmsQuery smsQuery = SmsQuery();

  List<AccountModel> accounts = [];
  List<TransactionModel> transactions = [];
  List<BudgetModel> budgets = [];
  List<RecurringModel> recurring = [];

  int selectedTab = 0;

  String searchText = '';

  DateTime? filterFrom;
  DateTime? filterTo;

  String? pin;

  bool biometricEnabled = false;

  int autoLockMinutes = 5;

  bool locked = false;

  DateTime? backgroundTime;

  final List<String> categories = [
    'Food',
    'Travel',
    'Bills',
    'Shopping',
    'Medical',
    'Education',
    'Rent',
    'EMI',
    'Insurance',
    'Entertainment',
    'Fuel',
    'Recharge',
    'Subscription',
    'Credit Card Payment',
    'Other',
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state == AppLifecycleState.paused) {
      backgroundTime = DateTime.now();
    }

    if (state == AppLifecycleState.resumed) {
      if (backgroundTime != null &&
          pin != null &&
          DateTime.now()
                  .difference(backgroundTime!)
                  .inMinutes >=
              autoLockMinutes) {
        setState(() {
          locked = true;
        });
      }
    }
  }

  Future<void> loadData() async {
    final prefs =
        await SharedPreferences.getInstance();

    final accountJson =
        prefs.getString('accounts');

    final transactionJson =
        prefs.getString('transactions');

    final budgetJson =
        prefs.getString('budgets');

    final recurringJson =
        prefs.getString('recurring');

    if (accountJson != null) {
      accounts =
          (jsonDecode(accountJson) as List)
              .map(
                (e) => AccountModel.fromJson(e),
              )
              .toList();
    }

    if (transactionJson != null) {
      transactions =
          (jsonDecode(transactionJson) as List)
              .map(
                (e) =>
                    TransactionModel.fromJson(e),
              )
              .toList();
    }

    if (budgetJson != null) {
      budgets =
          (jsonDecode(budgetJson) as List)
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

  Future<void> saveData() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      'accounts',
      jsonEncode(
        accounts.map((e) => e.toJson()).toList(),
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
        budgets.map((e) => e.toJson()).toList(),
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

    if (pin == null) {
      await prefs.remove('pin');
    } else {
      await prefs.setString('pin', pin!);
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
        } else {
          balance -= transaction.amount;
        }
      }
    }

    return balance;
  }

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

  double creditOutstanding(
    AccountModel account,
  ) {
    if (account.type !=
            AccountType.creditCard &&
        account.type != AccountType.loan) {
      return 0;
    }

    return transactions
        .where(
          (t) =>
              t.accountId == account.id &&
              t.type ==
                  TransactionType.expense,
        )
        .fold(
          0,
          (sum, t) => sum + t.amount,
        );
  }

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
              !t.date.isBefore(filterFrom!);

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
        (a, b) => b.date.compareTo(a.date),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return LockScreen(
        biometricEnabled: biometricEnabled,
        onBiometric: unlockBiometric,
        onPin: (enteredPin) {
          if (enteredPin == pin) {
            setState(() {
              locked = false;
            });
          } else {
            ScaffoldMessenger.of(context)
                .showSnackBar(
              const SnackBar(
                content: Text('Wrong PIN'),
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
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: showAddTransaction,
          ),
        ],
      ),
      body: pages[selectedTab],
      bottomNavigationBar:
          NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
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
            icon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

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
              getAccountBalance(account.id),
        );

    return RefreshIndicator(
      onRefresh: () async {
        await processRecurring();
        await saveData();
        setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Current Balance',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    moneyFormat.format(
                      balances,
                    ),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          const Text(
            'Accounts & Balances',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
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

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
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
                        ? 'Outstanding: ${moneyFormat.format(creditOutstanding(account))}'
                        : 'Opening: ${moneyFormat.format(account.openingBalance)}',
                  ),
                  trailing: Text(
                    moneyFormat.format(
                      balance,
                    ),
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      color: balance < 0
                          ? Colors.red
                          : null,
                    ),
                  ),
                  onTap: () =>
                      editAccount(account),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: summaryCard(
                  'Income',
                  totalIncome,
                  Colors.green,
                  Icons.arrow_downward,
                ),
              ),
              const SizedBox(width: 8),
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
          const SizedBox(height: 12),
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
              trailing: const Icon(
                Icons.chevron_right,
              ),
              onTap: scanSms,
            ),
          ),
        ],
      ),
    );
  }

  Widget summaryCard(
    String title,
    double value,
    Color color,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Icon(
              icon,
              color: color,
            ),
            const SizedBox(height: 5),
            Text(title),
            const SizedBox(height: 5),
            Text(
              moneyFormat.format(value),
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

                    return ListTile(
                      leading:
                          CircleAvatar(
                        child: Icon(
                          income
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
                      ),
                      subtitle: Text(
                        '${transaction.category}'
                        '${transaction.subCategory.isEmpty ? '' : ' • ${transaction.subCategory}'}'
                        '\n${dateFormat.format(transaction.date)}',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        '${income ? '+' : '-'}${moneyFormat.format(transaction.amount)}',
                        style: TextStyle(
                          color: income
                              ? Colors.green
                              : Colors.red,
                          fontWeight:
                              FontWeight.bold,
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
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget budgetPage() {
    final now = DateTime.now();

    final current = budgets
        .where(
          (b) =>
              b.month == now.month &&
              b.year == now.year,
        )
        .toList();

    return ListView(
      padding:
          const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading:
                const Icon(Icons.add_chart),
            title: const Text(
              'Add Monthly Budget',
            ),
            subtitle: const Text(
              'Food ₹8,000 • Travel ₹3,000 • Bills ₹5,000',
            ),
            trailing:
                const Icon(Icons.add),
            onTap: addBudget,
          ),
        ),
        const SizedBox(height: 10),
        ...current.map(
          (budget) {
            final actual =
                transactions
                    .where(
                      (t) =>
                          t.type ==
                              TransactionType
                                  .expense &&
                          t.category ==
                              budget.category &&
                          t.date.month ==
                              now.month &&
                          t.date.year ==
                              now.year,
                    )
                    .fold(
                      0.0,
                      (sum, t) =>
                          sum + t.amount,
                    );

            final remaining =
                budget.amount - actual;

            return Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            budget.category,
                            style:
                                const TextStyle(
                              fontSize: 18,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                          ),
                          onPressed: () =>
                              deleteBudget(
                            budget,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Budget: ${moneyFormat.format(budget.amount)}',
                    ),
                    Text(
                      'Actual: ${moneyFormat.format(actual)}',
                    ),
                    Text(
                      remaining >= 0
                          ? 'Remaining: ${moneyFormat.format(remaining)}'
                          : 'Exceeded by ${moneyFormat.format(-remaining)}',
                      style: TextStyle(
                        color: remaining >= 0
                            ? Colors.green
                            : Colors.red,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    LinearProgressIndicator(
                      value:
                          budget.amount <= 0
                              ? 0
                              : (actual /
                                      budget.amount)
                                  .clamp(
                                  0.0,
                                  1.0,
                                ),
                    ),
                    if (remaining < 0)
                      const Padding(
                        padding:
                            EdgeInsets.only(
                          top: 8,
                        ),
                        child: Text(
                          '⚠ Budget exceeded',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget recurringPage() {
    return ListView(
      padding:
          const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading:
                const Icon(Icons.repeat),
            title: const Text(
              'Add Recurring Expense',
            ),
            subtitle: const Text(
              'EMI • Rent • Electricity • School fees • Insurance • Subscription',
            ),
            trailing:
                const Icon(Icons.add),
            onTap: addRecurring,
          ),
        ),
        const SizedBox(height: 10),
        ...recurring.map(
          (item) => Card(
            child: ListTile(
              leading: const Icon(
                Icons.event_repeat,
              ),
              title: Text(item.title),
              subtitle: Text(
                '${item.category} • Day ${item.day}\n${moneyFormat.format(item.amount)}',
              ),
              isThreeLine: true,
              trailing: Switch(
                value: item.active,
                onChanged: (value) async {
                  item.active = value;
                  await saveData();
                  setState(() {});
                },
              ),
              onLongPress: () async {
                recurring.remove(item);
                await saveData();
                setState(() {});
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget reportsPage() {
    final categoryTotals =
        <String, double>{};

    for (final transaction
        in transactions) {
      if (transaction.type ==
          TransactionType.expense) {
        categoryTotals[
                transaction.category] =
            (categoryTotals[
                        transaction.category] ??
                    0) +
                transaction.amount;
      }
    }

    final entries =
        categoryTotals.entries.toList()
          ..sort(
            (a, b) =>
                b.value.compareTo(a.value),
          );

    return ListView(
      padding:
          const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: exportExcel,
                icon: const Icon(
                  Icons.table_chart,
                ),
                label:
                    const Text('Excel'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: exportPdf,
                icon: const Icon(
                  Icons.picture_as_pdf,
                ),
                label: const Text(
                  'PDF',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Card(
          child: Padding(
            padding:
                const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Income vs Expense',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 20,
                ),
                SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      barGroups: [
                        BarChartGroupData(
                          x: 0,
                          barRods: [
                            BarChartRodData(
                              toY:
                                  totalIncome,
                              width: 40,
                            ),
                          ],
                        ),
                        BarChartGroupData(
                          x: 1,
                          barRods: [
                            BarChartRodData(
                              toY:
                                  totalExpense,
                              width: 40,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                Text(
                  'Income: ${moneyFormat.format(totalIncome)}',
                ),
                Text(
                  'Expense: ${moneyFormat.format(totalExpense)}',
                ),
                Text(
                  'Savings: ${moneyFormat.format(savings)}',
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 15),
        Card(
          child: Padding(
            padding:
                const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Category-wise Expense',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                ...entries.map(
                  (entry) => ListTile(
                    title:
                        Text(entry.key),
                    trailing: Text(
                      moneyFormat.format(
                        entry.value,
                      ),
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
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
      padding:
          const EdgeInsets.all(16),
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
              'Transfer between accounts',
            ),
            onTap: transferMoney,
          ),
        ),
        Card(
          child: ListTile(
            leading:
                const Icon(Icons.sms),
            title: const Text(
              'SMS Automation',
            ),
            subtitle: const Text(
              'Read and detect bank transactions',
            ),
            onTap: scanSms,
          ),
        ),
        Card(
          child: ListTile(
            leading:
                const Icon(Icons.lock),
            title: const Text(
              'Security',
            ),
            subtitle: Text(
              pin == null
                  ? 'PIN not configured'
                  : 'PIN enabled • Auto-lock $autoLockMinutes min',
            ),
            onTap: securitySettings,
          ),
        ),
      ],
    );
  }

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
        existing?.type ??
            TransactionType.expense;

    AccountModel account =
        accounts.firstWhere(
      (a) =>
          a.id ==
          (existing?.accountId ??
              accounts.first.id),
      orElse: () => accounts.first,
    );

    String category =
        existing?.category ??
            categories.first;

    final subController =
        TextEditingController(
      text:
          existing?.subCategory ?? '',
    );

    final amountController =
        TextEditingController(
      text: existing == null
          ? ''
          : existing.amount.toString(),
    );

    final merchantController =
        TextEditingController(
      text:
          existing?.merchant ?? '',
    );

    final noteController =
        TextEditingController(
      text: existing?.note ?? '',
    );

    DateTime date =
        existing?.date ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder:
              (context, setDialogState) {
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
                          child:
                              Text('Expense'),
                        ),
                        DropdownMenuItem(
                          value:
                              TransactionType
                                  .income,
                          child:
                              Text('Income'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value !=
                            null) {
                          setDialogState(
                            () => type =
                                value,
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
                              child: Text(
                                a.name,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value !=
                            null) {
                          setDialogState(
                            () => account =
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
                    DropdownButtonFormField<
                        String>(
                      value: category,
                      items: categories
                          .map(
                            (c) =>
                                DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value !=
                            null) {
                          setDialogState(
                            () => category =
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
                        decimal: true,
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
                      subtitle: Text(
                        dateFormat.format(
                          date,
                        ),
                      ),
                      trailing:
                          const Icon(
                        Icons
                            .calendar_today,
                      ),
                      onTap: () async {
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
                            () => date =
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
                      const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final amount =
                        double.tryParse(
                              amountController
                                  .text,
                            ) ??
                            0;

                    if (amount <= 0) {
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
                                  .text,
                          merchant:
                              merchantController
                                  .text,
                          amount: amount,
                          type: type,
                          note:
                              noteController
                                  .text,
                        ),
                      );
                    } else {
                      existing.date = date;
                      existing.accountId =
                          account.id;
                      existing.category =
                          category;
                      existing.subCategory =
                          subController
                              .text;
                      existing.merchant =
                          merchantController
                              .text;
                      existing.amount =
                          amount;
                      existing.type =
                          type;
                      existing.note =
                          noteController
                              .text;
                    }

                    await saveData();

                    if (mounted) {
                      Navigator.pop(
                        dialogContext,
                      );

                      setState(() {});
                    }
                  },
                  child:
                      const Text('Save'),
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
    final result =
        await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'Delete transaction?',
        ),
        content: Text(
          moneyFormat.format(
            transaction.amount,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              context,
              false,
            ),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
              context,
              true,
            ),
            child:
                const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      transactions.removeWhere(
        (t) => t.id == transaction.id,
      );

      await saveData();

      setState(() {});
    }
  }

  Future<void> manageAccounts() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'Accounts',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ...accounts.map(
                (account) => ListTile(
                  leading: Icon(
                    accountIcon(
                      account.type,
                    ),
                  ),
                  title:
                      Text(account.name),
                  subtitle: Text(
                    moneyFormat.format(
                      getAccountBalance(
                        account.id,
                      ),
                    ),
                  ),
                  trailing:
                      const Icon(
                    Icons.edit,
                  ),
                  onTap: () async {
                    Navigator.pop(
                      context,
                    );

                    await editAccount(
                      account,
                    );
                  },
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.add),
                title: const Text(
                  'Add Account',
                ),
                onTap: () async {
                  Navigator.pop(
                    context,
                  );

                  await addAccount();
                },
              ),
            ],
          ),
        ),
      ),
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
      builder: (_) =>
          StatefulBuilder(
        builder:
            (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Add Account',
            ),
            content:
                SingleChildScrollView(
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
                    items: AccountType
                        .values
                        .map(
                          (type) =>
                              DropdownMenuItem(
                            value: type,
                            child: Text(
                              accountTypeName(
                                type,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value !=
                          null) {
                        setDialogState(
                          () => type =
                              value,
                        );
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
                onPressed: () =>
                    Navigator.pop(
                  context,
                ),
                child:
                    const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final balance =
                      double.tryParse(
                            balanceController
                                .text,
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

                  if (mounted) {
                    Navigator.pop(
                      context,
                    );

                    setState(() {});
                  }
                },
                child:
                    const Text('Save'),
              ),
            ],
          );
        },
      ),
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
      builder: (_) => AlertDialog(
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
            onPressed: () =>
                Navigator.pop(
              context,
            ),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              account.name =
                  nameController.text;

              account.openingBalance =
                  double.tryParse(
                        balanceController
                            .text,
                      ) ??
                      0;

              await saveData();

              if (mounted) {
                Navigator.pop(
                  context,
                );

                setState(() {});
              }
            },
            child:
                const Text('Save'),
          ),
        ],
      ),
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

  Future<void> transferMoney() async {
    if (accounts.length < 2) {
      return;
    }

    AccountModel from =
        accounts.first;

    AccountModel to =
        accounts[1];

    final amountController =
        TextEditingController();

    await showDialog(
      context: context,
      builder: (_) =>
          StatefulBuilder(
        builder:
            (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Account Transfer',
            ),
            content: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                DropdownButtonFormField<
                    AccountModel>(
                  value: from,
                  items: accounts
                      .map(
                        (a) =>
                            DropdownMenuItem(
                          value: a,
                          child: Text(
                            a.name,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value !=
                        null) {
                      setDialogState(
                        () => from =
                            value,
                      );
                    }
                  },
                  decoration:
                      const InputDecoration(
                    labelText: 'From',
                  ),
                ),
                DropdownButtonFormField<
                    AccountModel>(
                  value: to,
                  items: accounts
                      .map(
                        (a) =>
                            DropdownMenuItem(
                          value: a,
                          child: Text(
                            a.name,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value !=
                        null) {
                      setDialogState(
                        () => to =
                            value,
                      );
                    }
                  },
                  decoration:
                      const InputDecoration(
                    labelText: 'To',
                  ),
                ),
                TextField(
                  controller:
                      amountController,
                  keyboardType:
                      const TextInputType
                          .numberWithOptions(
                    decimal: true,
                  ),
                  decoration:
                      const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                  context,
                ),
                child:
                    const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final amount =
                      double.tryParse(
                            amountController
                                .text,
                          ) ??
                          0;

                  if (amount <= 0 ||
                      from.id == to.id) {
                    return;
                  }

                  transactions.add(
                    TransactionModel(
                      id: DateTime.now()
                          .microsecondsSinceEpoch
                          .toString(),
                      date:
                          DateTime.now(),
                      accountId:
                          from.id,
                      category:
                          'Transfer',
                      subCategory: '',
                      merchant:
                          'Account Transfer',
                      amount: amount,
                      type: TransactionType
                          .transfer,
                      note:
                          'Transfer to ${to.name}',
                      transferToAccountId:
                          to.id,
                    ),
                  );

                  await saveData();

                  if (mounted) {
                    Navigator.pop(
                      context,
                    );

                    setState(() {});
                  }
                },
                child:
                    const Text('Transfer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> addBudget() async {
    final amountController =
        TextEditingController();

    String category =
        categories.first;

    await showDialog(
      context: context,
      builder: (_) =>
          StatefulBuilder(
        builder:
            (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Monthly Budget',
            ),
            content: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                DropdownButtonFormField<
                    String>(
                  value: category,
                  items: categories
                      .map(
                        (c) =>
                            DropdownMenuItem(
                          value: c,
                          child: Text(
                            c,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value !=
                        null) {
                      setDialogState(
                        () => category =
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
                TextField(
                  controller:
                      amountController,
                  keyboardType:
                      const TextInputType
                          .numberWithOptions(
                    decimal: true,
                  ),
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Monthly budget',
                    prefixText: '₹ ',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                  context,
                ),
                child:
                    const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final amount =
                      double.tryParse(
                            amountController
                                .text,
                          ) ??
                          0;

                  if (amount <= 0) {
                    return;
                  }

                  final now =
                      DateTime.now();

                  budgets.removeWhere(
                    (b) =>
                        b.category ==
                            category &&
                        b.month ==
                            now.month &&
                        b.year ==
                            now.year,
                  );

                  budgets.add(
                    BudgetModel(
                      category:
                          category,
                      amount: amount,
                      month:
                          now.month,
                      year:
                          now.year,
                    ),
                  );

                  await saveData();

                  if (mounted) {
                    Navigator.pop(
                      context,
                    );

                    setState(() {});
                  }
                },
                child:
                    const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> deleteBudget(
    BudgetModel budget,
  ) async {
    budgets.remove(budget);

    await saveData();

    setState(() {});
  }

  Future<void> addRecurring() async {
    final titleController =
        TextEditingController();

    final amountController =
        TextEditingController();

    String category = 'EMI';

    AccountModel account =
        accounts.first;

    int day = 1;

    await showDialog(
      context: context,
      builder: (_) =>
          StatefulBuilder(
        builder:
            (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Recurring Expense',
            ),
            content:
                SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller:
                        titleController,
                    decoration:
                        const InputDecoration(
                      labelText: 'Title',
                    ),
                  ),
                  DropdownButtonFormField<
                      String>(
                    value: category,
                    items: [
                      'EMI',
                      'Rent',
                      'Electricity',
                      'School fees',
                      'Insurance',
                      'Subscription',
                      'Other',
                    ]
                        .map(
                          (c) =>
                              DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value !=
                          null) {
                        setDialogState(
                          () => category =
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
                  DropdownButtonFormField<
                      AccountModel>(
                    value: account,
                    items: accounts
                        .map(
                          (a) =>
                              DropdownMenuItem(
                            value: a,
                            child: Text(
                              a.name,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value !=
                          null) {
                        setDialogState(
                          () => account =
                              value,
                        );
                      }
                    },
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Payment account',
                    ),
                  ),
                  TextField(
                    controller:
                        amountController,
                    keyboardType:
                        const TextInputType
                            .numberWithOptions(
                      decimal: true,
                    ),
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Amount',
                      prefixText: '₹ ',
                    ),
                  ),
                  DropdownButtonFormField<
                      int>(
                    value: day,
                    items: List.generate(
                      28,
                      (i) =>
                          DropdownMenuItem(
                        value: i + 1,
                        child: Text(
                          'Day ${i + 1}',
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      if (value !=
                          null) {
                        setDialogState(
                          () => day =
                              value,
                        );
                      }
                    },
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Due day',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                  context,
                ),
                child:
                    const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final amount =
                      double.tryParse(
                            amountController
                                .text,
                          ) ??
                          0;

                  if (amount <= 0) {
                    return;
                  }

                  recurring.add(
                    RecurringModel(
                      id: DateTime.now()
                          .microsecondsSinceEpoch
                          .toString(),
                      title: titleController
                              .text
                              .trim()
                              .isEmpty
                          ? category
                          : titleController
                              .text
                              .trim(),
                      category:
                          category,
                      amount: amount,
                      accountId:
                          account.id,
                      day: day,
                      active: true,
                    ),
                  );

                  await saveData();

                  if (mounted) {
                    Navigator.pop(
                      context,
                    );

                    setState(() {});
                  }
                },
                child:
                    const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> selectDateRange() async {
    final range =
        await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (range != null) {
      setState(() {
        filterFrom = range.start;
        filterTo = range.end;
      });
    }
  }

  // ============================================================
  // SECURITY
  // ============================================================

  Future<void> securitySettings() async {
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder:
            (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Security',
            ),
            content:
                SingleChildScrollView(
              child: Column(
                children: [
                  ListTile(
                    leading:
                        const Icon(Icons.pin),
                    title: Text(
                      pin == null
                          ? 'Set PIN'
                          : 'Change PIN',
                    ),
                    onTap: () async {
                      Navigator.pop(
                        context,
                      );

                      await setPin();
                    },
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Fingerprint / Biometrics',
                    ),
                    value:
                        biometricEnabled,
                    onChanged:
                        pin == null
                            ? null
                            : (value) async {
                                if (value) {
                                  final supported =
                                      await checkBiometric();

                                  if (!supported) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text(
                                            'Biometric authentication is not available.',
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                }

                                biometricEnabled =
                                    value;

                                await saveData();

                                setDialogState(
                                  () {},
                                );

                                setState(
                                  () {},
                                );
                              },
                  ),
                  DropdownButtonFormField<
                      int>(
                    value:
                        autoLockMinutes,
                    items: const [
                      DropdownMenuItem(
                        value: 1,
                        child:
                            Text(
                          '1 minute',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 5,
                        child:
                            Text(
                          '5 minutes',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 10,
                        child:
                            Text(
                          '10 minutes',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 30,
                        child:
                            Text(
                          '30 minutes',
                        ),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value !=
                          null) {
                        autoLockMinutes =
                            value;

                        await saveData();

                        setDialogState(
                          () {},
                        );

                        setState(
                          () {},
                        );
                      }
                    },
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Auto-lock',
                    ),
                  ),
                  if (pin != null)
                    ListTile(
                      leading:
                          const Icon(
                        Icons.lock_open,
                      ),
                      title:
                          const Text(
                        'Lock Now',
                      ),
                      onTap: () {
                        Navigator.pop(
                          context,
                        );

                        setState(() {
                          locked =
                              true;
                        });
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                  context,
                ),
                child:
                    const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> checkBiometric() async {
    try {
      final canCheck =
          await auth.canCheckBiometrics;

      final supported =
          await auth.isDeviceSupported();

      return canCheck && supported;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin() async {
    final firstController =
        TextEditingController();

    final secondController =
        TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'Set 4-digit PIN',
        ),
        content: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            TextField(
              controller:
                  firstController,
              keyboardType:
                  TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter
                    .digitsOnly,
              ],
              decoration:
                  const InputDecoration(
                labelText:
                    'Enter PIN',
              ),
            ),
            TextField(
              controller:
                  secondController,
              keyboardType:
                  TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter
                    .digitsOnly,
              ],
              decoration:
                  const InputDecoration(
                labelText:
                    'Confirm PIN',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(
              context,
            ),
            child:
                const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (firstController
                          .text
                          .length !=
                      4 ||
                  secondController
                          .text
                          .length !=
                      4) {
                return;
              }

              if (firstController.text !=
                  secondController.text) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'PIN does not match.',
                    ),
                  ),
                );

                return;
              }

              pin =
                  firstController.text;

              await saveData();

              if (mounted) {
                Navigator.pop(
                  context,
                );

                setState(() {});
              }
            },
            child:
                const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> unlockBiometric() async {
    try {
      final authenticated =
          await auth.authenticate(
        localizedReason:
            'Unlock Expense Tracker',
        options:
            const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated &&
          mounted) {
        setState(() {
          locked = false;
        });
      }
    } catch (_) {}
  }

  // ============================================================
  // SMS
  // ============================================================

  Future<bool> requestSmsPermission() async {
    if (!Platform.isAndroid) {
      return false;
    }

    final status =
        await Permission.sms.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      if (!mounted) {
        return false;
      }

      final open =
          await showDialog<bool>(
        context: context,
        builder: (_) =>
            AlertDialog(
          title: const Text(
            'SMS Permission Required',
          ),
          content: const Text(
            'Expense Tracker needs SMS permission to detect bank transactions. Please enable SMS permission in Android Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),
              child: const Text(
                'Open Settings',
              ),
            ),
          ],
        ),
      );

      if (open == true) {
        await openAppSettings();
      }

      return false;
    }

    final result =
        await Permission.sms.request();

    return result.isGranted;
  }

  Future<void> scanSms() async {
    final permission =
        await requestSmsPermission();

    if (!permission) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'SMS permission was not granted.',
            ),
          ),
        );
      }

      return;
    }

    try {
      final messages =
          await smsQuery.querySms(
        kinds: [
          SmsQueryKind.inbox,
        ],
      );

      final candidates =
          <TransactionModel>[];

      for (final sms in messages) {
        final body =
            sms.body ?? '';

        if (body.trim().isEmpty) {
          continue;
        }

        final lower =
            body.toLowerCase();

        final financial =
            lower.contains(
                  'debited',
                ) ||
                lower.contains(
                  'credited',
                ) ||
                lower.contains(
                  'debit',
                ) ||
                lower.contains(
                  'credit',
                ) ||
                lower.contains(
                  'upi',
                ) ||
                lower.contains(
                  'transaction',
                ) ||
                lower.contains(
                  'spent',
                ) ||
                lower.contains(
                  'paid',
                );

        if (!financial) {
          continue;
        }

        final amount =
            extractAmount(body);

        if (amount == null ||
            amount <= 0) {
          continue;
        }

        final credit =
            lower.contains(
                  'credited',
                ) ||
                lower.contains(
                  'credit',
                ) ||
                lower.contains(
                  'received',
                ) ||
                lower.contains(
                  'deposit',
                );

        final debit =
            lower.contains(
                  'debited',
                ) ||
                lower.contains(
                  'debit',
                ) ||
                lower.contains(
                  'spent',
                ) ||
                lower.contains(
                  'paid',
                );

        if (!credit && !debit) {
          continue;
        }

        final smsId =
            sms.id?.toString();

        if (smsId != null &&
            transactions.any(
              (t) =>
                  t.smsId == smsId,
            )) {
          continue;
        }

        final transaction =
            TransactionModel(
          id: DateTime.now()
              .microsecondsSinceEpoch
              .toString(),
          date:
              extractSmsDate(body) ??
                  DateTime.now(),
          accountId:
              detectAccount(body),
          category:
              detectCategory(body),
          subCategory: 'SMS',
          merchant:
              detectMerchant(body),
          amount: amount,
          type: credit
              ? TransactionType
                  .income
              : TransactionType
                  .expense,
          note: body,
          smsId: smsId,
        );

        candidates.add(
          transaction,
        );
      }

      if (!mounted) {
        return;
      }

      if (candidates.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'No new bank transactions found.',
            ),
          ),
        );

        return;
      }

      await showSmsReview(
        candidates,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            'Could not read SMS: $error',
          ),
        ),
      );
    }
  }

  double? extractAmount(
    String text,
  ) {
    final patterns = [
      RegExp(
        r'(?:INR|Rs\.?|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
        caseSensitive: false,
      ),
      RegExp(
        r'([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:INR|Rs\.?|₹)',
        caseSensitive: false,
      ),
    ];

    for (final pattern
        in patterns) {
      final match =
          pattern.firstMatch(text);

      if (match != null) {
        return double.tryParse(
          match
              .group(1)!
              .replaceAll(',', ''),
        );
      }
    }

    return null;
  }

  DateTime? extractSmsDate(
    String text,
  ) {
    final match =
        RegExp(
      r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})',
    ).firstMatch(text);

    if (match == null) {
      return null;
    }

    final day =
        int.tryParse(match.group(1)!);

    final month =
        int.tryParse(match.group(2)!);

    var year =
        int.tryParse(match.group(3)!);

    if (day == null ||
        month == null ||
        year == null) {
      return null;
    }

    if (year < 100) {
      year += 2000;
    }

    return DateTime(
      year,
      month,
      day,
    );
  }

  String detectMerchant(
    String text,
  ) {
    final patterns = [
      RegExp(
        r'(?:at|to|merchant|vpa)\s+([A-Za-z0-9 ._@&-]{2,50})',
        caseSensitive: false,
      ),
      RegExp(
        r'UPI.*?to\s+([A-Za-z0-9 ._@&-]{2,50})',
        caseSensitive: false,
      ),
    ];

    for (final pattern
        in patterns) {
      final match =
          pattern.firstMatch(text);

      if (match != null) {
        return match
            .group(1)!
            .trim()
            .replaceAll(
              RegExp(r'\s+'),
              ' ',
            );
      }
    }

    return 'Bank Transaction';
  }

  String detectCategory(
    String text,
  ) {
    final lower =
        text.toLowerCase();

    if (lower.contains(
          'swiggy',
        ) ||
        lower.contains(
          'zomato',
        ) ||
        lower.contains(
          'restaurant',
        ) ||
        lower.contains(
          'food',
        )) {
      return 'Food';
    }

    if (lower.contains(
          'uber',
        ) ||
        lower.contains(
          'ola',
        ) ||
        lower.contains(
          'petrol',
        ) ||
        lower.contains(
          'fuel',
        )) {
      return 'Travel';
    }

    if (lower.contains(
          'electricity',
        ) ||
        lower.contains(
          'kseb',
        ) ||
        lower.contains(
          'bill',
        )) {
      return 'Bills';
    }

    if (lower.contains(
          'school',
        ) ||
        lower.contains(
          'education',
        )) {
      return 'Education';
    }

    if (lower.contains(
      'insurance',
    )) {
      return 'Insurance';
    }

    if (lower.contains(
          'emi',
        ) ||
        lower.contains(
          'loan',
        )) {
      return 'EMI';
    }

    if (lower.contains(
      'subscription',
    )) {
      return 'Subscription';
    }

    return 'Other';
  }

  String detectAccount(
    String text,
  ) {
    final lower =
        text.toLowerCase();

    final creditCards =
        accounts.where(
      (a) =>
          a.type ==
          AccountType.creditCard,
    );

    if (lower.contains(
          'credit card',
        ) ||
        lower.contains(
          'card',
        )) {
      if (creditCards.isNotEmpty) {
        return creditCards.first.id;
      }
    }

    final banks =
        accounts.where(
      (a) =>
          a.type ==
          AccountType.bank,
    );

    if (banks.isNotEmpty) {
      return banks.first.id;
    }

    return accounts.first.id;
  }

  Future<void> showSmsReview(
    List<TransactionModel>
        candidates,
  ) async {
    final selected =
        <String, bool>{
      for (final transaction
          in candidates)
        transaction.id: true,
    };

    await showDialog(
      context: context,
      builder: (_) =>
          StatefulBuilder(
        builder:
            (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Review SMS Transactions',
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 450,
              child: ListView(
                children: candidates
                    .map(
                      (transaction) =>
                          CheckboxListTile(
                        value: selected[
                            transaction.id],
                        onChanged:
                            (value) {
                          setDialogState(
                            () {
                              selected[
                                      transaction
                                          .id] =
                                  value ??
                                      false;
                            },
                          );
                        },
                        title: Text(
                          '${transaction.merchant} • ${moneyFormat.format(transaction.amount)}',
                        ),
                        subtitle:
                            Text(
                          '${transaction.type == TransactionType.income ? 'CREDIT' : 'DEBIT'}\n${transaction.category} • ${dateFormat.format(transaction.date)}',
                        ),
                        isThreeLine:
                            true,
                      ),
                    )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                  context,
                ),
                child:
                    const Text('Skip'),
              ),
              FilledButton(
                onPressed: () async {
                  for (final transaction
                      in candidates) {
                    if (selected[
                            transaction
                                .id] ==
                        true) {
                      transactions.add(
                        transaction,
                      );
                    }
                  }

                  await saveData();

                  if (mounted) {
                    Navigator.pop(
                      context,
                    );

                    setState(() {});
                  }
                },
                child: const Text(
                  'Save Selected',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // EXPORT
  // ============================================================

  Future<void> exportExcel() async {
    final workbook =
        ex.Excel.createExcel();

    final sheet =
        workbook['Transactions'];

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

    for (final transaction
        in transactions) {
      final account =
          accounts.firstWhere(
        (a) =>
            a.id ==
            transaction.accountId,
        orElse: () =>
            accounts.first,
      );

      sheet.appendRow([
        ex.TextCellValue(
          dateFormat.format(
            transaction.date,
          ),
        ),
        ex.TextCellValue(
          account.name,
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

    final bytes =
        workbook.encode();

    if (bytes == null) {
      return;
    }

    final directory =
        await getApplicationDocumentsDirectory();

    final file = File(
      '${directory.path}/Expense_Tracker.xlsx',
    );

    await file.writeAsBytes(
      bytes,
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      const SnackBar(
        content: Text(
          'Excel file created.',
        ),
      ),
    );
  }

  Future<void> exportPdf() async {
    final pdf =
        pw.Document();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text(
            'Expense Tracker',
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight:
                  pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(
            height: 12,
          ),
          pw.Text(
            'Financial Summary',
          ),
          pw.Text(
            'Income: ${moneyFormat.format(totalIncome)}',
          ),
          pw.Text(
            'Expense: ${moneyFormat.format(totalExpense)}',
          ),
          pw.Text(
            'Savings: ${moneyFormat.format(savings)}',
          ),
          pw.SizedBox(
            height: 20,
          ),
          pw.TableHelper.fromTextArray(
            headers: [
              'Date',
              'Category',
              'Merchant',
              'Type',
              'Amount',
            ],
            data: transactions
                .map(
                  (transaction) => [
                    dateFormat.format(
                      transaction.date,
                    ),
                    transaction
                        .category,
                    transaction
                        .merchant,
                    transaction.type
                        .name,
                    moneyFormat.format(
                      transaction.amount,
                    ),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) =>
          pdf.save(),
    );
  }
}

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
  final controller =
      TextEditingController();

  @override
  void initState() {
    super.initState();

    if (widget.biometricEnabled) {
      WidgetsBinding.instance
          .addPostFrameCallback(
        (_) {
          widget.onBiometric();
        },
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock,
                size: 70,
              ),
              const SizedBox(
                height: 20,
              ),
              const Text(
                'Expense Tracker',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 30,
              ),
              TextField(
                controller:
                    controller,
                keyboardType:
                    TextInputType.number,
                maxLength: 4,
                obscureText: true,
                textAlign:
                    TextAlign.center,
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
                onSubmitted:
                    widget.onPin,
              ),
              const SizedBox(
                height: 10,
              ),
              FilledButton(
                onPressed: () {
                  widget.onPin(
                    controller.text,
                  );
                },
                child:
                    const Text('Unlock'),
              ),
              if (widget
                  .biometricEnabled)
                TextButton.icon(
                  onPressed:
                      widget.onBiometric,
                  icon: const Icon(
                    Icons.fingerprint,
                  ),
                  label: const Text(
                    'Use fingerprint',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
