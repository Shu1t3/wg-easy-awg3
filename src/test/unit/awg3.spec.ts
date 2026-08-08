process.env.PORT = '51821';

import { describe, expect, test } from 'vitest';
import { wg } from '#server/utils/wgHelper';
import {
  HSchema,
  ISchema,
  JcSchema,
  JminSchema,
  JmaxSchema,
  SSchema,
  formatEndpoint,
} from '#server/utils/types';
import {
  InterfaceUpdateSchema,
  type InterfaceType,
} from '#db/repositories/interface/types';
import {
  ClientUpdateSchema,
  type ClientType,
} from '#db/repositories/client/types';
import {
  UserConfigUpdateSchema,
  type UserConfigType,
} from '#db/repositories/userConfig/types';
import type { HooksType } from '#db/repositories/hooks/types';

const baseInterface: InterfaceType = {
  name: 'wg0',
  device: 'wg0',
  port: 51820,
  privateKey: 'serverPrivateKey==',
  publicKey: 'serverPublicKey==',
  ipv4Cidr: '10.8.0.0/24',
  ipv6Cidr: 'fdcc:ad94:bacf:61a3::/64',
  mtu: 1420,
  routingTable: 'auto',
  jC: 7,
  jMin: 10,
  jMax: 1000,
  s1: 128,
  s2: 56,
  s3: 100,
  s4: 200,
  h1: '123456-123500',
  h2: '234567',
  h3: '345678',
  h4: '456789',
  i1: '<b 0x01020304><t>',
  i2: '<r 32>',
  i3: null,
  i4: null,
  i5: null,
  enabled: true,
  firewallEnabled: false,
  createdAt: '2026-01-01 00:00:00',
  updatedAt: '2026-01-01 00:00:00',
};

const baseHooks: HooksType = {
  id: 'wg0',
  preUp: '',
  postUp: '',
  preDown: '',
  postDown: '',
  createdAt: '2026-01-01 00:00:00',
  updatedAt: '2026-01-01 00:00:00',
};

const baseUserConfig: UserConfigType = {
  id: 'wg0',
  host: 'vpn.example.com',
  port: 51820,
  defaultDns: ['1.1.1.1', '8.8.8.8'],
  defaultAllowedIps: ['0.0.0.0/0', '::/0'],
  defaultMtu: 1420,
  defaultPersistentKeepalive: 25,
  defaultJC: 7,
  defaultJMin: 10,
  defaultJMax: 1000,
  defaultI1: '<b 0x01020304>',
  defaultI2: null,
  defaultI3: null,
  defaultI4: null,
  defaultI5: '<b 0x05060708>',
  createdAt: '2026-01-01 00:00:00',
  updatedAt: '2026-01-01 00:00:00',
};

const baseClient: ClientType = {
  id: 1,
  userId: 1,
  interfaceId: 'wg0',
  name: 'test-awg3-client',
  ipv4Address: '10.8.0.2',
  ipv6Address: 'fdcc:ad94:bacf:61a3::2',
  preUp: '',
  postUp: '',
  preDown: '',
  postDown: '',
  privateKey: 'clientPrivateKey==',
  publicKey: 'clientPublicKey==',
  preSharedKey: 'clientPreSharedKey==',
  expiresAt: null,
  allowedIps: null,
  serverAllowedIps: [],
  firewallIps: null,
  persistentKeepalive: 25,
  mtu: 1420,
  jC: 8,
  jMin: 20,
  jMax: 800,
  i1: '<b 0x05060708>',
  i2: null,
  i3: null,
  i4: null,
  i5: '<b 0x090a0b0c>',
  dns: null,
  serverEndpoint: null,
  enabled: true,
  createdAt: '2026-01-01 00:00:00',
  updatedAt: '2026-01-01 00:00:00',
};

