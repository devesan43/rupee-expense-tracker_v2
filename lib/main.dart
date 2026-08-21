import 'dart:io';

import 'package:excel/excel.dart' as ex;
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rupee Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1b5e20),
        ),
      ),
      home: const LockGate(),
    );
  }
}

// -----------------------------------------------------------------------------
// TRANSACTION MODEL
// -----------------------------------------------------------------------------

class T {
  int? id;
  double amount;
  String type;
  String account;
  String category;
  String sub;
  String date;
  String desc;
  String? to;

  T({
    this.id,
    required this.amount,
    required this.type,
    required this.account,
    required this.category,
    required this.sub,
    required this.date,
    required this.desc,
    this.to,
  });

  Map<String, dynamic> map() {
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'account': account,
      'toAccount': to,
      'category': category,
      'subCategory': sub,
      'date': date,
      'description': desc,
    };
  }

  factory T.from(Map<String, dynamic> m) {
    return T(
      id: m['id'],
      amount: (m['amount'] as num).toDouble(),
      type: m['type'] as String,
      account: m['account'] as String,
      category: m['category'] ?? 'Other',
      sub: m['subCategory'] ?? '',
      date: m['date'] as String,
      desc: m['description'] ?? '',
      to: m['toAccount'],
    );
  }
}

// -----------------------------------------------------------------------------
// RECURRING MODEL
// -----------------------------------------------------------------------------

class R {
  int? id;
  String name;
  String account;
  String category;
  double amount;
  int day;

  R({
    this.id,
    required this.name,
    required this.account,
    required this.category,
    required this.amount,
    required this.day,
  });

  Map<String, dynamic> map() {
    return {
      'id': id,
      'name': name,
      'account': account,
      'category': category,
      'amount': amount,
      'day': day,
    };
  }

  factory R.from(Map<String, dynamic> m) {
    return R(
      id: m['id'],
      name: m['name'] as String,
      account: m['account'] as String,
      category: m['category'] as String,
      amount: (m['amount'] as num).toDouble(),
      day: m['day'] as int,
    );
  }
}

// -----------------------------------------------------------------------------
// DATABASE
// -----------------------------------------------------------------------------

class DB {
  static Database? d;

