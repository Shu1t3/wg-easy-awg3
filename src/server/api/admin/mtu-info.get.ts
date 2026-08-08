import { getQuery } from 'h3';

import { definePermissionEventHandler } from '#server/utils/handler';
import { getMtuDiagnostic } from '#server/utils/mtu';

export default definePermissionEventHandler(
  'admin',
  'any',
  async ({ event }) => {
    const query = getQuery(event);
    const target =
      typeof query.target === 'string' && query.target.trim() !== ''
        ? query.target.trim()
        : undefined;

    const result = await getMtuDiagnostic(target);
    return result;
  }
);
