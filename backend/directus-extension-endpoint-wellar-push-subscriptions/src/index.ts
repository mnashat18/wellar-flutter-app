import crypto from 'node:crypto';

type JsonMap = Record<string, unknown>;

type SyncBody = {
  token?: unknown;
  device_id?: unknown;
  platform?: unknown;
  device_label?: unknown;
  app_version?: unknown;
  os_version?: unknown;
};

type RevokeBody = {
  device_id?: unknown;
};

type ActiveUserRow = {
  id: string;
  active_business_profile?: unknown;
};

type MembershipRow = {
  id: string;
  status?: string | null;
  business_profile?: unknown;
  user?: unknown;
};

type FailureStage =
  | 'validation'
  | 'user_context'
  | 'membership_context'
  | 'existing_token'
  | 'device_rows'
  | 'upsert';

const SYNC_ALLOWED_KEYS = new Set([
  'token',
  'device_id',
  'platform',
  'device_label',
  'app_version',
  'os_version',
]);

const REVOKE_ALLOWED_KEYS = new Set(['device_id']);

const MAX_LENGTHS = {
  token: 255,
  deviceId: 255,
  platform: 16,
  deviceLabel: 255,
  appVersion: 255,
  osVersion: 255,
};

class EndpointError extends Error {
  readonly status: number;
  readonly code: string;
  readonly stage: FailureStage;

  constructor(stage: FailureStage, status: number, code: string) {
    super(code);
    this.name = 'EndpointError';
    this.stage = stage;
    this.status = status;
    this.code = code;
  }
}

function fail(stage: FailureStage, status: number, code: string): never {
  throw new EndpointError(stage, status, code);
}

function jsonError(res: any, status: number, error: string, details?: string) {
  const payload: JsonMap = { error };
  if (details && process.env.NODE_ENV !== 'production') {
    payload.details = details;
  }
  res.status(status).json(payload);
}

function lower(value: unknown): string {
  return String(value ?? '').trim().toLowerCase();
}

function relationId(value: unknown): string {
  if (!value) return '';
  if (typeof value === 'string') return value.trim();
  if (typeof value === 'object' && 'id' in (value as Record<string, unknown>)) {
    return String((value as Record<string, unknown>).id ?? '').trim();
  }
  return String(value).trim();
}

function asSafeString(value: unknown, maxLength: number): string {
  if (value === null || value === undefined) return '';
  const text = String(value).trim();
  if (!text) return '';
  return text.length > maxLength ? text.slice(0, maxLength) : text;
}

function validatePlatform(value: unknown): 'android' | 'ios' | null {
  const normalized = lower(value);
  if (normalized === 'android') return 'android';
  if (normalized === 'ios') return 'ios';
  return null;
}

function hasOnlyAllowedKeys(
  body: JsonMap,
  allowedKeys: Set<string>,
): boolean {
  const keys = Object.keys(body);
  for (const key of keys) {
    if (!allowedKeys.has(key)) {
      return false;
    }
  }
  return true;
}

function lockKey(parts: string[]): string {
  const hash = crypto.createHash('sha256').update(parts.join('|')).digest();
  return hash.readBigInt64BE(0).toString();
}

async function resolveWorkspaceContext(context: any, userId: string) {
  const { services, getSchema, database } = context;
  let schema: any;
  try {
    schema = await getSchema();
  } catch {
    fail('user_context', 500, 'SCHEMA_UNAVAILABLE');
  }
  const usersService = new services.ItemsService('directus_users', {
    schema,
    accountability: { admin: true },
    knex: database,
  });
  const membersService = new services.ItemsService('business_profile_members', {
    schema,
    accountability: { admin: true },
    knex: database,
  });

  let user: ActiveUserRow;
  try {
    user = (await usersService.readOne(userId, {
      fields: ['id', 'active_business_profile'],
    })) as ActiveUserRow;
  } catch {
    fail('user_context', 404, 'USER_CONTEXT_NOT_FOUND');
  }

  const activeBusinessProfileId = relationId(user?.active_business_profile);
  if (!activeBusinessProfileId) {
    fail('user_context', 403, 'NO_ACTIVE_WORKSPACE');
  }

  let memberships: MembershipRow[];
  try {
    memberships = (await membersService.readByQuery({
      limit: 1,
      fields: ['id', 'status', 'business_profile', 'user'],
      filter: {
        user: { _eq: userId },
        business_profile: { _eq: activeBusinessProfileId },
        status: { _eq: 'active' },
      },
    })) as MembershipRow[];
  } catch {
    fail('membership_context', 403, 'WORKSPACE_SCOPE_UNAVAILABLE');
  }

  if (!Array.isArray(memberships) || memberships.length === 0) {
    fail('membership_context', 403, 'WORKSPACE_SCOPE_UNAVAILABLE');
  }

  return {
    activeBusinessProfileId,
  };
}

