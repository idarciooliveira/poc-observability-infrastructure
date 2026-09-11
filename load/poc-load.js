import http from 'k6/http';
import { check, sleep } from 'k6';

// Sustained realistic traffic for the observability POC (banking + insurance).
// Run via scripts/load-k6.ps1|.sh (grafana/k6 in Docker, no local install).
//
// Env (wrappers pass these; defaults = Docker Desktop host mapping):
//   BANKING_URL, INSURANCE_URL, VUS, RAMP_MIN, STEADY_MIN, CHAOS_MODE
//
// Alignment with prod hardening 1-4: this script only drives app APIs —
// tenant separation happens server-side (gateway overwrites tenant.id and the
// collector fans out per-tenant with X-Scope-OrgID), so no OTLP headers are
// needed here. The k6 `tenant` tag below is load-side grouping only. None of
// these routes are /health|/ready, so the pipeline `filter` keeps all of it.
// After enabling multitenancy, reset volumes once then re-run load to
// repopulate both tenants; operator dashboards query federated
// banking-client|insurance-client, per-tenant DS prove isolation.

const BANKING_URL = __ENV.BANKING_URL || 'http://host.docker.internal:8080';
const INSURANCE_URL = __ENV.INSURANCE_URL || 'http://host.docker.internal:8083';
const VUS = parseInt(__ENV.VUS || '10', 10);
const RAMP_MIN = parseFloat(__ENV.RAMP_MIN || '2');
const STEADY_MIN = parseFloat(__ENV.STEADY_MIN || '5');
const CHAOS_MODE = (__ENV.CHAOS_MODE || 'off').toLowerCase();

// Seeds (see */src/main/resources/data.sql + scripts/collection/openapi.yaml).
const BANK_SEED_1 = 'BANK-0001'; // 5000.00
const BANK_SEED_2 = 'BANK-0002'; // 1500.00 — source ONLY for the insufficient-balance probe (never a dest)
const BANK_SEED_3 = 'BANK-0003'; // 50000.00 — source for the fraud-reject probe (15000 >= 10000)
const POLICY_ACTIVE_FULL = 'b1c2e8d0-2222-4b3b-8d2b-000000000001'; // ACTIVE limit 100000
const POLICY_ACTIVE_SMALL = 'b1c2e8d0-2222-4b3b-8d2b-000000000002'; // ACTIVE limit 50000
const POLICY_INACTIVE = 'b1c2e8d0-2222-4b3b-8d2b-000000000003'; // INACTIVE limit 75000
const POLICY_MISSING = 'b1c2e8d0-2222-4b3b-8d2b-000000009999'; // valid UUID, never seeded -> 404
const TRANSFER_MISSING = '00000000-0000-0000-0000-000000000000'; // valid UUID, never a transfer -> 404

const DOWN_MIN = STEADY_MIN <= 2 ? 0.5 : 1;

