-- Gotchu MVP Database Schema

create extension if not exists pgcrypto;

create table users (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  kyc_status text default 'verified',
  stripe_account_id text,
  created_at timestamptz not null default now()
);

create table wallet_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  available_cents bigint not null default 0,
  created_at timestamptz not null default now()
);

create table ledger_entries (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references wallet_accounts(id) on delete cascade,
  type text not null,               -- SEND_P2P | RECEIVE_P2P | CREDIT_TOPUP | DEBIT_PAYOUT | CREDIT_TAP
  direction text not null,          -- DEBIT | CREDIT
  amount_cents bigint not null,
  ref_type text not null,           -- PAYMENT_SESSION | STRIPE_PI | GROUP | MANUAL
  ref_id text not null,
  created_at timestamptz not null default now()
);

create table payment_sessions (
  id uuid primary key default gen_random_uuid(),
  payee_id uuid not null references users(id),
  amount_cents bigint not null,
  split_mode text not null default 'single',  -- single|equal
  max_payers int not null default 1,
  status text not null default 'CREATED',     -- CREATED|ADVERTISING|LOCKED|PAID|TIMEOUT|CANCEL
  exp_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table session_eids (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references payment_sessions(id) on delete cascade,
  eid text not null,
  rotated_at timestamptz not null default now()
);

create table payment_groups (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references payment_sessions(id) on delete cascade,
  total_cents bigint not null,
  split_mode text not null default 'equal',
  created_at timestamptz not null default now()
);

create table group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references payment_groups(id) on delete cascade,
  payer_id uuid not null references users(id),
  share_cents bigint not null,
  state text not null default 'JOINED',  -- JOINED|PAID|DECLINED
  created_at timestamptz not null default now()
);

create table idempotency_keys (
  key text primary key,
  user_id uuid not null references users(id),
  route text not null,
  ref text,
  created_at timestamptz not null default now()
);

-- Indexes for performance
create index idx_session_eids_eid on session_eids(eid);
create index idx_ledger_wallet_id on ledger_entries(wallet_id);
create index idx_ledger_created_at on ledger_entries(created_at);
create index idx_idempotency_user_route on idempotency_keys(user_id, route);
create index idx_payment_sessions_status on payment_sessions(status);
create index idx_payment_sessions_exp_at on payment_sessions(exp_at);