function parseSyncBody(body: JsonMap) {
  if (!hasOnlyAllowedKeys(body, SYNC_ALLOWED_KEYS)) {
    fail('validation', 400, 'UNSUPPORTED_FIELD');
  }

  const token = asSafeString(body.token, MAX_LENGTHS.token);
  const deviceId = asSafeString(body.device_id, MAX_LENGTHS.deviceId);
  const platform = validatePlatform(body.platform);
  const deviceLabel = asSafeString(body.device_label, MAX_LENGTHS.deviceLabel);
  const appVersion = asSafeString(body.app_version, MAX_LENGTHS.appVersion);
  const osVersion = asSafeString(body.os_version, MAX_LENGTHS.osVersion);

  if (!token) {
    fail('validation', 400, 'TOKEN_REQUIRED');
  }
  if (!deviceId) {
    fail('validation', 400, 'DEVICE_ID_REQUIRED');
  }
  if (!platform) {
    fail('validation', 400, 'PLATFORM_INVALID');
  }

  return {
    token,
    deviceId,
    platform,
    deviceLabel: deviceLabel || null,
    appVersion: appVersion || null,
    osVersion: osVersion || null,
  };
}

function parseRevokeBody(body: JsonMap) {
  if (!hasOnlyAllowedKeys(body, REVOKE_ALLOWED_KEYS)) {
    fail('validation', 400, 'UNSUPPORTED_FIELD');
  }

  const deviceId = asSafeString(body.device_id, MAX_LENGTHS.deviceId);
  if (!deviceId) {
    fail('validation', 400, 'DEVICE_ID_REQUIRED');
  }

  return { deviceId };
}

async function upsertSubscription(
  trx: any,
  {
    userId,
    businessProfileId,
    payload,
  }: {
    userId: string;
    businessProfileId: string;
    payload: ReturnType<typeof parseSyncBody>;
  },
) {
  const now = new Date().toISOString();
  const targetRows = (await trx('push_subscriptions')
    .select(['id'])
    .where({
      user: userId,
      business_profile: businessProfileId,
      device_id: payload.deviceId,
    })
    .orderBy('is_active', 'desc')
    .orderBy('last_seen_at', 'desc')
    .orderBy('id', 'desc')) as Array<{ id: string }>;

  const targetRowId = targetRows.length > 0 ? String(targetRows[0].id ?? '').trim() : '';
  const updateData: JsonMap = {
    token: payload.token,
    user: userId,
    business_profile: businessProfileId,
    device_id: payload.deviceId,
    platform: payload.platform,
    is_active: true,
    last_seen_at: now,
  };

  if (payload.deviceLabel) {
    updateData.device_label = payload.deviceLabel;
  }
  if (payload.appVersion) {
    updateData.app_version = payload.appVersion;
  }
  if (payload.osVersion) {
    updateData.os_version = payload.osVersion;
  }

  let savedId = targetRowId;
  let operation: 'created' | 'updated' = 'updated';
  if (savedId) {
    await trx('push_subscriptions').where({ id: savedId }).update(updateData);
  } else {
    operation = 'created';
    const inserted = await trx('push_subscriptions')
      .insert({
        id: crypto.randomUUID(),
        ...updateData,
      })
      .returning(['id']);
    const first = Array.isArray(inserted) ? inserted[0] : inserted;
    savedId = String((first?.id ?? first ?? '')).trim();
  }

  let duplicateRowsDeactivated = 0;
  if (savedId) {
    duplicateRowsDeactivated = await trx('push_subscriptions')
      .where({
        user: userId,
        business_profile: businessProfileId,
        device_id: payload.deviceId,
      })
      .andWhereNot('id', savedId)
      .update({
        is_active: false,
        last_seen_at: now,
      });
  }

  return {
    operation,
    duplicateRowsDeactivated:
      typeof duplicateRowsDeactivated === 'number'
          ? duplicateRowsDeactivated
          : Number(duplicateRowsDeactivated ?? 0) || 0,
  };
}

async function revokeSubscription(
  trx: any,
  {
    userId,
    businessProfileId,
    deviceId,
  }: {
    userId: string;
    businessProfileId: string;
    deviceId: string;
  },
) {
  const now = new Date().toISOString();
  await trx('push_subscriptions')
    .where({
      user: userId,
      business_profile: businessProfileId,
      device_id: deviceId,
    })
    .update({
      is_active: false,
      last_seen_at: now,
    });
}