export const options = {
  scenarios: {
    banking: {
      executor: 'ramping-vus',
      exec: 'banking',
      startVUs: 0,
      stages: [
        { duration: `${RAMP_MIN}m`, target: VUS },
        { duration: `${STEADY_MIN}m`, target: VUS },
        { duration: `${DOWN_MIN}m`, target: 0 },
      ],
      gracefulRampDown: '30s',
    },
    insurance: {
      executor: 'ramping-vus',
      exec: 'insurance',
      startVUs: 0,
      stages: [
        { duration: `${RAMP_MIN}m`, target: VUS },
        { duration: `${STEADY_MIN}m`, target: VUS },
        { duration: `${DOWN_MIN}m`, target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    checks: ['rate>0.99'],
    http_req_duration:
      CHAOS_MODE === 'latency' ? ['p(95)<4000'] : ['p(95)<2000'],
  },
};

function jsonHeaders() {
  return { 'Content-Type': 'application/json' };
}

function tag(tenant, outcome) {
  return { headers: jsonHeaders(), tags: { tenant, outcome } };
}

// Weighted pick over [0,100): entries are [upperBoundExclusive, value].
function pick(table, r) {
  const roll = r === undefined ? Math.random() * 100 : r;
  for (const [bound, value] of table) {
    if (roll < bound) return value;
  }
  return table[table.length - 1][1];
}

function createAccount(base, accountNumber) {
  const res = http.post(
    `${base}/accounts`,
    JSON.stringify({ accountNumber, balance: 1000000.0 }),
    { headers: jsonHeaders(), tags: { tenant: 'banking', outcome: 'setup' } },
  );
  // 201 created, 409 when a previous run already created it — both fine.
  check(res, { 'setup account 201/409': (r) => r.status === 201 || r.status === 409 });
  return res;
}

export function setup() {
  // One funded source account per VU (no cross-VU balance collisions) plus a
  // single shared dest (crediting is unbounded, it can never drain).
  const ts = Date.now();
  const sources = [];
  const n = Math.max(1, VUS);
  for (let i = 0; i < n; i++) {
    const name = `LOAD-${ts}-${i}`;
    createAccount(BANKING_URL, name);
    sources.push(name);
  }
  const dest = `LOAD-${ts}-DST`;
  createAccount(BANKING_URL, dest);
  return { sources, dest };
}

// Per-VU state: last approved transfer id for the GET /transfers/{id} 200 probe.
// (Top-level `let` is VU-scoped in k6: each VU gets its own copy.)
let lastTransferId = null;

function mySource(data) {
  const srcs = data && data.sources && data.sources.length ? data.sources : [BANK_SEED_1];
  return srcs[(__VU - 1) % srcs.length];
}

function myDest(data) {
  return (data && data.dest) || BANK_SEED_1;
}

export function banking(data) {
  const src = mySource(data);
  const dst = myDest(data);
  const kind = pick([
    [55, 'approved'],
    [65, 'fraud_reject'],
    [75, 'insufficient'],
    [78, 'notfound'],
    [80, 'invalid'],
    [100, 'read'],
  ]);

  let res;
  let expected;
  let outcome = kind;

  if (kind === 'approved') {
    const amount = (10 + Math.random() * 490).toFixed(2);
    res = http.post(
      `${BANKING_URL}/transfers`,
      JSON.stringify({ sourceAccountNumber: src, destinationAccountNumber: dst, amount: parseFloat(amount) }),
      tag('banking', 'approved'),
    );
    expected = 201;
    if (res.status === 201) {
      try {
        lastTransferId = res.json('id') || res.json('transferId');
      } catch (e) {
        lastTransferId = null;
      }
    }
  } else if (kind === 'fraud_reject') {
    // BANK-0003 covers 15000; fraud rejects amounts >= 10000 (balance first, no debit).
    res = http.post(
      `${BANKING_URL}/transfers`,
      JSON.stringify({ sourceAccountNumber: BANK_SEED_3, destinationAccountNumber: BANK_SEED_1, amount: 15000.0 }),
      tag('banking', 'fraud_reject'),
    );
    expected = 422;
  } else if (kind === 'insufficient') {
    // BANK-0002 (1500) can never cover 5000; fraud would approve (5000 < 10000) but balance wins first.
    res = http.post(
      `${BANKING_URL}/transfers`,
      JSON.stringify({ sourceAccountNumber: BANK_SEED_2, destinationAccountNumber: BANK_SEED_1, amount: 5000.0 }),
      tag('banking', 'insufficient_balance'),
    );
    expected = 422;
    outcome = 'insufficient_balance';
  } else if (kind === 'notfound') {
    res = http.post(
      `${BANKING_URL}/transfers`,
      JSON.stringify({ sourceAccountNumber: 'NOPE-9999', destinationAccountNumber: BANK_SEED_1, amount: 10.0 }),
      tag('banking', 'notfound'),
    );
    expected = 404;
  } else if (kind === 'invalid') {
    // Bean validation (@DecimalMin 0.01) rejects before the use case -> 400.
    res = http.post(
      `${BANKING_URL}/transfers`,
      JSON.stringify({ sourceAccountNumber: src, destinationAccountNumber: dst, amount: 0.0 }),
      tag('banking', 'invalid'),
    );
    expected = 400;
  } else {
    // Reads: GET account (200), GET transfer by last id (200) or random id (404),
    // GET missing account (404). Each branch asserts its own exact status.
    const sub = pick([
      [50, 'account_hit'],
      [75, 'transfer'],
      [100, 'account_miss'],
    ]);
    if (sub === 'account_hit') {
      const acct = Math.random() < 0.5 ? src : BANK_SEED_1;
      res = http.get(`${BANKING_URL}/accounts/${acct}`, tag('banking', 'read'));
      expected = 200;
    } else if (sub === 'transfer') {
      if (lastTransferId) {
        res = http.get(`${BANKING_URL}/transfers/${lastTransferId}`, tag('banking', 'read'));
        expected = 200;
      } else {
        res = http.get(`${BANKING_URL}/transfers/${TRANSFER_MISSING}`, tag('banking', 'read'));
        expected = 404;
      }
    } else {
      res = http.get(`${BANKING_URL}/accounts/NOPE-9999`, tag('banking', 'read'));
      expected = 404;
    }
    outcome = 'read';
  }

  check(res, { [`banking:${outcome} status ${expected}`]: (r) => r.status === expected });
  sleep(0.3 + Math.random() * 0.5);
}

export function insurance(data) {
  // Insurance claims never drain (canCover is non-cumulative), so static seeds suffice.
  const kind = pick([
    [55, 'approved'],
    [65, 'high_value'],
    [75, 'exhaustion'],
    [80, 'inactive'],
    [85, 'notfound'],
    [88, 'coverage'],
    [90, 'invalid'],
    [100, 'read'],
  ]);

  let res;
  let expected;
  let outcome = kind;

  if (kind === 'approved') {
    res = http.post(
      `${INSURANCE_URL}/policies/${POLICY_ACTIVE_FULL}/claims`,
      JSON.stringify({ amount: 1000.0 }),
      tag('insurance', 'approved'),
    );
    expected = 201;
  } else if (kind === 'high_value') {
    // 60000 > 50000 high-value threshold (coverage 100000 still covers -> risk rejects).
    res = http.post(
      `${INSURANCE_URL}/policies/${POLICY_ACTIVE_FULL}/claims`,
      JSON.stringify({ amount: 60000.0 }),
      tag('insurance', 'high_value'),
    );
    expected = 422;
  } else if (kind === 'exhaustion') {
    // 45000 > 80% of 50000 (=40000) but < 50000 high-value -> coverage_exhaustion.
    res = http.post(
      `${INSURANCE_URL}/policies/${POLICY_ACTIVE_SMALL}/claims`,
      JSON.stringify({ amount: 45000.0 }),
      tag('insurance', 'coverage_exhaustion'),
    );
    expected = 422;
    outcome = 'coverage_exhaustion';
  } else if (kind === 'inactive') {
    res = http.post(
      `${INSURANCE_URL}/policies/${POLICY_INACTIVE}/claims`,
      JSON.stringify({ amount: 1000.0 }),
      tag('insurance', 'inactive'),
    );
    expected = 422;
  } else if (kind === 'notfound') {
    res = http.post(
      `${INSURANCE_URL}/policies/${POLICY_MISSING}/claims`,
      JSON.stringify({ amount: 1000.0 }),
      tag('insurance', 'notfound'),
    );
    expected = 404;
  } else if (kind === 'coverage') {
    // 200000 > 100000 limit -> canCover fails before risk -> 422.
    res = http.post(
      `${INSURANCE_URL}/policies/${POLICY_ACTIVE_FULL}/claims`,
      JSON.stringify({ amount: 200000.0 }),
      tag('insurance', 'coverage_exceeded'),
    );
    expected = 422;
    outcome = 'coverage_exceeded';
  } else if (kind === 'invalid') {
    // Bean validation (@DecimalMin 0.01) -> 400.
    res = http.post(
      `${INSURANCE_URL}/policies/${POLICY_ACTIVE_FULL}/claims`,
      JSON.stringify({ amount: 0 }),
      tag('insurance', 'invalid'),
    );
    expected = 400;
  } else {
    // No GET claim endpoint exists: reads are approved POSTs with small
    // variation (still 201), tagged outcome=read so dashboards can split them.
    const amount = (500 + Math.random() * 1000).toFixed(2);
    res = http.post(
      `${INSURANCE_URL}/policies/${POLICY_ACTIVE_FULL}/claims`,
      JSON.stringify({ amount: parseFloat(amount) }),
      tag('insurance', 'read'),
    );
    expected = 201;
    outcome = 'read';
  }

  check(res, { [`insurance:${outcome} status ${expected}`]: (r) => r.status === expected });
  sleep(0.3 + Math.random() * 0.5);
}
