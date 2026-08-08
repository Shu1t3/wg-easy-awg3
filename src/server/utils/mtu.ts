import childProcess from 'node:child_process';
import fs from 'node:fs/promises';
import { networkInterfaces } from 'node:os';

import { createDebug } from 'obug';

const MTU_DEBUG = createDebug('MTU');

export interface MtuCalculation {
  detectedPmtu: number;
  interfaceMtu: number;
  interfaceName: string;
  testedTarget: string;
  isMeasured: boolean;
  recommendations: {
    awgRecommended: number;
    wgIpv4: number;
    wgIpv6: number;
    safeMobile: number;
    safeDoubleTunnel: number;
    pppoe: number;
    ethernet: number;
  };
  presets: Array<{
    id: string;
    value: number;
    title: string;
    desc: string;
    badge?: string;
  }>;
}

/**
 * Calculates derived AmneziaVPN and AmneziaWG MTU recommendations given a Path MTU.
 */
export function calculateMtuRecommendations(
  pmtu: number,
  interfaceMtu = 1500,
  interfaceName = 'eth0',
  testedTarget = '1.1.1.1',
  isMeasured = true
): MtuCalculation {
  const safePmtu = Math.max(1280, Math.min(pmtu, 9000));

  // AmneziaVPN IPv4 overhead: 20B IPv4 + 8B UDP + 32B AmneziaVPN = 60 bytes
  const wgIpv4 = safePmtu - 60;
  // AmneziaVPN IPv6 overhead: 40B IPv6 + 8B UDP + 32B AmneziaVPN = 80 bytes
  const wgIpv6 = safePmtu - 80;

  // For AmneziaWG (AWG 3.0) with junk packets and CPS obfuscation:
  // Standard recommended MTU is 1420 when PMTU is 1500 (or wgIpv4 if lower)
  const awgRecommended = Math.min(wgIpv4, 1420);

  // Mobile LTE / 5G / Roaming conservative MTU
  const safeMobile = Math.min(awgRecommended, 1280);

  const safeDoubleTunnel = 1360;
  const pppoe = 1412;
  const ethernet = 1500;

  const presets = [
    {
      id: 'awg-recommended',
      value: awgRecommended,
      title: 'awg.mtuDialog.presetAwgTitle',
      desc: 'awg.mtuDialog.presetAwgDesc',
      badge: 'AWG 3.0',
    },
    {
      id: 'wg-ipv4',
      value: wgIpv4,
      title: 'awg.mtuDialog.presetWgIpv4Title',
      desc: 'awg.mtuDialog.presetWgIpv4Desc',
      badge: 'AmneziaVPN IPv4',
    },
    {
      id: 'wg-ipv6',
      value: wgIpv6,
      title: 'awg.mtuDialog.presetWgIpv6Title',
      desc: 'awg.mtuDialog.presetWgIpv6Desc',
      badge: 'AmneziaVPN IPv6',
    },
    {
      id: 'double-tunnel',
      value: safeDoubleTunnel,
      title: 'awg.mtuDialog.presetDoubleTunnelTitle',
      desc: 'awg.mtuDialog.presetDoubleTunnelDesc',
      badge: 'Safe / Double Tunnel',
    },
    {
      id: 'mobile-roaming',
      value: safeMobile,
      title: 'awg.mtuDialog.presetMobileTitle',
      desc: 'awg.mtuDialog.presetMobileDesc',
      badge: 'LTE / Roaming',
    },
    {
      id: 'pppoe',
      value: pppoe,
      title: 'awg.mtuDialog.presetPppoeTitle',
      desc: 'awg.mtuDialog.presetPppoeDesc',
      badge: 'PPPoE / DSL',
    },
    {
      id: 'ethernet',
      value: ethernet,
      title: 'awg.mtuDialog.presetEthernetTitle',
      desc: 'awg.mtuDialog.presetEthernetDesc',
      badge: 'Ethernet',
    },
  ];

  return {
    detectedPmtu: safePmtu,
    interfaceMtu,
    interfaceName,
    testedTarget,
    isMeasured,
    recommendations: {
      awgRecommended,
      wgIpv4,
      wgIpv6,
      safeMobile,
      safeDoubleTunnel,
      pppoe,
      ethernet,
    },
    presets,
  };
}

/**
 * Detects the active primary local interface and its MTU.
 */
export async function detectLocalInterface(): Promise<{
  name: string;
  mtu: number;
}> {
  try {
    const interfaces = networkInterfaces();
    for (const [name, ifaces] of Object.entries(interfaces)) {
      if (
        name === 'lo' ||
        name.startsWith('wg') ||
        name.startsWith('docker') ||
        name.startsWith('br-') ||
        name.startsWith('veth')
      ) {
        continue;
      }

      if (ifaces && ifaces.length > 0) {
        // Try reading sysfs MTU on Linux
        try {
          const sysfsMtu = await fs.readFile(
            `/sys/class/net/${name}/mtu`,
            'utf-8'
          );
          const mtuNum = Number.parseInt(sysfsMtu.trim(), 10);
          if (!Number.isNaN(mtuNum) && mtuNum > 0) {
            return { name, mtu: mtuNum };
          }
        } catch {
          // Ignore sysfs error and fallback to default
        }

        return { name, mtu: 1500 };
      }
    }
  } catch (err) {
    MTU_DEBUG('Failed to detect local interfaces:', err);
  }

  return { name: 'eth0', mtu: 1500 };
}