  static Future<Database> get db async {
    if (d != null) {
      return d!;
    }

    d = await openDatabase(
      p.join(
        await getDatabasesPath(),
        'expense_v2.db',
      ),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tx(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount REAL,
            type TEXT,
            account TEXT,
            toAccount TEXT,
            category TEXT,
            subCategory TEXT,
            date TEXT,
            description TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE cat(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            type TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE bal(
            account TEXT PRIMARY KEY,
            opening REAL
          )
        ''');

        await db.execute('''
          CREATE TABLE budget(
            month TEXT,
            category TEXT,
            amount REAL,
            PRIMARY KEY(month, category)
          )
        ''');

        await db.execute('''
          CREATE TABLE recurring(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            account TEXT,
            category TEXT,
            amount REAL,
            day INTEGER
          )
        ''');

        for (final account in [
          'Cash',
          'Bank Account',
          'Credit Card',
        ]) {
          await db.insert(
            'bal',
            {
              'account': account,
              'opening': 0,
            },
          );
        }
      },
    );

    return d!;
  }

  static Future<List<T>> all() async {
    final database = await db;

    final result = await database.query(
      'tx',
      orderBy: 'date DESC, id DESC',
    );

    return result.map(T.from).toList();
  }

  static Future<void> save(T transaction) async {
    final database = await db;

    if (transaction.id == null) {
      await database.insert(
        'tx',
        transaction.map(),
      );
    } else {
      await database.update(
        'tx',
        transaction.map(),
        where: 'id=?',
        whereArgs: [transaction.id],
      );
    }
  }

  static Future<void> del(int id) async {
    final database = await db;

    await database.delete(
      'tx',
      where: 'id=?',
      whereArgs: [id],
    );
  }

  static Future<List<String>> cats(String type) async {
    final Map<String, List<String>> defaults = {
      'Expense': [
        'Food',
        'Bills',
        'Travel',
        'Shopping',
        'Health',
        'Education',
        'Utilities',
        'Other',
      ],
      'Income': [
        'Salary',
        'Business',
        'Investment',
        'Gift',
        'Other',
      ],
      'Savings': [
        'Emergency Fund',
        'FD',
        'Mutual Funds',
        'Gold',
      ],
      'Credit': [
        'Personal Loan',
        'Borrowed',
        'Lent',
        'Credit Card Debt',
      ],
      'Transfer': [
        'Account Transfer',
      ],
    };

    final base = defaults[type] ?? ['Other'];

    final database = await db;

    final result = await database.query(
      'cat',
      where: 'type=?',
      whereArgs: [type],
    );

    final custom = result.map(
      (e) => e['name'] as String,
    );

    return {
      ...base,
      ...custom,
    }.toList();
  }

  static Future<void> addCat(
    String name,
    String type,
  ) async {
    final database = await db;

    await database.insert(
      'cat',
      {
        'name': name,
        'type': type,
      },
    );
  }

  static Future<double> opening(String account) async {
    final database = await db;

    final result = await database.query(
      'bal',
      where: 'account=?',
      whereArgs: [account],
    );

    if (result.isEmpty) {
      return 0;
    }

    return (result.first['opening'] as num).toDouble();
  }

  static Future<void> setOpening(
    String account,
    double value,
  ) async {
    final database = await db;

    await database.update(
      'bal',
      {
        'opening': value,
      },
      where: 'account=?',
      whereArgs: [account],
    );
  }

  static Future<void> setBudget(
    String month,
    String category,
    double amount,
  ) async {
    final database = await db;

    await database.insert(
      'budget',
      {
        'month': month,
        'category': category,
        'amount': amount,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, double>> budgets(
    String month,
  ) async {
    final database = await db;

    final result = await database.query(
      'budget',
      where: 'month=?',
      whereArgs: [month],
    );

    return {
      for (final e in result)
        e['category'] as String:
            (e['amount'] as num).toDouble(),
    };
  }

  static Future<List<R>> recurring() async {
    final database = await db;

    final result = await database.query(
      'recurring',
      orderBy: 'day',
    );

    return result.map(R.from).toList();
  }

  static Future<void> addR(R recurring) async {
    final database = await db;

    await database.insert(
      'recurring',
      recurring.map(),
    );
  }
}

// -----------------------------------------------------------------------------
// LOCK GATE
// -----------------------------------------------------------------------------

class LockGate extends StatefulWidget {
  const LockGate({super.key});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  bool busy = true;
  bool locked = false;

  final pin = TextEditingController();
  final auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    final preferences = await SharedPreferences.getInstance();

    final savedPin = preferences.getString('pin');

    if (savedPin != null) {
      locked = true;

      try {
        if (preferences.getBool('bio') == true &&
            await auth.isDeviceSupported()) {
          locked = !(await auth.authenticate(
            localizedReason: 'Unlock Expense Tracker',
          ));
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!locked) {
      return const Home();
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock,
                size: 60,
              ),
              const SizedBox(height: 15),
              const Text(
                'Expense Tracker Locked',
                style: TextStyle(
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIN',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: () async {
                  final preferences =
                      await SharedPreferences.getInstance();

                  if (pin.text == preferences.getString('pin')) {
                    setState(() {
                      locked = false;
                    });
                  }
                },
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HOME
// -----------------------------------------------------------------------------

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final accounts = [
    'Cash',
    'Bank Account',
    'Credit Card',
  ];

  final types = [
    'Expense',
    'Income',
    'Savings',
    'Credit',
    'Transfer',
  ];

  List<T> data = [];
  List<T> shown = [];

  Map<String, double> bal = {};
  Map<String, double> bud = {};

  List<R> rec = [];

  String period = 'Monthly';
  String acct = 'All';
  String query = '';

  DateTimeRange? dates;

  @override
  void initState() {
    super.initState();
    load();
  }

  // ---------------------------------------------------------------------------
  // LOAD DATA
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    data = await DB.all();

    rec = await DB.recurring();

    bud = await DB.budgets(
      DateFormat('yyyy-MM').format(
        DateTime.now(),
      ),
    );

    bal = {};

    for (final account in accounts) {
      bal[account] = await DB.opening(account);
    }

    for (final transaction in data) {
      if (transaction.type == 'Income') {
        bal[transaction.account] =
            (bal[transaction.account] ?? 0) +
                transaction.amount;
      }

      if (transaction.type == 'Expense' ||
          transaction.type == 'Credit') {
        bal[transaction.account] =
            (bal[transaction.account] ?? 0) -
                transaction.amount;
      }

      if (transaction.type == 'Transfer') {
        bal[transaction.account] =
            (bal[transaction.account] ?? 0) -
                transaction.amount;

        if (transaction.to != null) {
          bal[transaction.to!] =
              (bal[transaction.to!] ?? 0) +
                  transaction.amount;
        }
      }
    }

    filter();

    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // FILTER
  // ---------------------------------------------------------------------------

  void filter() {
    final now = DateTime.now();

    shown = data.where((transaction) {
      final date =
          DateTime.tryParse(transaction.date) ?? now;

      if (acct != 'All' &&
          transaction.account != acct) {
        return false;
      }

      if (dates != null) {
        final start = DateTime(
          dates!.start.year,
          dates!.start.month,
          dates!.start.day,
        );

        final end = DateTime(
          dates!.end.year,
          dates!.end.month,
          dates!.end.day,
          23,
          59,
          59,
        );

        if (date.isBefore(start) || date.isAfter(end)) {
          return false;
        }
      }

      if (dates == null) {
        if (period == 'Daily' &&
            !transaction.date.startsWith(
              DateFormat('yyyy-MM-dd').format(now),
            )) {
          return false;
        }

        if (period == 'Monthly' &&
            !transaction.date.startsWith(
              DateFormat('yyyy-MM').format(now),
            )) {
          return false;
        }

        if (period == 'Yearly' &&
            !transaction.date.startsWith(
              DateFormat('yyyy').format(now),
            )) {
          return false;
        }
      }

      if (query.isNotEmpty) {
        final text =
            '${transaction.category} '
            '${transaction.sub} '
            '${transaction.desc} '
            '${transaction.account}';

        if (!text.toLowerCase().contains(
              query.toLowerCase(),
            )) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  double total(String type) {
    return shown
        .where((transaction) => transaction.type == type)
        .fold(
          0.0,
          (sum, transaction) =>
              sum + transaction.amount,
        );
  }

  // ---------------------------------------------------------------------------
  // ADD / EDIT TRANSACTION
  // ---------------------------------------------------------------------------

  Future<void> edit([T? old]) async {
    final amountController = TextEditingController(
      text: old?.amount.toString() ?? '',
    );

    final descriptionController = TextEditingController(
      text: old?.desc ?? '',
    );

    final subController = TextEditingController(
      text: old?.sub ?? '',
    );

    String selectedType =
        old?.type ?? 'Expense';

    String selectedAccount =
        old?.account ?? 'Cash';

    String selectedTo =
        old?.to ?? 'Bank Account';

    String selectedCategory =
        old?.category ?? 'Other';

    List<String> categoryList =
        await DB.cats(selectedType);

    if (!categoryList.contains(selectedCategory)) {
      selectedCategory = categoryList.first;
    }

    if (!mounted) {
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      old == null
                          ? 'New Entry'
                          : 'Edit Entry',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: types.map(
                        (type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          );
                        },
                      ).toList(),
                      onChanged: (value) async {
                        if (value == null) return;

                        selectedType = value;

                        categoryList =
                            await DB.cats(selectedType);

                        selectedCategory =
                            categoryList.first;

                        setModalState(() {});
                      },
                    ),

                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: selectedAccount,
                      decoration: const InputDecoration(
                        labelText: 'Account',
                        border: OutlineInputBorder(),
                      ),
                      items: accounts.map(
                        (account) {
                          return DropdownMenuItem<String>(
                            value: account,
                            child: Text(account),
                          );
                        },
                      ).toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        setModalState(() {
                          selectedAccount = value;

                          if (selectedTo ==
                              selectedAccount) {
                            selectedTo =
                                accounts.firstWhere(
                              (account) =>
                                  account !=
                                  selectedAccount,
                            );
                          }
                        });
                      },
                    ),

                    const SizedBox(height: 12),

                    if (selectedType == 'Transfer')
                      DropdownButtonFormField<String>(
                        value: selectedTo,
                        decoration:
                            const InputDecoration(
                          labelText: 'Transfer To',
                          border: OutlineInputBorder(),
                        ),
                        items: accounts
                            .where(
                              (account) =>
                                  account !=
                                  selectedAccount,
                            )
                            .map(
                              (account) {
                                return DropdownMenuItem<
                                    String>(
                                  value: account,
                                  child: Text(account),
                                );
                              },
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;

                          setModalState(() {
                            selectedTo = value;
                          });
                        },
                      ),

                    if (selectedType == 'Transfer')
                      const SizedBox(height: 12),

                    if (selectedType != 'Transfer')
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration:
                            const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: categoryList.map(
                          (category) {
                            return DropdownMenuItem<
                                String>(
                              value: category,
                              child: Text(category),
                            );
                          },
                        ).toList(),
                        onChanged: (value) {
                          if (value == null) return;

                          setModalState(() {
                            selectedCategory =
                                value;
                          });
                        },
                      ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: subController,
                      decoration:
                          const InputDecoration(
                        labelText: 'Sub-category',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText: 'Amount ₹',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: descriptionController,
                      decoration:
                          const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    ElevatedButton(
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
                                'Enter a valid amount',
                              ),
                            ),
                          );

                          return;
                        }

                        final transaction = T(
                          id: old?.id,
                          amount: amount,
                          type: selectedType,
                          account: selectedAccount,
                          to: selectedType ==
                                  'Transfer'
                              ? selectedTo
                              : null,
                          category:
                              selectedType ==
                                      'Transfer'
                                  ? 'Transfer'
                                  : selectedCategory,
                          sub: subController.text.trim(),
                          date: old?.date ??
                              DateFormat(
                                'yyyy-MM-dd HH:mm',
                              ).format(
                                DateTime.now(),
                              ),
                          desc:
                              descriptionController.text
                                  .trim(),
                        );

                        await DB.save(transaction);

                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      child: Text(
                        old == null
                            ? 'Save'
                            : 'Update',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    amountController.dispose();
    descriptionController.dispose();
    subController.dispose();

    await load();
  }

  // ---------------------------------------------------------------------------
  // MANUAL CATEGORY
  // ---------------------------------------------------------------------------

  Future<void> category() async {
    final controller = TextEditingController();

    String type = 'Expense';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Manual Category',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    items: types
                        .where(
                          (x) => x != 'Transfer',
                        )
                        .map(
                          (e) =>
                              DropdownMenuItem<String>(
                            value: e,
                            child: Text(e),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;

                      setDialogState(() {
                        type = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration:
                        const InputDecoration(
                      labelText: 'Category',
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    if (controller.text.trim().isNotEmpty) {
                      await DB.addCat(
                        controller.text.trim(),
                        type,
                      );
                    }

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    await load();
  }

  // ---------------------------------------------------------------------------
  // OPENING BALANCES
  // ---------------------------------------------------------------------------

  Future<void> openings() async {
    for (final account in accounts) {
      final controller = TextEditingController(
        text: '${await DB.opening(account)}',
      );

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              '$account Opening Balance',
            ),
            content: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration:
                  const InputDecoration(
                labelText: 'Opening Balance ₹',
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  await DB.setOpening(
                    account,
                    double.tryParse(
                          controller.text,
                        ) ??
                        0,
                  );

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      controller.dispose();
    }

    await load();
  }

  // ---------------------------------------------------------------------------
  // BUDGET
  // ---------------------------------------------------------------------------

  Future<void> budget() async {
    final categories =
        await DB.cats('Expense');

    if (categories.isEmpty) {
      return;
    }

    String selectedCategory =
        categories.first;

    final controller = TextEditingController(
      text:
          '${bud[selectedCategory] ?? 0}',
    );

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Budget vs Actual',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    items: categories.map(
                      (category) {
                        return DropdownMenuItem<
                            String>(
                          value: category,
                          child: Text(category),
                        );
                      },
                    ).toList(),
                    onChanged: (value) {
                      if (value == null) return;

                      setDialogState(() {
                        selectedCategory =
                            value;

                        controller.text =
                            '${bud[selectedCategory] ?? 0}';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Monthly budget ₹',
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    await DB.setBudget(
                      DateFormat('yyyy-MM').format(
                        DateTime.now(),
                      ),
                      selectedCategory,
                      double.tryParse(
                            controller.text,
                          ) ??
                          0,
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    await load();
  }

  // ---------------------------------------------------------------------------
  // RECURRING EXPENSE
  // ---------------------------------------------------------------------------

  Future<void> recurringDialog() async {
    final nameController =
        TextEditingController();

    final amountController =
        TextEditingController();

    final dayController =
        TextEditingController(text: '1');

    final categoryController =
        TextEditingController(text: 'Bills');

    String account = 'Bank Account';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Recurring Expense',
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(
                    labelText: 'Name',
                  ),
                ),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration:
                      const InputDecoration(
                    labelText: 'Amount ₹',
                  ),
                ),
                TextField(
                  controller: dayController,
                  keyboardType:
                      TextInputType.number,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Day of month',
                  ),
                ),
                StatefulBuilder(
                  builder:
                      (context, setDialogState) {
                    return DropdownButtonFormField<
                        String>(
                      value: account,
                      items: accounts.map(
                        (e) {
                          return DropdownMenuItem<
                              String>(
                            value: e,
                            child: Text(e),
                          );
                        },
                      ).toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        setDialogState(() {
                          account = value;
                        });
                      },
                    );
                  },
                ),
                TextField(
                  controller:
                      categoryController,
                  decoration:
                      const InputDecoration(
                    labelText: 'Category',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final amount =
                    double.tryParse(
                          amountController
                              .text,
                        ) ??
                        0;

                final day =
                    int.tryParse(
                          dayController
                              .text,
                        ) ??
                        1;

                if (nameController.text
                        .trim()
                        .isEmpty ||
                    amount <= 0) {
                  return;
                }

                await DB.addR(
                  R(
                    name: nameController
                        .text
                        .trim(),
                    account: account,
                    category:
                        categoryController
                            .text
                            .trim(),
                    amount: amount,
                    day: day.clamp(1, 31),
                  ),
                );

                if (dialogContext.mounted) {
                  Navigator.pop(
                    dialogContext,
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    amountController.dispose();
    dayController.dispose();
    categoryController.dispose();

    await load();
  }

  // ---------------------------------------------------------------------------
  // DATE RANGE
  // ---------------------------------------------------------------------------

  Future<void> datesPick() async {
    final result =
        await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: dates,
    );

    if (result != null) {
      setState(() {
        dates = result;
      });

      filter();
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // EXCEL EXPORT
  // -----------------------------------------------------------------------------

  Future<void> excel() async {
    final workbook =
        ex.Excel.createExcel();

    final sheet =
        workbook['Transactions'];

    sheet.appendRow([
      ex.TextCellValue('Date'),
      ex.TextCellValue('Type'),
      ex.TextCellValue('Account'),
      ex.TextCellValue('Category'),
      ex.TextCellValue('Subcategory'),
      ex.TextCellValue('Amount'),
      ex.TextCellValue('Description'),
    ]);

    for (final transaction in data) {
      sheet.appendRow([
        ex.TextCellValue(transaction.date),
        ex.TextCellValue(transaction.type),
        ex.TextCellValue(transaction.account),
        ex.TextCellValue(transaction.category),
        ex.TextCellValue(transaction.sub),
        ex.DoubleCellValue(transaction.amount),
        ex.TextCellValue(transaction.desc),
      ]);
    }

    final bytes = workbook.encode();

    if (bytes == null) {
      return;
    }

    final directory =
        await FilePicker.platform
            .getDirectoryPath();

    if (directory == null) {
      return;
    }

    final file = File(
      p.join(
        directory,
        'expense_report.xlsx',
      ),
    );

    await file.writeAsBytes(bytes);

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          'Excel saved to ${file.path}',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PDF EXPORT
  // ---------------------------------------------------------------------------

  Future<void> pdf() async {
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Monthly Financial Report',
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Income: ₹${total('Income').toStringAsFixed(2)}',
            ),
            pw.Text(
              'Expense: ₹${total('Expense').toStringAsFixed(2)}',
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: [
                'Date',
                'Type',
                'Category',
                'Amount',
              ],
              data: shown.map(
                (transaction) {
                  return [
                    transaction.date,
                    transaction.type,
                    transaction.category,
                    transaction.amount
                        .toStringAsFixed(2),
                  ];
                },
              ).toList(),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) => document.save(),
    );
  }

  // ---------------------------------------------------------------------------
  // PIN
  // ---------------------------------------------------------------------------

  Future<void> pinLock() async {
    final preferences =
        await SharedPreferences.getInstance();

    final controller =
        TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Set PIN'),
          content: TextField(
            controller: controller,
            keyboardType:
                TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration:
                const InputDecoration(
              labelText: 'PIN',
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (controller.text.length >= 4) {
                  await preferences.setString(
                    'pin',
                    controller.text,
                  );
                }

                if (dialogContext.mounted) {
                  Navigator.pop(
                    dialogContext,
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();
  }

  // ---------------------------------------------------------------------------
  // SMS IMPORT
  // ---------------------------------------------------------------------------

  Future<void> sms() async {
    final permission =
        await Permission.sms.request();

    if (!permission.isGranted) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'SMS permission is required',
          ),
        ),
      );

      return;
    }

    final messages =
        await SmsQuery().querySms(
      kinds: [
        SmsQueryKind.inbox,
      ],
      count: 100,
    );

    final regex = RegExp(
      r'(?:debited|spent|paid|credited|received|withdrawn|debit|credit)\D{0,30}(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]+)?)',
      caseSensitive: false,
    );

    int added = 0;

    for (final message in messages) {
      final body = message.body ?? '';

      final match =
          regex.firstMatch(body);

      if (match == null) {
        continue;
      }

      final amount =
          double.tryParse(
                match
                    .group(1)!
                    .replaceAll(',', ''),
              ) ??
              0;

      if (amount <= 0) {
        continue;
      }

      final date =
          DateFormat('yyyy-MM-dd HH:mm').format(
        message.date ??
            DateTime.now(),
      );

      if (data.any(
        (transaction) =>
            transaction.amount == amount &&
            transaction.date == date,
      )) {
        continue;
      }

      final lower =
          body.toLowerCase();

      final income =
          lower.contains('credited') ||
          lower.contains('received') ||
          lower.contains('credit');

      final category =
          lower.contains('swiggy') ||
                  lower.contains('zomato')
              ? 'Food'
              : lower.contains('uber') ||
                      lower.contains('ola')
                  ? 'Travel'
                  : lower.contains('bill') ||
                          lower.contains(
                            'recharge',
                          )
                      ? 'Bills'
                      : 'Other';

      final ok =
          await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'SMS Transaction Detected',
            ),
            content: SingleChildScrollView(
              child: Text(
                '₹${amount.toStringAsFixed(2)}\n\n$body',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    false,
                  );
                },
                child: const Text('Ignore'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    true,
                  );
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      );

      if (ok == true) {
        await DB.save(
          T(
            amount: amount,
            type: income
                ? 'Income'
                : 'Expense',
            account: 'Bank Account',
            category: category,
            sub: '',
            date: date,
            desc: 'SMS: $body',
          ),
        );

        added++;
      }
    }

    await load();

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '$added transaction(s) added',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Map<String, double> categories =
        {};

    for (final transaction
        in shown.where(
      (transaction) =>
          transaction.type == 'Expense',
    )) {
      categories[
              transaction.category] =
          (categories[
                  transaction.category] ??
              0) +
              transaction.amount;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Rupee Expense Tracker',
        ),
        actions: [
          IconButton(
            onPressed: sms,
            icon: const Icon(
              Icons.sms,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'cat') {
                category();
              }

              if (value == 'open') {
                openings();
              }

              if (value == 'budget') {
                budget();
              }

              if (value == 'rec') {
                recurringDialog();
              }

              if (value == 'excel') {
                excel();
              }

              if (value == 'pdf') {
                pdf();
              }

              if (value == 'pin') {
                pinLock();
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(
                  value: 'cat',
                  child: Text(
                    'Manual Categories',
                  ),
                ),
                PopupMenuItem(
                  value: 'open',
                  child: Text(
                    'Opening Balances',
                  ),
                ),
                PopupMenuItem(
                  value: 'budget',
                  child: Text(
                    'Budget vs Actual',
                  ),
                ),
                PopupMenuItem(
                  value: 'rec',
                  child: Text(
                    'Recurring Expenses',
                  ),
                ),
                PopupMenuItem(
                  value: 'excel',
                  child: Text(
                    'Export Excel',
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  child: Text(
                    'Monthly PDF Report',
                  ),
                ),
                PopupMenuItem(
                  value: 'pin',
                  child: Text(
                    'PIN Lock',
                  ),
                ),
              ];
            },
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.only(
            bottom: 100,
          ),
          children: [
            // PERIOD FILTER
            SingleChildScrollView(
              scrollDirection:
                  Axis.horizontal,
              child: Row(
                children: [
                  'Daily',
                  'Monthly',
                  'Yearly',
                  'All',
                ].map(
                  (value) {
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: ChoiceChip(
                        label: Text(value),
                        selected:
                            period == value,
                        onSelected: (_) {
                          setState(() {
                            period = value;
                            dates = null;
                          });

                          filter();
                        },
                      ),
                    );
                  },
                ).toList(),
              ),
            ),

            // ACCOUNT FILTER
            SingleChildScrollView(
              scrollDirection:
                  Axis.horizontal,
              child: Row(
                children: [
                  const Padding(
                    padding:
                        EdgeInsets.only(
                      left: 8,
                      right: 4,
                    ),
                    child: Text(
                      'Account:',
                    ),
                  ),
                  ...[
                    'All',
                    ...accounts,
                  ].map(
                    (value) {
                      return Padding(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 3,
                        ),
                        child: ChoiceChip(
                          label: Text(value),
                          selected:
                              acct == value,
                          onSelected: (_) {
                            setState(() {
                              acct = value;
                            });

                            filter();
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // SEARCH
            Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration:
                          const InputDecoration(
                        prefixIcon: Icon(
                          Icons.search,
                        ),
                        hintText:
                            'Search transactions',
                      ),
                      onChanged: (value) {
                        query = value;
                        filter();
                        setState(() {});
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: datesPick,
                    icon: const Icon(
                      Icons.date_range,
                    ),
                  ),
                ],
              ),
            ),

            // INCOME / EXPENSE
            Row(
              children: [
                Expanded(
                  child: _card(
                    'Income',
                    '₹${total('Income').toStringAsFixed(0)}',
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _card(
                    'Expense',
                    '₹${total('Expense').toStringAsFixed(0)}',
                    Colors.red,
                  ),
                ),
              ],
            ),

            // ACCOUNT BALANCES
            Row(
              children: accounts.map(
                (account) {
                  return Expanded(
                    child: _card(
                      account,
                      '₹${(bal[account] ?? 0).toStringAsFixed(0)}',
                      Colors.blue,
                    ),
                  );
                },
              ).toList(),
            ),

            // CREDIT CARD OUTSTANDING
            Card(
              child: ListTile(
                title: const Text(
                  'Credit Card Outstanding',
                ),
                trailing: Text(
                  '₹${(-(bal['Credit Card'] ?? 0)).clamp(0, double.infinity).toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),

            // PIE CHART
            if (categories.isNotEmpty)
              SizedBox(
                height: 300,
                child: Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Category-wise Expense',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Expanded(
                          child: PieChart(
                            PieChartData(
                              sections:
                                  categories
                                      .entries
                                      .map(
                                (entry) {
                                  return PieChartSectionData(
                                    value:
                                        entry.value,
                                    title:
                                        entry.key,
                                    radius: 70,
                                  );
                                },
                              ).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // BUDGET
            if (bud.isNotEmpty)
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Budget vs Actual',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 10,
                      ),
                      ...bud.entries.map(
                        (entry) {
                          final actual =
                              data
                                  .where(
                            (transaction) =>
                                transaction
                                    .type ==
                                'Expense' &&
                                transaction
                                    .category ==
                                entry.key &&
                                transaction.date
                                    .startsWith(
                                  DateFormat(
                                    'yyyy-MM',
                                  ).format(
                                    DateTime.now(),
                                  ),
                                ),
                          )
                                  .fold(
                            0.0,
                            (sum,
                                    transaction) =>
                                sum +
                                transaction
                                    .amount,
                          );

                          final progress =
                              entry.value <= 0
                                  ? 0.0
                                  : (actual /
                                          entry.value)
                                      .clamp(
                                      0.0,
                                      1.0,
                                    )
                                      .toDouble();

                          return Padding(
                            padding:
                                const EdgeInsets
                                    .only(
                              bottom: 8,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment
                                          .spaceBetween,
                                  children: [
                                    Text(
                                      entry.key,
                                    ),
                                    Text(
                                      '₹${actual.toStringAsFixed(0)} / ₹${entry.value.toStringAsFixed(0)}',
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: 4,
                                ),
                                LinearProgressIndicator(
                                  value: progress,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

            // RECURRING EXPENSES
            if (rec.isNotEmpty)
              Card(
                child: ExpansionTile(
                  title: const Text(
                    'Recurring Expenses',
                  ),
                  children: rec.map(
                    (recurring) {
                      return ListTile(
                        title: Text(
                          recurring.name,
                        ),
                        subtitle: Text(
                          '${recurring.category} • Day ${recurring.day} • ${recurring.account}',
                        ),
                        trailing: Text(
                          '₹${recurring.amount.toStringAsFixed(0)}',
                        ),
                      );
                    },
                  ).toList(),
                ),
              ),

            // TRANSACTIONS
            ...shown.map(
              (transaction) {
                final title =
                    transaction.type ==
                            'Transfer'
                        ? '${transaction.account} → ${transaction.to}'
                        : '${transaction.category}${transaction.sub.isEmpty ? '' : ' • ${transaction.sub}'}';

                return Card(
                  child: ListTile(
                    leading:
                        const CircleAvatar(
                      child: Icon(
                        Icons.wallet,
                      ),
                    ),
                    title: Text(title),
                    subtitle: Text(
                      '${transaction.account} • ${transaction.date}\n${transaction.desc}',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        Text(
                          '₹${transaction.amount.toStringAsFixed(2)}',
                        ),
                        IconButton(
                          onPressed: () =>
                              edit(transaction),
                          icon: const Icon(
                            Icons.edit,
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            if (transaction.id !=
                                null) {
                              await DB.del(
                                transaction.id!,
                              );
                            }

                            await load();
                          },
                          icon: const Icon(
                            Icons
                                .delete_outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),

      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: () => edit(),
        icon: const Icon(
          Icons.add,
        ),
        label: const Text(
          'Add Entry',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY CARD
  // ---------------------------------------------------------------------------

  Widget _card(
    String title,
    String value,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight:
                    FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