describe('AWG 3.0 Configuration Generation', () => {

  test('generateServerInterface includes all AWG 3.0 parameters', () => {
    const config = wg.generateServerInterface(baseInterface, baseHooks, {
      enableIpv6: true,
    });

    expect(config).toContain('PrivateKey = serverPrivateKey==');
    expect(config).toContain('ListenPort = 51820');
    expect(config).toContain('MTU = 1420');
    expect(config).toContain('Jc = 7');
    expect(config).toContain('Jmin = 10');
    expect(config).toContain('Jmax = 1000');
    expect(config).toContain('S1 = 128');
    expect(config).toContain('S2 = 56');
    expect(config).toContain('S3 = 100');
    expect(config).toContain('S4 = 200');
    expect(config).toContain('H1 = 123456-123500');
    expect(config).toContain('H2 = 234567');
    expect(config).toContain('H3 = 345678');
    expect(config).toContain('H4 = 456789');
    expect(config).toContain('I1 = <b 0x01020304><t>');
    expect(config).toContain('I2 = <r 32>');
    expect(config).not.toContain('I3 =');
  });

  test('generateClientConfig inherits server S1-S4 and H1-H4 and includes client Jc and I1, I5', () => {
    const config = wg.generateClientConfig(
      baseInterface,
      baseUserConfig,
      baseClient,
      { enableIpv6: true }
    );

    expect(config).toContain('PrivateKey = clientPrivateKey==');
    expect(config).toContain('Address = 10.8.0.2/32, fdcc:ad94:bacf:61a3::2/128');
    expect(config).toContain('DNS = 1.1.1.1, 8.8.8.8');
    expect(config).toContain('Jc = 8');
    expect(config).toContain('Jmin = 20');
    expect(config).toContain('Jmax = 800');
    expect(config).toContain('S1 = 128');
    expect(config).toContain('S2 = 56');
    expect(config).toContain('S3 = 100');
    expect(config).toContain('S4 = 200');
    expect(config).toContain('H1 = 123456-123500');
    expect(config).toContain('H2 = 234567');
    expect(config).toContain('H3 = 345678');
    expect(config).toContain('H4 = 456789');
    expect(config).toContain('I1 = <b 0x05060708>');
    expect(config).toContain('I5 = <b 0x090a0b0c>');
    expect(config).not.toContain('I2 =');
    expect(config).toContain('PublicKey = serverPublicKey==');
    expect(config).toContain('AllowedIPs = 0.0.0.0/0, ::/0');
    expect(config).toContain('PersistentKeepalive = 25');
    expect(config).toContain('Endpoint = vpn.example.com:51820');
  });

  test('generateClientConfig with enableIpv6: false excludes IPv6 address and filters ::/0 from AllowedIPs', () => {
    const config = wg.generateClientConfig(
      baseInterface,
      baseUserConfig,
      baseClient,
      { enableIpv6: false }
    );

    expect(config).toContain('Address = 10.8.0.2/32');
    expect(config).not.toContain('fdcc:ad94:bacf:61a3::2/128');
    expect(config).toContain('AllowedIPs = 0.0.0.0/0');
    expect(config).not.toContain('::/0');
  });

  test('generateClientConfig formats IPv6 host with square brackets', () => {
    const ipv6UserConfig: UserConfigType = {
      ...baseUserConfig,
      host: '2001:db8:85a3::8a2e:370:7334',
      port: 51820,
    };

    const config = wg.generateClientConfig(
      baseInterface,
      ipv6UserConfig,
      baseClient,
      { enableIpv6: true }
    );

    expect(config).toContain('Endpoint = [2001:db8:85a3::8a2e:370:7334]:51820');
  });

  test('generateClientConfig formats custom DNS and custom AllowedIPs', () => {
    const customClient: ClientType = {
      ...baseClient,
      dns: ['10.8.0.1'],
      allowedIps: ['192.168.1.0/24', '10.0.0.0/8'],
    };

    const config = wg.generateClientConfig(
      baseInterface,
      baseUserConfig,
      customClient,
      { enableIpv6: true }
    );

    expect(config).toContain('DNS = 10.8.0.1');
    expect(config).toContain('AllowedIPs = 192.168.1.0/24, 10.0.0.0/8');
  });

  test('generates clean configuration when AWG parameters are null', () => {
    const cleanInterface: InterfaceType = {
      ...baseInterface,
      jC: null,
      jMin: null,
      jMax: null,
      s1: null,
      s2: null,
      s3: null,
      s4: null,
      h1: null,
      h2: null,
      h3: null,
      h4: null,
      i1: null,
      i2: null,
      i3: null,
      i4: null,
      i5: null,
    };

    const config = wg.generateServerInterface(cleanInterface, baseHooks);

    expect(config).not.toContain('Jc =');
    expect(config).not.toContain('S1 =');
    expect(config).not.toContain('H1 =');
    expect(config).not.toContain('I1 =');
    expect(config).toContain('PrivateKey = serverPrivateKey==');
  });
});

