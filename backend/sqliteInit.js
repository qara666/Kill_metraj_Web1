/**
 * sqliteInit.js
 * Создаёт все необходимые таблицы для работы в SQLite режиме.
 * Запускается вместо Postgres-специфичных ensureTable функций.
 */

const { sequelize } = require('./src/config/database');
const logger = require('./src/utils/logger');

const TABLES = [
  // api_dashboard_cache
  `CREATE TABLE IF NOT EXISTS api_dashboard_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payload TEXT NOT NULL,
    data_hash TEXT NOT NULL,
    status_code INTEGER DEFAULT 200,
    error_message TEXT,
    division_id TEXT,
    target_date TEXT,
    order_count INTEGER DEFAULT 0,
    courier_count INTEGER DEFAULT 0,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`,

  // api_status_history
  `CREATE TABLE IF NOT EXISTS api_status_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    status_code INTEGER,
    error_message TEXT,
    response_time INTEGER,
    division_id TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`,

  // manual_order_overrides
  `CREATE TABLE IF NOT EXISTS manual_order_overrides (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_number TEXT UNIQUE NOT NULL,
    payment_method TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`,

  // global_order_overrides
  `CREATE TABLE IF NOT EXISTS global_order_overrides (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id TEXT UNIQUE NOT NULL,
    override_data TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`,

  // calculated_routes
  `CREATE TABLE IF NOT EXISTS calculated_routes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id TEXT UNIQUE,
    division_id TEXT,
    courier_id TEXT,
    route_data TEXT,
    distance_km REAL,
    duration_min REAL,
    calculated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`,

  // api_kml_hubs
  `CREATE TABLE IF NOT EXISTS api_kml_hubs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    source_url TEXT,
    is_active INTEGER DEFAULT 1,
    last_sync_at TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`,

  // api_kml_zones
  `CREATE TABLE IF NOT EXISTS api_kml_zones (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hub_id INTEGER,
    name TEXT,
    polygon_data TEXT,
    properties TEXT,
    is_active INTEGER DEFAULT 1,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`,

  // dashboard_division_states
  `CREATE TABLE IF NOT EXISTS dashboard_division_states (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    division_id TEXT UNIQUE NOT NULL,
    state_data TEXT,
    last_updated TEXT DEFAULT CURRENT_TIMESTAMP
  )`,

  // api_geo_cache
  `CREATE TABLE IF NOT EXISTS api_geo_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    address TEXT UNIQUE,
    lat REAL,
    lng REAL,
    raw_response TEXT,
    types TEXT,
    is_success INTEGER DEFAULT 1,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`,

  // courier_settlements
  `CREATE TABLE IF NOT EXISTS courier_settlements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    courier_id TEXT,
    courier_name TEXT,
    division_id TEXT,
    settlement_date TEXT,
    shift_start TEXT,
    shift_end TEXT,
    total_cash_expected REAL,
    total_cash_received REAL,
    total_card_amount REAL,
    total_online_amount REAL,
    orders_count INTEGER,
    order_ids TEXT,
    status TEXT DEFAULT 'pending',
    settled_by TEXT,
    settled_at TEXT,
    notes TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
  )`,
];

async function initSQLiteTables() {
  logger.info('[SQLite] Initializing all tables...');
  for (const sql of TABLES) {
    try {
      await sequelize.query(sql);
    } catch (e) {
      logger.error('[SQLite] Failed to create table:', { error: e.message, sql: sql.split('\n')[0] });
    }
  }
  logger.info('[SQLite] All tables ready.');
}

module.exports = { initSQLiteTables };
