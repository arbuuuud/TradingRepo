#!/usr/bin/env node

/**
 * Strategy Tester TSV Analytics & RBR/DBD DNA Probability Engine
 * 
 * Usage:
 *   node scripts/analyze-tester-results.js [path/to/file.tsv]
 *   bun scripts/analyze-tester-results.js [path/to/file.tsv]
 * 
 * If no file is provided, searches for the latest .tsv file in:
 * ~/mt5prefix/drive_c/users/alami/AppData/Roaming/MetaQuotes/Terminal/Common/Files/
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

// Default Wine Common Files directory on macOS
const DEFAULT_SEARCH_DIR = path.join(
  os.homedir(),
  'mt5prefix/drive_c/users/alami/AppData/Roaming/MetaQuotes/Terminal/Common/Files'
);

function findLatestTSV(dir) {
  if (!fs.existsSync(dir)) {
    return null;
  }

  const files = fs.readdirSync(dir)
    .filter(f => f.startsWith('rbr_dbd_analytics_') && f.endsWith('.tsv'))
    .map(f => {
      const fullPath = path.join(dir, f);
      const stat = fs.statSync(fullPath);
      return { file: f, path: fullPath, mtime: stat.mtimeMs };
    })
    .sort((a, b) => b.mtime - a.mtime);

  return files.length > 0 ? files[0].path : null;
}

function parseTSV(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split(/\r?\n/).filter(line => line.trim().length > 0);

  if (lines.length < 2) {
    throw new Error('TSV file is empty or missing headers.');
  }

  const headers = lines[0].split('\t').map(h => h.trim());
  const headerMap = {};
  headers.forEach((h, idx) => { headerMap[h] = idx; });

  const requiredCols = ['DealTicket', 'TradeType', 'DNA', 'Strength', 'ExhLevel', 'ProfitUSD', 'ProfitPoints', 'ExitReason'];
  for (const col of requiredCols) {
    if (headerMap[col] === undefined) {
      throw new Error(`Missing required column: ${col}`);
    }
  }

  const records = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split('\t');
    if (cols.length < headers.length) continue;

    const profitUSD = parseFloat(cols[headerMap['ProfitUSD']]) || 0.0;
    const profitPts = parseFloat(cols[headerMap['ProfitPoints']]) || 0.0;
    const strength = parseInt(cols[headerMap['Strength']], 10) || 0;
    const exhLevel = parseInt(cols[headerMap['ExhLevel']], 10) || 0;

    records.push({
      dealTicket: cols[headerMap['DealTicket']],
      posId: cols[headerMap['PosID']] || '',
      symbol: cols[headerMap['Symbol']] || '',
      tradeType: cols[headerMap['TradeType']],
      zoneType: cols[headerMap['ZoneType']] || '',
      zoneTF: cols[headerMap['ZoneTF']] || '',
      dna: cols[headerMap['DNA']] || '----',
      pillarT: parseInt(cols[headerMap['Pillar_T']], 10) || 0,
      pillarB: parseInt(cols[headerMap['Pillar_B']], 10) || 0,
      pillarF: parseInt(cols[headerMap['Pillar_F']], 10) || 0,
      pillarH: parseInt(cols[headerMap['Pillar_H']], 10) || 0,
      strength: strength,
      exhLevel: exhLevel,
      openTime: cols[headerMap['OpenTime']] || '',
      closeTime: cols[headerMap['CloseTime']] || '',
      openPrice: parseFloat(cols[headerMap['OpenPrice']]) || 0.0,
      closePrice: parseFloat(cols[headerMap['ClosePrice']]) || 0.0,
      profitUSD: profitUSD,
      profitPoints: profitPts,
      exitReason: cols[headerMap['ExitReason']] || 'UNKNOWN',
      comment: cols[headerMap['Comment']] || ''
    });
  }

  return records;
}

function computeMetrics(records) {
  const total = records.length;
  if (total === 0) {
    return {
      total: 0,
      wins: 0,
      losses: 0,
      winRate: 0,
      netProfit: 0,
      profitFactor: 0,
      avgPoints: 0,
      avgWinUSD: 0,
      avgLossUSD: 0,
      expectancy: 0
    };
  }

  let grossProfit = 0;
  let grossLoss = 0;
  let wins = 0;
  let losses = 0;
  let totalPoints = 0;

  for (const r of records) {
    totalPoints += r.profitPoints;
    if (r.profitUSD > 0) {
      wins++;
      grossProfit += r.profitUSD;
    } else if (r.profitUSD < 0) {
      losses++;
      grossLoss += Math.abs(r.profitUSD);
    } else {
      // flat break even (0 profit)
    }
  }

  const winRate = (wins / total) * 100;
  const netProfit = grossProfit - grossLoss;
  const profitFactor = grossLoss > 0 ? (grossProfit / grossLoss) : (grossProfit > 0 ? 99.99 : 0.0);
  const avgPoints = totalPoints / total;
  const avgWinUSD = wins > 0 ? (grossProfit / wins) : 0;
  const avgLossUSD = losses > 0 ? (grossLoss / losses) : 0;

  const pWin = wins / total;
  const pLoss = losses / total;
  const expectancy = (pWin * avgWinUSD) - (pLoss * avgLossUSD);

  return {
    total,
    wins,
    losses,
    winRate: Number(winRate.toFixed(1)),
    netProfit: Number(netProfit.toFixed(2)),
    profitFactor: Number(profitFactor.toFixed(2)),
    avgPoints: Number(avgPoints.toFixed(1)),
    avgWinUSD: Number(avgWinUSD.toFixed(2)),
    avgLossUSD: Number(avgLossUSD.toFixed(2)),
    expectancy: Number(expectancy.toFixed(2))
  };
}

function printSection(title) {
  console.log(`\n======================================================`);
  console.log(`  ${title}`);
  console.log(`======================================================`);
}

function main() {
  const args = process.argv.slice(2);
  let targetFile = args[0];

  if (targetFile === '--help' || targetFile === '-h') {
    console.log(`\nUsage:`);
    console.log(`  node scripts/analyze-tester-results.js [path/to/file.tsv]`);
    console.log(`  bun scripts/analyze-tester-results.js [path/to/file.tsv]`);
    console.log(`\nIf no file is provided, automatically searches for the latest .tsv in:`);
    console.log(`  ~/mt5prefix/drive_c/users/alami/AppData/Roaming/MetaQuotes/Terminal/Common/Files/\n`);
    process.exit(0);
  }

  if (!targetFile) {
    console.log(`[Info] No file specified. Searching latest in: ${DEFAULT_SEARCH_DIR}`);
    targetFile = findLatestTSV(DEFAULT_SEARCH_DIR);
    if (!targetFile) {
      console.error(`[Error] No TSV export files found in: ${DEFAULT_SEARCH_DIR}`);
      console.log(`Usage: node scripts/analyze-tester-results.js <path/to/file.tsv>`);
      process.exit(1);
    }
  }

  if (!fs.existsSync(targetFile)) {
    console.error(`[Error] Target file does not exist: ${targetFile}`);
    process.exit(1);
  }

  console.log(`\n[Analyzer] Loading file: ${path.resolve(targetFile)}`);
  const records = parseTSV(targetFile);

  if (records.length === 0) {
    console.log('[Notice] File contains valid headers, but 0 trades were logged.');
    return;
  }

  // 1. Overall Summary
  const globalMetrics = computeMetrics(records);
  printSection(`1. GLOBAL STRATEGY TESTER OVERVIEW (${records[0].symbol || 'ALL'} ${records[0].zoneTF || ''})`);
  console.log(`Total Closed Trades : ${globalMetrics.total}`);
  console.log(`Win Rate            : ${globalMetrics.winRate}% (${globalMetrics.wins} wins / ${globalMetrics.losses} losses)`);
  console.log(`Net Profit          : $${globalMetrics.netProfit}`);
  console.log(`Profit Factor       : ${globalMetrics.profitFactor}`);
  console.log(`Trade Expectancy    : $${globalMetrics.expectancy} per trade`);
  console.log(`Average Points      : ${globalMetrics.avgPoints} pts`);

  // Exit Reason Breakdown
  const exitCounts = {};
  records.forEach(r => {
    exitCounts[r.exitReason] = (exitCounts[r.exitReason] || 0) + 1;
  });
  console.log(`\nExit Distribution:`);
  Object.keys(exitCounts).forEach(reason => {
    const count = exitCounts[reason];
    const pct = ((count / records.length) * 100).toFixed(1);
    console.log(`  - ${reason.padEnd(14)}: ${String(count).padStart(4)} trades (${pct}%)`);
  });

  // 2. Strength Benchmark (Str 0 vs Str 1 vs Str 2)
  printSection('2. STRENGTH BENCHMARK: RAW BASELINE (Str 0) vs QUALIFIED (Str 1 & 2)');
  console.log('| Strength Level       | Trades | Win Rate | Net Profit | Profit Factor | Avg Points | Expectancy |');
  console.log('|----------------------|-------:|---------:|-----------:|--------------:|-----------:|-----------:|');

  const strengthLabels = {
    0: 'Str 0 (Baseline / Weak)',
    1: 'Str 1 (Moderate / 2★)',
    2: 'Str 2 (Master / 3-4★)'
  };

  [0, 1, 2].forEach(strVal => {
    const group = records.filter(r => r.strength === strVal);
    const m = computeMetrics(group);
    const label = strengthLabels[strVal].padEnd(20);
    console.log(`| ${label} | ${String(m.total).padStart(6)} | ${String(m.winRate + '%').padStart(8)} | ${String('$' + m.netProfit).padStart(10)} | ${String(m.profitFactor).padStart(13)} | ${String(m.avgPoints).padStart(10)} | ${String('$' + m.expectancy).padStart(10)} |`);
  });

  // 3. Individual Pillar Impact
  printSection('3. INDIVIDUAL PILLAR CONTRIBUTION (Active [1] vs Inactive [0])');
  console.log('| Pillar               | State    | Trades | Win Rate | Net Profit | Profit Factor | Avg Pts |');
  console.log('|----------------------|----------|-------:|---------:|-----------:|--------------:|--------:|');

  const pillars = [
    { name: 'T (Tight Base <= 3)', key: 'pillarT' },
    { name: 'B (BOS Body Close)',   key: 'pillarB' },
    { name: 'F (Attached FVG)',    key: 'pillarF' },
    { name: 'H (HTF Parent POI)',  key: 'pillarH' }
  ];

  pillars.forEach(p => {
    const activeGroup = records.filter(r => r[p.key] === 1);
    const inactiveGroup = records.filter(r => r[p.key] === 0);

    const mAct = computeMetrics(activeGroup);
    const mInact = computeMetrics(inactiveGroup);

    console.log(`| ${p.name.padEnd(20)} | Active   | ${String(mAct.total).padStart(6)} | ${String(mAct.winRate + '%').padStart(8)} | ${String('$' + mAct.netProfit).padStart(10)} | ${String(mAct.profitFactor).padStart(13)} | ${String(mAct.avgPoints).padStart(7)} |`);
    console.log(`| ${''.padEnd(20)} | Inactive | ${String(mInact.total).padStart(6)} | ${String(mInact.winRate + '%').padStart(8)} | ${String('$' + mInact.netProfit).padStart(10)} | ${String(mInact.profitFactor).padStart(13)} | ${String(mInact.avgPoints).padStart(7)} |`);
    console.log('|----------------------|----------|-------:|---------:|-----------:|--------------:|--------:|');
  });

  // 4. Combinatorial DNA Ranking (2^4 = 16 Setups)
  printSection('4. COMPLETE DNA COMBINATORIAL RANKING (Sorted by Expectancy)');
  console.log('| Rank | DNA  | Strength | Trades | Win Rate | Net Profit | Profit Factor | Expectancy | Avg Pts |');
  console.log('|:----:|:----:|:--------:|-------:|---------:|-----------:|--------------:|-----------:|--------:|');

  const dnaGroups = {};
  records.forEach(r => {
    const key = r.dna;
    if (!dnaGroups[key]) dnaGroups[key] = [];
    dnaGroups[key].push(r);
  });

  const dnaRankings = Object.keys(dnaGroups).map(dna => {
    const group = dnaGroups[dna];
    const m = computeMetrics(group);
    const avgStr = (group.reduce((acc, curr) => acc + curr.strength, 0) / group.length).toFixed(1);
    return { dna, avgStr, metrics: m };
  }).sort((a, b) => b.metrics.expectancy - a.metrics.expectancy);

  dnaRankings.forEach((item, idx) => {
    const rank = String(idx + 1).padStart(4);
    const dna = item.dna.padEnd(4);
    const str = String('Str ' + item.avgStr).padStart(8);
    const m = item.metrics;
    console.log(`| ${rank} | ${dna} | ${str} | ${String(m.total).padStart(6)} | ${String(m.winRate + '%').padStart(8)} | ${String('$' + m.netProfit).padStart(10)} | ${String(m.profitFactor).padStart(13)} | ${String('$' + m.expectancy).padStart(10)} | ${String(m.avgPoints).padStart(7)} |`);
  });

  // 5. Exhaustion Level Lifecycle Curve
  printSection('5. EXHAUSTION LEVEL DECAY CURVE (L0 Fresh -> L4 Critical)');
  console.log('| Exhaustion Level     | Trades | Win Rate | Net Profit | Profit Factor | Avg Points | Expectancy |');
  console.log('|----------------------|-------:|---------:|-----------:|--------------:|-----------:|-----------:|');

  const exhLabels = {
    0: 'L0 (Fresh / 0%)',
    1: 'L1 (Touched / 25%)',
    2: 'L2 (Half / 50%)',
    3: 'L3 (Deep / 75%)',
    4: 'L4 (Critical / 90%)',
    5: 'L5 (Exhausted / 100%)'
  };

  [0, 1, 2, 3, 4, 5].forEach(lvl => {
    const group = records.filter(r => r.exhLevel === lvl);
    if (group.length === 0) return;
    const m = computeMetrics(group);
    const label = (exhLabels[lvl] || `L${lvl}`).padEnd(20);
    console.log(`| ${label} | ${String(m.total).padStart(6)} | ${String(m.winRate + '%').padStart(8)} | ${String('$' + m.netProfit).padStart(10)} | ${String(m.profitFactor).padStart(13)} | ${String(m.avgPoints).padStart(10)} | ${String('$' + m.expectancy).padStart(10)} |`);
  });

  console.log(`\n[Analyzer] Analysis complete. Evaluated ${records.length} trade transactions.\n`);
}

main();
