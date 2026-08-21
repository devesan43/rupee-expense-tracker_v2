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

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const App()); }

class App extends StatelessWidget {
  const App({super.key});
  @override Widget build(BuildContext c)=>MaterialApp(
    title:'Rupee Expense Tracker',debugShowCheckedModeBanner:false,
    theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff1b5e20))),
    home:const LockGate());
}

class T {
  int? id; double amount; String type,account,category,sub,date,desc; String? to;
  T({this.id,required this.amount,required this.type,required this.account,
    required this.category,required this.sub,required this.date,required this.desc,this.to});
  Map<String,dynamic> map()=>{'id':id,'amount':amount,'type':type,'account':account,
    'toAccount':to,'category':category,'subCategory':sub,'date':date,'description':desc};
  factory T.from(Map<String,dynamic>m)=>T(id:m['id'],amount:(m['amount'] as num).toDouble(),
    type:m['type'],account:m['account'],category:m['category']??'Other',
    sub:m['subCategory']??'',date:m['date'],desc:m['description']??'',to:m['toAccount']);
}

class R {
  int? id; String name,account,category; double amount; int day;
  R({this.id,required this.name,required this.account,required this.category,required this.amount,required this.day});
  Map<String,dynamic> map()=>{'id':id,'name':name,'account':account,'category':category,'amount':amount,'day':day};
  factory R.from(Map<String,dynamic>m)=>R(id:m['id'],name:m['name'],account:m['account'],
    category:m['category'],amount:(m['amount'] as num).toDouble(),day:m['day']);
}

class DB {
  static Database? d;
  static Future<Database> get db async {
    if(d!=null)return d!;
    d=await openDatabase(p.join(await getDatabasesPath(),'expense_v2.db'),version:1,onCreate:(db,v)async{
      await db.execute('CREATE TABLE tx(id INTEGER PRIMARY KEY AUTOINCREMENT,amount REAL,type TEXT,account TEXT,toAccount TEXT,category TEXT,subCategory TEXT,date TEXT,description TEXT)');
      await db.execute('CREATE TABLE cat(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT,type TEXT)');
      await db.execute('CREATE TABLE bal(account TEXT PRIMARY KEY,opening REAL)');
      await db.execute('CREATE TABLE budget(month TEXT,category TEXT,amount REAL,PRIMARY KEY(month,category))');
      await db.execute('CREATE TABLE recurring(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT,account TEXT,category TEXT,amount REAL,day INTEGER)');
      for(final a in ['Cash','Bank Account','Credit Card'])await db.insert('bal',{'account':a,'opening':0});
    });
    return d!;
  }
  static Future<List<T>> all()async=>(await (await db).query('tx',orderBy:'date DESC,id DESC')).map(T.from).toList();
  static Future<void> save(T t)async{final x=await db;if(t.id==null)await x.insert('tx',t.map());else await x.update('tx',t.map(),where:'id=?',whereArgs:[t.id]);}
  static Future<void> del(int id)=>db.then((x)=>x.delete('tx',where:'id=?',whereArgs:[id]));
  static Future<List<String>> cats(String type)async{
    final base={'Expense':['Food','Bills','Travel','Shopping','Health','Education','Utilities','Other'],
      'Income':['Salary','Business','Investment','Gift','Other'],
      'Savings':['Emergency Fund','FD','Mutual Funds','Gold'],
      'Credit':['Personal Loan','Borrowed','Lent','Credit Card Debt'],
      'Transfer':['Account Transfer']}[type]??['Other'];
    final r=await (await db).query('cat',where:'type=?',whereArgs:[type]);
    return {...base,...r.map((e)=>e['name'] as String)}.toList();
  }
  static Future<void> addCat(String n,String t)=>db.then((x)=>x.insert('cat',{'name':n,'type':t}));
  static Future<double> opening(String a)async{final r=await (await db).query('bal',where:'account=?',whereArgs:[a]);return r.isEmpty?0:(r.first['opening']as num).toDouble();}
  static Future<void> setOpening(String a,double v)=>db.then((x)=>x.update('bal',{'opening':v},where:'account=?',whereArgs:[a]));
  static Future<void> setBudget(String m,String c,double v)=>db.then((x)=>x.insert('budget',{'month':m,'category':c,'amount':v},conflictAlgorithm:ConflictAlgorithm.replace));
  static Future<Map<String,double>> budgets(String m)async{
    final r=await (await db).query('budget',where:'month=?',whereArgs:[m]);
    return {for(final e in r)e['category'] as String:(e['amount']as num).toDouble()};
  }
  static Future<List<R>> recurring()async=>(await (await db).query('recurring',orderBy:'day')).map(R.from).toList();
  static Future<void> addR(R r)=>db.then((x)=>x.insert('recurring',r.map()));
}

