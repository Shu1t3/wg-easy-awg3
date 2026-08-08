import { describe, expect, test } from 'vitest';

import { RELEASE } from '#server/utils/config';
import { calculateMtuRecommendations } from '#server/utils/mtu';
import packageJson from '@@/package.json';

describe('MTU calculation and recommendations', () => {
  test('calculates optimal MTU values for standard 1500 Ethernet Path MTU', () => {
    const calc = calculateMtuRecommendations(
      1500,
      1500,
      'eth0',
      '1.1.1.1',
      true
    );

    expect(calc.detectedPmtu).toBe(1500);
    expect(calc.interfaceMtu).toBe(1500);
    expect(calc.interfaceName).toBe('eth0');
    expect(calc.testedTarget).toBe('1.1.1.1');
    expect(calc.isMeasured).toBe(true);

    // WireGuard IPv4: 1500 - 60 = 1440
    expect(calc.recommendations.wgIpv4).toBe(1440);
    // WireGuard IPv6: 1500 - 80 = 1420
    expect(calc.recommendations.wgIpv6).toBe(1420);
    // Recommended AmneziaWG: min(1440, 1420) = 1420
    expect(calc.recommendations.awgRecommended).toBe(1420);
    // Safe Mobile LTE: 1280
    expect(calc.recommendations.safeMobile).toBe(1280);
    expect(calc.recommendations.safeDoubleTunnel).toBe(1360);
    expect(calc.recommendations.pppoe).toBe(1412);
    expect(calc.recommendations.ethernet).toBe(1500);

    expect(calc.presets.length).toBe(7);
    const awgPreset = calc.presets.find((p) => p.id === 'awg-recommended');
    expect(awgPreset?.value).toBe(1420);
    const wgIpv4Preset = calc.presets.find((p) => p.id === 'wg-ipv4');
    expect(wgIpv4Preset?.value).toBe(1440);
  });

  test('calculates optimal MTU values for PPPoE 1492 Path MTU', () => {
    const calc = calculateMtuRecommendations(
      1492,
      1492,
      'ppp0',
      '8.8.8.8',
      true
    );

    expect(calc.detectedPmtu).toBe(1492);
    expect(calc.recommendations.wgIpv4).toBe(1432);
    expect(calc.recommendations.wgIpv6).toBe(1412);
    expect(calc.recommendations.awgRecommended).toBe(1420);
  });

  test('adjusts AmneziaWG recommendation when PMTU is lower than 1480', () => {
    const calc = calculateMtuRecommendations(
      1380,
      1380,
      'eth0',
      '1.1.1.1',
      true
    );

    expect(calc.detectedPmtu).toBe(1380);
    expect(calc.recommendations.wgIpv4).toBe(1320);
    expect(calc.recommendations.awgRecommended).toBe(1320);
    expect(calc.recommendations.safeMobile).toBe(1280);
  });

  test('clamps Path MTU bounds between 1280 and 9000', () => {
    const low = calculateMtuRecommendations(1000);
    expect(low.detectedPmtu).toBe(1280);

    const high = calculateMtuRecommendations(10000);
    expect(high.detectedPmtu).toBe(9000);
  });
});

describe('Version configuration', () => {
  test('package.json version matches 15.4.0-shu1t3', () => {
    expect(packageJson.version).toBe('15.4.0-shu1t3');
  });

  test('RELEASE matches v15.4.0-shu1t3', () => {
    expect(RELEASE).toBe('v15.4.0-shu1t3');
  });
});
