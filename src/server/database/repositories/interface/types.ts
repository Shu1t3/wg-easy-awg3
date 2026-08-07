import type { InferSelectModel } from 'drizzle-orm';
import z from 'zod';
import isCidr from 'is-cidr';

import type { wgInterface } from './schema';

import {
  EnabledSchema,
  HSchema,
  ISchema,
  JcSchema,
  JmaxSchema,
  JminSchema,
  MtuSchema,
  PortSchema,
  RoutingTableSchema,
  SSchema,
  doRangesOverlap,
  parseHRange,
  safeStringRefine,
  schemaForType,
  t,
} from '#server/utils/types';

export type InterfaceType = InferSelectModel<typeof wgInterface>;

export type InterfaceCreateType = Omit<
  InterfaceType,
  'createdAt' | 'updatedAt'
>;

export type InterfaceUpdateType = Omit<
  InterfaceCreateType,
  'name' | 'createdAt' | 'updatedAt' | 'privateKey' | 'publicKey'
>;

const device = z
  .string({ message: t('zod.interface.device') })
  .min(1, t('zod.interface.device'))
  .pipe(safeStringRefine);

const cidr = z
  .string({ message: t('zod.interface.cidr') })
  .min(1, { message: t('zod.interface.cidr') })
  .refine((value) => isCidr(value), { message: t('zod.interface.cidrValid') })
  .pipe(safeStringRefine);

export const InterfaceUpdateSchema = schemaForType<InterfaceUpdateType>()(
  z
    .object({
      ipv4Cidr: cidr,
      ipv6Cidr: cidr,
      mtu: MtuSchema,
      routingTable: RoutingTableSchema,
      jC: JcSchema,
      jMin: JminSchema,
      jMax: JmaxSchema,
      s1: SSchema,
      s2: SSchema,
      s3: SSchema,
      s4: SSchema,
      h1: HSchema,
      h2: HSchema,
      h3: HSchema,
      h4: HSchema,
      i1: ISchema,
      i2: ISchema,
      i3: ISchema,
      i4: ISchema,
      i5: ISchema,
      port: PortSchema,
      device: device,
      enabled: EnabledSchema,
      firewallEnabled: EnabledSchema,
    })
    .refine(
      (data) => {
        const headers = [
          { name: 'h1', range: parseHRange(data.h1) },
          { name: 'h2', range: parseHRange(data.h2) },
          { name: 'h3', range: parseHRange(data.h3) },
          { name: 'h4', range: parseHRange(data.h4) },
        ].filter((h) => h.range !== null);

        for (let i = 0; i < headers.length; i++) {
          for (let j = i + 1; j < headers.length; j++) {
            if (doRangesOverlap(headers[i]!.range, headers[j]!.range)) {
              return false;
            }
          }
        }
        return true;
      },
      {
        message: t('zod.generic.validNumberRange'),
        path: ['h1'],
      }
    )
);

export type InterfaceCidrUpdateType = {
  ipv4Cidr: string;
  ipv6Cidr: string;
};

export const InterfaceCidrUpdateSchema =
  schemaForType<InterfaceCidrUpdateType>()(
    z.object({
      ipv4Cidr: cidr,
      ipv6Cidr: cidr,
    })
  );