describe('formatEndpoint utility', () => {
  test('formats domain and IPv4 correctly', () => {
    expect(formatEndpoint('vpn.example.com', 51820)).toBe('vpn.example.com:51820');
    expect(formatEndpoint('192.168.1.1', 51820)).toBe('192.168.1.1:51820');
    expect(formatEndpoint('https://vpn.example.com/', 51820)).toBe(
      'vpn.example.com:51820'
    );
  });

  test('formats IPv6 with square brackets', () => {
    expect(formatEndpoint('2001:db8::1', 51820)).toBe('[2001:db8::1]:51820');
    expect(formatEndpoint('[2001:db8::1]', 51820)).toBe('[2001:db8::1]:51820');
    expect(formatEndpoint('fe80::1', 51820)).toBe('[fe80::1]:51820');
  });
});

describe('AWG 3.0 Zod Schema Validation', () => {
  test('HSchema validates single numbers and range formats across full uint32 range', () => {
    expect(HSchema.parse('123456')).toBe('123456');
    expect(HSchema.parse(' 100000 - 200000 ')).toBe('100000-200000');
    expect(HSchema.parse('1000-1000')).toBe('1000');
    expect(HSchema.parse('4294967295')).toBe('4294967295'); // Full uint32 max
    expect(HSchema.parse(' 3000000000 - 4000000000 ')).toBe(
      '3000000000-4000000000'
    );
    expect(HSchema.parse(null)).toBeNull();
    expect(HSchema.parse('')).toBeNull();

    expect(() => HSchema.parse('4294967296')).toThrow(); // Above uint32 max
    expect(() => HSchema.parse('2000-1000')).toThrow();
    expect(() => HSchema.parse('4')).toThrow(); // Below H_MIN (5)
    expect(() => HSchema.parse('invalid')).toThrow();
  });

  test('InterfaceUpdateSchema validates non-overlapping H1-H4 ranges and Jmin <= Jmax', () => {
    const validUpdate = {
      ipv4Cidr: '10.8.0.0/24',
      ipv6Cidr: 'fdcc:ad94:bacf:61a3::/64',
      mtu: 1420,
      routingTable: 'auto',
      jC: 7,
      jMin: 10,
      jMax: 1000,
      s1: 128,
      s2: 56,
      s3: 100,
      s4: 200,
      h1: '100000-200000',
      h2: '200001-300000',
      h3: '300001-400000',
      h4: '400001-500000',
      i1: null,
      i2: null,
      i3: null,
      i4: null,
      i5: null,
      port: 51820,
      device: 'wg0',
      enabled: true,
      firewallEnabled: false,
    };

    expect(InterfaceUpdateSchema.parse(validUpdate)).toBeDefined();

    // Invalid: Jmin > Jmax
    const invalidJmin = {
      ...validUpdate,
      jMin: 500,
      jMax: 100,
    };
    expect(() => InterfaceUpdateSchema.parse(invalidJmin)).toThrow();

    // Overlapping ranges: H1 (100000-200000) and H2 (150000-250000)
    const overlappingUpdate = {
      ...validUpdate,
      h1: '100000-200000',
      h2: '150000-250000',
    };
    expect(() => InterfaceUpdateSchema.parse(overlappingUpdate)).toThrow();
  });

  test('ClientUpdateSchema and UserConfigUpdateSchema validate Jmin <= Jmax', () => {
    const validClientUpdate = {
      name: 'client1',
      enabled: true,
      expiresAt: null,
      ipv4Address: '10.8.0.2',
      ipv6Address: 'fdcc:ad94:bacf:61a3::2',
      preUp: '',
      postUp: '',
      preDown: '',
      postDown: '',
      allowedIps: ['0.0.0.0/0'],
      serverAllowedIps: [],
      firewallIps: null,
      mtu: 1420,
      jC: 7,
      jMin: 20,
      jMax: 500,
      i1: null,
      i2: null,
      i3: null,
      i4: null,
      i5: null,
      persistentKeepalive: 25,
      serverEndpoint: null,
      dns: null,
    };

    expect(ClientUpdateSchema.parse(validClientUpdate)).toBeDefined();

    const invalidClientUpdate = {
      ...validClientUpdate,
      jMin: 600,
      jMax: 500,
    };
    expect(() => ClientUpdateSchema.parse(invalidClientUpdate)).toThrow();

    const validUserConfig = {
      port: 51820,
      defaultMtu: 1420,
      defaultPersistentKeepalive: 25,
      defaultDns: ['1.1.1.1'],
      defaultAllowedIps: ['0.0.0.0/0'],
      defaultJC: 7,
      defaultJMin: 10,
      defaultJMax: 1000,
      defaultI1: null,
      defaultI2: null,
      defaultI3: null,
      defaultI4: null,
      defaultI5: null,
      host: 'vpn.example.com',
    };

    expect(UserConfigUpdateSchema.parse(validUserConfig)).toBeDefined();

    const invalidUserConfig = {
      ...validUserConfig,
      defaultJMin: 1200,
      defaultJMax: 1000,
    };
    expect(() => UserConfigUpdateSchema.parse(invalidUserConfig)).toThrow();
  });

  test('ISchema validates CPS format and null conversion', () => {
    expect(ISchema.parse('<b 0x01020304><t>')).toBe('<b 0x01020304><t>');
    expect(ISchema.parse('<r 32>')).toBe('<r 32>');
    expect(ISchema.parse('<b 0x00><r 64><t>')).toBe('<b 0x00><r 64><t>');
    expect(ISchema.parse(null)).toBeNull();
    expect(ISchema.parse('')).toBeNull();
    expect(ISchema.parse('   ')).toBeNull();

    expect(() => ISchema.parse('constructor')).toThrow();
    expect(() => ISchema.parse('plain invalid text without tags')).toThrow();
  });

  test('Jc, Jmin, Jmax, and S schemas validate limits and reject negative numbers', () => {
    expect(JcSchema.parse(7)).toBe(7);
    expect(JcSchema.parse(null)).toBeNull();
    expect(() => JcSchema.parse(0)).toThrow(); // min 1
    expect(() => JcSchema.parse(200)).toThrow(); // max 128
    expect(() => JcSchema.parse(-5)).toThrow();

    expect(JminSchema.parse(10)).toBe(10);
    expect(JminSchema.parse(0)).toBe(0);
    expect(() => JminSchema.parse(-1)).toThrow();

    expect(JmaxSchema.parse(1000)).toBe(1000);
    expect(JmaxSchema.parse(0)).toBe(0);
    expect(() => JmaxSchema.parse(-1)).toThrow();

    expect(SSchema.parse(128)).toBe(128);
    expect(SSchema.parse(0)).toBe(0);
    expect(() => SSchema.parse(-10)).toThrow();
    expect(() => SSchema.parse(2000)).toThrow(); // max 1132
  });

  test('Client creation correctly inherits obfuscation parameters from clientInterface if userConfig defaults are null', () => {
    const activeInterface: InterfaceType = {
      ...baseInterface,
      jC: 5,
      jMin: 40,
      jMax: 200,
      i1: '<b 0xaabbccdd><t>',
      i2: '<r 16>',
      i3: null,
      i4: null,
      i5: '<b 0x11223344>',
      mtu: 1360,
    };

    const emptyUserConfig: UserConfigType = {
      ...baseUserConfig,
      defaultJC: null,
      defaultJMin: null,
      defaultJMax: null,
      defaultI1: null,
      defaultI2: null,
      defaultI3: null,
      defaultI4: null,
      defaultI5: null,
      defaultMtu: 1360,
    };

    const resolvedJc = emptyUserConfig.defaultJC ?? activeInterface.jC;
    const resolvedJmin = emptyUserConfig.defaultJMin ?? activeInterface.jMin;
    const resolvedJmax = emptyUserConfig.defaultJMax ?? activeInterface.jMax;
    const resolvedI1 = emptyUserConfig.defaultI1 ?? activeInterface.i1;
    const resolvedI2 = emptyUserConfig.defaultI2 ?? activeInterface.i2;
    const resolvedI5 = emptyUserConfig.defaultI5 ?? activeInterface.i5;

    expect(resolvedJc).toBe(5);
    expect(resolvedJmin).toBe(40);
    expect(resolvedJmax).toBe(200);
    expect(resolvedI1).toBe('<b 0xaabbccdd><t>');
    expect(resolvedI2).toBe('<r 16>');
    expect(resolvedI5).toBe('<b 0x11223344>');

    const createdClient: ClientType = {
      ...baseClient,
      jC: resolvedJc,
      jMin: resolvedJmin,
      jMax: resolvedJmax,
      i1: resolvedI1,
      i2: resolvedI2,
      i5: resolvedI5,
    };

    const config = wg.generateClientConfig(
      activeInterface,
      emptyUserConfig,
      createdClient,
      { enableIpv6: true }
    );

    expect(config).toContain('Jc = 5');
    expect(config).toContain('Jmin = 40');
    expect(config).toContain('Jmax = 200');
    expect(config).toContain('I1 = <b 0xaabbccdd><t>');
    expect(config).toContain('I2 = <r 16>');
    expect(config).toContain('I5 = <b 0x11223344>');
  });
});

