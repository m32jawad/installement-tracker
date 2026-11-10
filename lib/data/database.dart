import 'package:sqflite/sqflite.dart';

/// SQLite schema (spec section 4). Bump [schemaVersion] and add a step to
/// [_migrate] for every schema change; never edit an existing step.
const schemaVersion = 1;
const dbFileName = 'installment_tracker.db';

Future<void> _createV1(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT NOT NULL,
      alt_phone TEXT,
      cnic TEXT,
      address TEXT,
      photo TEXT,
      guarantor_name TEXT,
      guarantor_phone TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT
    )''');
  await db.execute('''
    CREATE TABLE items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT,
      brand TEXT,
      model TEXT,
      imei TEXT,
      description TEXT,
      purchase_cost INTEGER DEFAULT 0,
      selling_price INTEGER DEFAULT 0,
      photos TEXT,
      status TEXT DEFAULT 'available',
      created_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE sales (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      item_id INTEGER REFERENCES items(id) ON DELETE SET NULL,
      sale_date TEXT NOT NULL,
      total_price INTEGER NOT NULL,
      advance_amount INTEGER NOT NULL DEFAULT 0,
      advance_method TEXT,
      advance_date TEXT,
      monthly_amount INTEGER NOT NULL,
      total_installments INTEGER NOT NULL,
      frequency TEXT NOT NULL DEFAULT 'monthly',
      custom_days INTEGER DEFAULT 30,
      first_due_date TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      notes TEXT,
      created_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE installments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
      installment_number INTEGER NOT NULL,
      due_date TEXT NOT NULL,
      amount INTEGER NOT NULL,
      paid_amount INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      paid_date TEXT,
      payment_method TEXT,
      skipped INTEGER NOT NULL DEFAULT 0,
      skip_reason TEXT,
      note TEXT,
      created_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
      installment_id INTEGER REFERENCES installments(id) ON DELETE SET NULL,
      customer_id INTEGER NOT NULL,
      amount INTEGER NOT NULL,
      payment_date TEXT NOT NULL,
      method TEXT NOT NULL,
      transaction_id TEXT,
      bank_name TEXT,
      cheque_number TEXT,
      receipt_photo TEXT,
      note TEXT,
      is_advance INTEGER NOT NULL DEFAULT 0,
      apply_extra INTEGER NOT NULL DEFAULT 1,
      created_by TEXT,
      created_at TEXT NOT NULL,
      edited_at TEXT
    )''');
  await db.execute('''
    CREATE TABLE payment_edits (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      payment_id INTEGER NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
      changes TEXT NOT NULL,
      edited_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE security_documents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
      type TEXT NOT NULL,
      photo_url TEXT NOT NULL,
      note TEXT,
      cheque_number TEXT,
      bank_name TEXT,
      cheque_date TEXT,
      created_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE sale_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
      note TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )''');
  await db.execute('CREATE INDEX idx_inst_sale ON installments(sale_id)');
  await db.execute('CREATE INDEX idx_inst_due ON installments(due_date)');
  await db.execute('CREATE INDEX idx_pay_sale ON payments(sale_id)');
  await db.execute('CREATE INDEX idx_pay_date ON payments(payment_date)');
  await db.execute('CREATE INDEX idx_sales_customer ON sales(customer_id)');
}

Future<void> _migrate(Database db, int from, int to) async {
  // Future schema steps go here: if (from < 2) { ... }
}

Future<Database> openAppDatabase(String path, {DatabaseFactory? factory}) {
  final f = factory ?? databaseFactory;
  return f.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) => _createV1(db),
      onUpgrade: _migrate,
    ),
  );
}