/**
 * Sends a single probe ICMP ping with Don't Fragment (DF) flag.
 */
function probePing(
  target: string,
  payloadSize: number,
  timeoutMs = 1000
): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const isDarwin = process.platform === 'darwin';
    // Linux iputils / busybox uses -M do, macOS / BSD uses -D
    const args = isDarwin
      ? ['-c', '1', '-t', '1', '-D', '-s', String(payloadSize), target]
      : ['-c', '1', '-W', '1', '-M', 'do', '-s', String(payloadSize), target];

    const child = childProcess.spawn('ping', args, {
      timeout: timeoutMs + 200,
    });

    let stdoutData = '';
    let stderrData = '';

    child.stdout.on('data', (d) => {
      stdoutData += d.toString();
    });
    child.stderr.on('data', (d) => {
      stderrData += d.toString();
    });

    child.on('error', () => {
      resolve(false);
    });

    child.on('close', (code) => {
      if (code === 0) {
        const combined = (stdoutData + stderrData).toLowerCase();
        if (
          combined.includes('frag needed') ||
          combined.includes('message too long') ||
          combined.includes('packet too big')
        ) {
          resolve(false);
        } else {
          resolve(true);
        }
      } else {
        resolve(false);
      }
    });
  });
}

/**
 * Measures Path MTU (PMTUD) to a remote target using ICMP DF probes and binary search.
 */
export async function measurePathMtu(
  target = '1.1.1.1'
): Promise<{ pmtu: number; measured: boolean }> {
  // Validate target input
  const cleanTarget = target.trim().replace(/[^a-zA-Z0-9.:-]/g, '');
  if (!cleanTarget) {
    return { pmtu: 1500, measured: false };
  }

  try {
    // 1. Basic reachability probe
    const reachable = await probePing(cleanTarget, 56, 1200);
    if (!reachable) {
      MTU_DEBUG(`Target ${cleanTarget} unreachable for DF ping probe`);
      return { pmtu: 1500, measured: false };
    }

    // 2. Fast check: Standard Ethernet MTU 1500 (1472 payload + 28 bytes header)
    if (await probePing(cleanTarget, 1472, 1000)) {
      return { pmtu: 1500, measured: true };
    }

    // 3. Fast check: Standard PPPoE MTU 1492 (1464 payload + 28 bytes header)
    if (await probePing(cleanTarget, 1464, 1000)) {
      return { pmtu: 1492, measured: true };
    }

    // 4. Fast check: Cloud VPS MTU 1420 (1392 payload + 28 bytes header)
    if (await probePing(cleanTarget, 1392, 1000)) {
      // Binary search between 1392 and 1464
      let low = 1392;
      let high = 1464;
      let optimal = 1392;

      while (low <= high) {
        const mid = Math.floor((low + high) / 2);
        if (await probePing(cleanTarget, mid, 800)) {
          optimal = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      return { pmtu: optimal + 28, measured: true };
    }

    // 5. General binary search between 1200 and 1472
    let low = 1200;
    let high = 1472;
    let optimal = 0;

    while (low <= high) {
      const mid = Math.floor((low + high) / 2);
      if (await probePing(cleanTarget, mid, 800)) {
        optimal = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (optimal > 0) {
      return { pmtu: optimal + 28, measured: true };
    }
  } catch (err) {
    MTU_DEBUG('Error measuring PMTU:', err);
  }

  return { pmtu: 1500, measured: false };
}

/**
 * High-level function that runs the complete MTU diagnostic and calculation.
 */
export async function getMtuDiagnostic(
  customTarget?: string
): Promise<MtuCalculation> {
  const localIface = await detectLocalInterface();
  const defaultTargets = ['1.1.1.1', '8.8.8.8', '77.88.8.8', '9.9.9.9'];
  const targets = customTarget ? [customTarget] : defaultTargets;

  let bestPmtu = 0;
  let testedTarget = targets[0] ?? '1.1.1.1';
  let isMeasured = false;

  for (const target of targets) {
    const res = await measurePathMtu(target);
    if (res.measured) {
      bestPmtu = res.pmtu;
      testedTarget = target;
      isMeasured = true;
      break;
    }
  }

  if (bestPmtu === 0) {
    bestPmtu = localIface.mtu || 1500;
  }

  return calculateMtuRecommendations(
    bestPmtu,
    localIface.mtu,
    localIface.name,
    testedTarget,
    isMeasured
  );
}
