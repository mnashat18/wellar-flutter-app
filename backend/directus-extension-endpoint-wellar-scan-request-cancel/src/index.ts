import { defineEndpoint } from '@directus/extensions-sdk';

type JsonMap = Record<string, unknown>;

type CancelHttpErrorShape = {
  status: number;
  code: string;
  message: string;
};

class CancelHttpError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(shape: CancelHttpErrorShape) {
    super(shape.message);
    this.name = 'CancelHttpError';
    this.status = shape.status;
    this.code = shape.code;
  }
}

function jsonError(
  res: any,
  status: number,
  error: string,
  details?: string,
) {
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

function isTruthy(value: unknown): boolean {
  if (typeof value === 'boolean') return value;
  const normalized = String(value ?? '').trim().toLowerCase();
  return normalized === 'true' || normalized === '1' || normalized === 'yes';
}

export default defineEndpoint((router: any, context: any) => {
  const { services, getSchema, database, logger } = context;

  router.post('/scan-requests/:id/cancel', async (req: any, res: any) => {
    const accountability = req.accountability;
    const userId = String(accountability?.user ?? '').trim();
    const requestId = String(req.params?.id ?? '').trim();

    if (!userId) {
      return jsonError(res, 401, 'UNAUTHENTICATED');
    }

    if (!requestId) {
      return jsonError(res, 400, 'REQUEST_ID_REQUIRED');
    }

    try {
      const schema = await getSchema();
      const elevatedAccountability = {
        ...(accountability ?? {}),
        admin: true,
      };
      const usersService = new services.ItemsService('directus_users', {
        schema,
        accountability: elevatedAccountability,
        knex: database,
      });
      const membershipsService = new services.ItemsService(
        'business_profile_members',
        {
          schema,
          accountability: elevatedAccountability,
          knex: database,
        },
      );
      const requestsService = new services.ItemsService('scan_requests', {
        schema,
        accountability: elevatedAccountability,
        knex: database,
      });

      const currentUser = (await usersService.readOne(userId, {
        fields: ['id', 'active_business_profile'],
      })) as JsonMap;
      const activeBusinessProfileId = relationId(
        currentUser?.active_business_profile,
      );

      if (!activeBusinessProfileId) {
        return jsonError(res, 403, 'NO_ACTIVE_WORKSPACE');
      }

      const memberships = (await membershipsService.readByQuery({
        limit: 1,
        fields: ['id'],
        filter: {
          user: { _eq: userId },
          business_profile: { _eq: activeBusinessProfileId },
          status: { _eq: 'active' },
        },
      })) as Array<{ id?: string }>;

      if (!Array.isArray(memberships) || memberships.length === 0) {
        return jsonError(res, 403, 'WORKSPACE_SCOPE_UNAVAILABLE');
      }

      const result = await database.transaction(async (trx: any) => {
        const row = await trx('scan_requests')
          .select([
            'id',
            'status',
            'cancelled',
            'requested_by_user',
            'business_profile',
            'completed_scan',
            'completed_at',
          ])
          .where({ id: requestId })
          .forUpdate()
          .first();

        if (!row) {
          throw new CancelHttpError({
            status: 404,
            code: 'REQUEST_NOT_FOUND',
            message: 'Request not found.',
          });
        }

        const businessProfileId = relationId(row.business_profile);
        if (businessProfileId !== activeBusinessProfileId) {
          throw new CancelHttpError({
            status: 404,
            code: 'REQUEST_NOT_FOUND',
            message: 'Request not found.',
          });
        }

        if (relationId(row.requested_by_user) !== userId) {
          throw new CancelHttpError({
            status: 403,
            code: 'REQUEST_NOT_OWNER',
            message: 'You can only cancel requests you sent.',
          });
        }

        const status = lower(row.status);
        const completedScanId = relationId(row.completed_scan);
        const alreadyCancelled = isTruthy(row.cancelled) || status === 'cancelled';
        const cancellableStatuses = new Set(['pending', 'sent']);

        if (
          alreadyCancelled ||
          completedScanId.length > 0 ||
          String(row.completed_at ?? '').trim().length > 0 ||
          !cancellableStatuses.has(status)
        ) {
          throw new CancelHttpError({
            status: 409,
            code: 'REQUEST_NOT_ELIGIBLE',
            message: 'This request can no longer be cancelled.',
          });
        }

        const now = new Date().toISOString();
        await requestsService.updateOne(requestId, {
          status: 'cancelled',
          cancelled: 'true',
          date_updated: now,
          user_updated: userId,
        });

        return requestsService.readOne(requestId, {
          fields: [
            'id',
            'status',
            'request_type',
            'business_profile',
            'requested_by_user',
            'requested_by_user.id',
            'requested_by_user.email',
            'requested_by_user.first_name',
            'requested_by_user.last_name',
            'target_member',
            'department',
            'due_at',
            'requested_at',
            'completed_scan',
            'completed_at',
            'cancelled',
          ],
        });
      });

      return res.status(200).json({ data: result });
    } catch (error: any) {
      if (error instanceof CancelHttpError) {
        return jsonError(res, error.status, error.code, error.message);
      }
      logger?.error?.('[scan-request-cancel] failed', error);
      return jsonError(res, 500, 'REQUEST_CANCEL_FAILED');
    }
  });
});