function databaseErrorCode(error: any): string | null {
  const code = error?.code ?? error?.originalError?.code ?? error?.cause?.code;
  return typeof code === 'string' && code.trim().length > 0 ? code.trim() : null;
}

function errorClass(error: any): string {
  return error?.constructor?.name || error?.name || typeof error;
}

function mapUnexpectedDatabaseFailure(error: any): EndpointError | null {
  const code = databaseErrorCode(error);
  if (code === '23505') {
    return new EndpointError('upsert', 409, 'PUSH_SUBSCRIPTION_CONFLICT');
  }
  if (code === '23503') {
    return new EndpointError('upsert', 409, 'PUSH_SUBSCRIPTION_REFERENCE_INVALID');
  }
  if (code === '23502') {
    return new EndpointError('upsert', 500, 'PUSH_SUBSCRIPTION_REQUIRED_FIELD_MISSING');
  }
  if (code === '22001') {
    return new EndpointError('upsert', 400, 'PUSH_SUBSCRIPTION_FIELD_TOO_LONG');
  }
  return null;
}

function logUnexpectedFailure(context: any, stage: FailureStage, error: any) {
  context?.logger?.error?.({
    event: 'wellar_push_sync_failed',
    stage,
    error_class: errorClass(error),
    error_code:
      error instanceof EndpointError
        ? error.code
        : typeof error?.code === 'string'
          ? error.code
          : 'UNEXPECTED_ERROR',
    database_error_code: databaseErrorCode(error),
  });
}

function handleEndpointError(
  context: any,
  res: any,
  error: any,
  fallbackStage: FailureStage,
  fallbackCode: string,
) {
  const mapped = error instanceof EndpointError ? error : mapUnexpectedDatabaseFailure(error);
  if (mapped instanceof EndpointError) {
    if (mapped.status >= 500) {
      logUnexpectedFailure(context, mapped.stage, error);
    }
    return jsonError(res, mapped.status, mapped.code);
  }
  logUnexpectedFailure(context, fallbackStage, error);
  return jsonError(res, 500, fallbackCode);
}

export default {
  id: 'wellar-push-subscriptions',
  handler: (router: any, context: any) => {
    router.post('/sync', async (req: any, res: any) => {
      const userId = String(req.accountability?.user ?? '').trim();
      if (!userId) {
        return jsonError(res, 401, 'UNAUTHENTICATED');
      }

      try {
        const body = (req.body ?? {}) as JsonMap;
        const payload = parseSyncBody(body);
        const workspace = await resolveWorkspaceContext(context, userId);
        const { database } = context;
        const lockId = lockKey([userId, workspace.activeBusinessProfileId, payload.deviceId]);

        const result = await database.transaction(async (trx: any) => {
          await trx.raw('select pg_advisory_xact_lock(?)', [lockId]);
          return await upsertSubscription(trx, {
            userId,
            businessProfileId: workspace.activeBusinessProfileId,
            payload,
          });
        });

        context?.logger?.info?.({
          event: 'wellar_push_sync_succeeded',
          operation: result.operation,
          duplicate_rows_deactivated: result.duplicateRowsDeactivated,
        });

        return res.status(200).json({ ok: true });
      } catch (error: any) {
        return handleEndpointError(
          context,
          res,
          error,
          'upsert',
          'PUSH_SYNC_FAILED',
        );
      }
    });

    router.post('/revoke', async (req: any, res: any) => {
      const userId = String(req.accountability?.user ?? '').trim();
      if (!userId) {
        return jsonError(res, 401, 'UNAUTHENTICATED');
      }

      try {
        const body = (req.body ?? {}) as JsonMap;
        const { deviceId } = parseRevokeBody(body);
        const workspace = await resolveWorkspaceContext(context, userId);
        const { database } = context;
        const lockId = lockKey([userId, workspace.activeBusinessProfileId, deviceId]);

        await database.transaction(async (trx: any) => {
          await trx.raw('select pg_advisory_xact_lock(?)', [lockId]);
          await revokeSubscription(trx, {
            userId,
            businessProfileId: workspace.activeBusinessProfileId,
            deviceId,
          });
        });

        return res.status(200).json({ ok: true });
      } catch (error: any) {
        return handleEndpointError(
          context,
          res,
          error,
          'upsert',
          'PUSH_REVOKE_FAILED',
        );
      }
    });
  },
};