class LockGate extends StatefulWidget{const LockGate({super.key});@override State<LockGate>createState()=>_LockGateState();}
class _LockGateState extends State<LockGate>{
  bool busy=true,locked=false;final pin=TextEditingController();final auth=LocalAuthentication();
  @override void initState(){super.initState();init();}
  Future<void>init()async{final s=await SharedPreferences.getInstance();final p=s.getString('pin');
    if(p!=null){locked=true;try{if(s.getBool('bio')==true&&(await auth.isDeviceSupported()))locked=!(await auth.authenticate(localizedReason:'Unlock Expense Tracker'));}catch(_){}}setState(()=>busy=false);}
  @override Widget build(BuildContext c){if(busy)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(!locked)return const Home();return Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(32),child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.lock,size:60),const Text('Expense Tracker Locked',style:TextStyle(fontSize:22)),
      TextField(controller:pin,obscureText:true,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'PIN')),
      ElevatedButton(onPressed:()async{final s=await SharedPreferences.getInstance();if(pin.text==s.getString('pin'))setState(()=>locked=false);},child:const Text('Unlock'))
    ]))));}
}

class Home extends StatefulWidget{const Home({super.key});@override State<Home>createState()=>_HomeState();}
class _HomeState extends State<Home>{
  final accounts=['Cash','Bank Account','Credit Card'],types=['Expense','Income','Savings','Credit','Transfer'];
  List<T> data=[],shown=[];Map<String,double> bal={},bud={};List<R> rec=[];String period='Monthly',acct='All',query='';DateTimeRange? dates;
  @override void initState(){super.initState();load();}
  Future<void>load()async{data=await DB.all();rec=await DB.recurring();bud=await DB.budgets(DateFormat('yyyy-MM').format(DateTime.now()));
    bal={};for(final a in accounts)bal[a]=await DB.opening(a);
    for(final t in data){if(t.type=='Income')bal[t.account]=(bal[t.account]??0)+t.amount;
      if(t.type=='Expense'||t.type=='Credit')bal[t.account]=(bal[t.account]??0)-t.amount;
      if(t.type=='Transfer'){bal[t.account]=(bal[t.account]??0)-t.amount;if(t.to!=null)bal[t.to!]=(bal[t.to!]??0)+t.amount;}}
    filter();setState((){});}
  void filter(){final now=DateTime.now();shown=data.where((t){final d=DateTime.tryParse(t.date)??now;
    if(acct!='All'&&t.account!=acct)return false;if(dates!=null&&(d.isBefore(dates!.start)||d.isAfter(dates!.end.add(const Duration(days:1)))))return false;
    if(dates==null){if(period=='Daily'&&!t.date.startsWith(DateFormat('yyyy-MM-dd').format(now)))return false;
      if(period=='Monthly'&&!t.date.startsWith(DateFormat('yyyy-MM').format(now)))return false;
      if(period=='Yearly'&&!t.date.startsWith(DateFormat('yyyy').format(now)))return false;}
    if(query.isNotEmpty&&!('${t.category} ${t.sub} ${t.desc} ${t.account}'.toLowerCase().contains(query.toLowerCase())))return false;return true;}).toList();}
  double total(String type)=>shown.where((t)=>t.type==type).fold(0,(a,t)=>a+t.amount);
  Future<void>edit([T? old])async{
    final a=TextEditingController(text:old?.amount.toString()??''),d=TextEditingController(text:old?.desc??''),sub=TextEditingController(text:old?.sub??'');
    String ty=old?.type??'Expense',ac=old?.account??'Cash',to=old?.to??'Bank Account',cat=old?.category??'Other';
    await showModalBottomSheet(context:context,isScrollControlled:true,builder:(c)=>StatefulBuilder(builder:(c,set)=>Padding(
      padding:EdgeInsets.fromLTRB(16,16,16,MediaQuery.of(c).viewInsets.bottom+16),child:SingleChildScrollView(child:Column(children:[
        Text(old==null?'New Entry':'Edit Entry',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        DropdownButtonFormField(value:ty,items:types.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)async{ty=v!;cat=(await DB.cats(ty)).first;set((){});}),
        DropdownButtonFormField(value:ac,items:accounts.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>set(()=>ac=v!)),
        if(ty=='Transfer')DropdownButtonFormField(value:to,items:accounts.where((x)=>x!=ac).map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>set(()=>to=v!)),
        if(ty!='Transfer')DropdownButtonFormField(value:cat,items:(await DB.cats(ty)).map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>set(()=>cat=v!)),
        TextField(controller:sub,decoration:const InputDecoration(labelText:'Sub-category')),
        TextField(controller:a,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Amount ₹')),
        TextField(controller:d,decoration:const InputDecoration(labelText:'Description')),
        ElevatedButton(onPressed:()async{final n=double.tryParse(a.text)??0;if(n<=0)return;await DB.save(T(id:old?.id,amount:n,type:ty,account:ac,to:ty=='Transfer'?to:null,category:ty=='Transfer'?'Transfer':cat,sub:sub.text,date:old?.date??DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),desc:d.text));if(c.mounted)Navigator.pop(c);},child:Text(old==null?'Save':'Update'))
      ]))));load();}
  Future<void>category()async{final n=TextEditingController();String ty='Expense';await showDialog(context:context,builder:(c)=>AlertDialog(title:const Text('Manual Category'),
    content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField(value:ty,items:types.where((x)=>x!='Transfer').map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>ty=v!),
      TextField(controller:n,decoration:const InputDecoration(labelText:'Category'))]),actions:[ElevatedButton(onPressed:()async{if(n.text.trim().isNotEmpty)await DB.addCat(n.text.trim(),ty);if(c.mounted)Navigator.pop(c);},child:const Text('Save'))]));}
  Future<void>openings()async{for(final x in accounts){final c=TextEditingController(text:'${await DB.opening(x)}');await showDialog(context:context,builder:(q)=>AlertDialog(title:Text('$x Opening Balance'),
    content:TextField(controller:c,keyboardType:TextInputType.number),actions:[ElevatedButton(onPressed:()async{await DB.setOpening(x,double.tryParse(c.text)??0);if(q.mounted)Navigator.pop(q);},child:const Text('Save'))]));}load();}
  Future<void>budget()async{final cs=await DB.cats('Expense');String cat=cs.first;final c=TextEditingController(text:'${bud[cat]??0}');await showDialog(context:context,builder:(q)=>StatefulBuilder(builder:(q,set)=>AlertDialog(title:const Text('Budget vs Actual'),
    content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField(value:cat,items:cs.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>set(()=>cat=v!)),TextField(controller:c,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Monthly budget ₹'))]),
    actions:[ElevatedButton(onPressed:()async{await DB.setBudget(DateFormat('yyyy-MM').format(DateTime.now()),cat,double.tryParse(c.text)??0);if(q.mounted)Navigator.pop(q);},child:const Text('Save'))])));load();}
  Future<void>recurringDialog()async{final n=TextEditingController(),a=TextEditingController(),day=TextEditingController(text:'1'),cat=TextEditingController(text:'Bills');String ac='Bank Account';
    await showDialog(context:context,builder:(q)=>AlertDialog(title:const Text('Recurring Expense'),content:SingleChildScrollView(child:Column(children:[
      TextField(controller:n,decoration:const InputDecoration(labelText:'Name')),
      TextField(controller:a,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Amount ₹')),
      TextField(controller:day,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Day of month')),
      DropdownButtonFormField(value:ac,items:accounts.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>ac=v!),
      TextField(controller:cat,decoration:const InputDecoration(labelText:'Category'))])),actions:[ElevatedButton(onPressed:()async{await DB.addR(R(name:n.text,account:ac,category:cat.text,amount:double.tryParse(a.text)??0,day:int.tryParse(day.text)??1));if(q.mounted)Navigator.pop(q);},child:const Text('Save'))]));load();}
  Future<void>datesPick()async{final r=await showDateRangePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime(2100),initialDateRange:dates);if(r!=null){dates=r;filter();setState((){});}}
  Future<void>excel()async{final b=ex.Excel.createExcel();final s=b['Transactions'];s.appendRow(['Date','Type','Account','Category','Subcategory','Amount','Description']);for(final t in data)s.appendRow([t.date,t.type,t.account,t.category,t.sub,t.amount,t.desc]);final z=b.encode();if(z==null)return;final dir=await FilePicker.platform.getDirectoryPath();if(dir==null)return;await File(p.join(dir,'expense_report.xlsx')).writeAsBytes(z);}
  Future<void>pdf()async{final d=pw.Document();d.addPage(pw.MultiPage(build:(c)=>[pw.Header(text:'Monthly Financial Report'),pw.Text('Income ₹${total('Income').toStringAsFixed(2)}'),pw.Text('Expense ₹${total('Expense').toStringAsFixed(2)}'),pw.Table.fromTextArray(headers:['Date','Type','Category','Amount'],data:shown.map((t)=>[t.date,t.type,t.category,t.amount.toStringAsFixed(2)]).toList())]));await Printing.layoutPdf(onLayout:(_)=>d.save());}
  Future<void>pinLock()async{final s=await SharedPreferences.getInstance();final c=TextEditingController();await showDialog(context:context,builder:(q)=>AlertDialog(title:const Text('Set PIN'),content:TextField(controller:c,keyboardType:TextInputType.number,obscureText:true,maxLength:6),actions:[ElevatedButton(onPressed:()async{if(c.text.length>=4)await s.setString('pin',c.text);if(q.mounted)Navigator.pop(q);},child:const Text('Save'))]));}
  Future<void>sms()async{if(!(await Permission.sms.request()).isGranted)return;final ms=await SmsQuery().querySms(kinds:[SmsQueryKind.inbox],count:100);final re=RegExp(r'(?:debited|spent|paid|credited|received|withdrawn|debit|credit)\D{0,30}(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]+)?)',caseSensitive:false);int n=0;
    for(final m in ms){final body=m.body??'';final x=re.firstMatch(body);if(x==null)continue;final amt=double.tryParse(x.group(1)!.replaceAll(',',''))??0;if(amt<=0)continue;final dt=DateFormat('yyyy-MM-dd HH:mm').format(m.date??DateTime.now());if(data.any((t)=>t.amount==amt&&t.date==dt))continue;
      final low=body.toLowerCase();final inc=low.contains('credited')||low.contains('received')||low.contains('credit');final cat=low.contains('swiggy')||low.contains('zomato')?'Food':low.contains('uber')||low.contains('ola')?'Travel':low.contains('bill')||low.contains('recharge')?'Bills':'Other';
      final ok=await showDialog<bool>(context:context,builder:(q)=>AlertDialog(title:const Text('SMS Transaction Detected'),content:Text('₹$amt\n$body'),actions:[TextButton(onPressed:()=>Navigator.pop(q,false),child:const Text('Ignore')),ElevatedButton(onPressed:()=>Navigator.pop(q,true),child:const Text('Add'))]));if(ok==true){await DB.save(T(amount:amt,type:inc?'Income':'Expense',account:'Bank Account',category:cat,sub:'',date:dt,desc:'SMS: $body'));n++;}}
    load();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$n transaction(s) added')));}
  @override Widget build(BuildContext c){final cats=<String,double>{};for(final t in shown.where((x)=>x.type=='Expense'))cats[t.category]=(cats[t.category]??0)+t.amount;
    return Scaffold(appBar:AppBar(title:const Text('Rupee Expense Tracker'),actions:[IconButton(onPressed:sms,icon:const Icon(Icons.sms)),PopupMenuButton<String>(onSelected:(v){if(v=='cat')category();if(v=='open')openings();if(v=='budget')budget();if(v=='rec')recurringDialog();if(v=='excel')excel();if(v=='pdf')pdf();if(v=='pin')pinLock();},itemBuilder:(c)=>const[
      PopupMenuItem(value:'cat',child:Text('Manual Categories')),PopupMenuItem(value:'open',child:Text('Opening Balances')),PopupMenuItem(value:'budget',child:Text('Budget vs Actual')),
      PopupMenuItem(value:'rec',child:Text('Recurring Expenses')),PopupMenuItem(value:'excel',child:Text('Export Excel')),PopupMenuItem(value:'pdf',child:Text('Monthly PDF Report')),PopupMenuItem(value:'pin',child:Text('PIN Lock'))])]),
      body:RefreshIndicator(onRefresh:load,child:ListView(children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:['Daily','Monthly','Yearly','All'].map((v)=>ChoiceChip(label:Text(v),selected:period==v,onSelected:(_){setState(()=>period=v);dates=null;filter();})).toList()),
        Row(children:[Expanded(child:TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search'),onChanged:(v){query=v;filter();setState((){});})),IconButton(onPressed:datesPick,icon:const Icon(Icons.date_range))]),
        Row(children:[Expanded(child:_card('Income','₹${total('Income').toStringAsFixed(0)}',Colors.green)),Expanded(child:_card('Expense','₹${total('Expense').toStringAsFixed(0)}',Colors.red))]),
        Row(children:accounts.map((a)=>Expanded(child:_card(a,'₹${(bal[a]??0).toStringAsFixed(0)}',Colors.blue))).toList()),
        Card(child:ListTile(title:const Text('Credit Card Outstanding'),trailing:Text('₹${(-(bal['Credit Card']??0)).clamp(0,double.infinity).toStringAsFixed(0)}',style:const TextStyle(color:Colors.red,fontWeight:FontWeight.bold)))),
        if(cats.isNotEmpty)SizedBox(height:250,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[const Text('Category-wise Expense'),Expanded(child:PieChart(PieChartData(sections:cats.entries.map((e)=>PieChartSectionData(value:e.value,title:e.key,radius:70)).toList())))])))),
        if(bud.isNotEmpty)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Budget vs Actual'),...bud.entries.map((e){final a=data.where((t)=>t.type=='Expense'&&t.category==e.key&&t.date.startsWith(DateFormat('yyyy-MM').format(DateTime.now()))).fold(0.0,(s,t)=>s+t.amount);return Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(e.key),Text('₹${a.toStringAsFixed(0)} / ₹${e.value.toStringAsFixed(0)}')]),LinearProgressIndicator(value:e.value==0?0:(a/e.value).clamp(0,1)),const SizedBox(height:6)]})})]))),
        if(rec.isNotEmpty)Card(child:ExpansionTile(title:const Text('Recurring Expenses'),children:rec.map((r)=>ListTile(title:Text(r.name),subtitle:Text('${r.category} • Day ${r.day} • ${r.account}'),trailing:Text('₹${r.amount.toStringAsFixed(0)}')).toList())),
        ...shown.map((t)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.wallet)),title:Text(t.type=='Transfer'?'${t.account} → ${t.to}':'${t.category}${t.sub.isEmpty?'':' • ${t.sub}'}'),subtitle:Text('${t.account} • ${t.date}\n${t.desc}'),isThreeLine:true,trailing:Wrap(children:[Text('₹${t.amount.toStringAsFixed(2)}'),IconButton(onPressed:()=>edit(t),icon:const Icon(Icons.edit)),IconButton(onPressed:()async{if(t.id!=null)await DB.del(t.id!);load();},icon:const Icon(Icons.delete_outline))]))))
      ])),floatingActionButton:FloatingActionButton.extended(onPressed:()=>edit(),icon:const Icon(Icons.add),label:const Text('Add Entry'));}
  Widget _card(String a,String v,Color col)=>Card(child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[Text(a,style:const TextStyle(fontSize:11)),Text(v,style:TextStyle(color:col,fontWeight:FontWeight.bold))])));
}
