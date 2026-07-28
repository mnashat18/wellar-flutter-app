import { OAuth2Client, TokenPayload } from 'google-auth-library';
import { defineEndpoint } from '@directus/extensions-sdk';

type JsonMap = Record<string, unknown>;

type ExchangeBody = {
  idToken?: string;
  platform?: string;
};

type MemberIdentityBody = {
  business_profile?: string;
  member_ids?: unknown;
};

type DirectusUser = {
  id: string;
  email: string;
  first_name?: string | null;
  last_name?: string | null;
  role?: string | null;
};

type SessionResult = {
  access_token: string;
  refresh_token: string;
  expires: number;
};

type MembershipRecord = {
  id: string;
  status?: string | null;
  member_role?: string | null;
  department?: string | { id?: string | null } | null;
  business_profile?: string | { id?: string | null } | null;
  user?: string | { id?: string | null } | null;
};

const ERROR = {
  GOOGLE_TOKEN_MISSING: 'GOOGLE_TOKEN_MISSING',
  GOOGLE_TOKEN_INVALID: 'GOOGLE_TOKEN_INVALID',
  GOOGLE_EMAIL_MISSING: 'GOOGLE_EMAIL_MISSING',
  GOOGLE_EMAIL_NOT_VERIFIED: 'GOOGLE_EMAIL_NOT_VERIFIED',
  GOOGLE_ACCOUNT_NOT_ALLOWED: 'GOOGLE_ACCOUNT_NOT_ALLOWED',
  DIRECTUS_SESSION_CREATE_FAILED: 'DIRECTUS_SESSION_CREATE_FAILED',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
} as const;

function isTruthy(v: string | undefined): boolean {
  if (!v) return false;
  const n = v.trim().toLowerCase();
  return n === '1' || n === 'true' || n === 'yes' || n === 'on';
}

function splitCsv(v: string | undefined): string[] {
  if (!v) return [];
  return v
    .split(',')
    .map((x) => x.trim())
    .filter((x) => x.length > 0);
}

function lower(v: unknown): string {
  return String(v ?? '').trim().toLowerCase();
}

function jsonError(res: any, status: number, error: string, details?: string) {
  const payload: JsonMap = { error };
  if (details && process.env.NODE_ENV !== 'production') {
    payload.details = details;
  }
  res.status(status).json(payload);
}

function membershipRoleRank(role: string): number {
  const normalized = lower(role);
  if (normalized === 'owner') return 4;
  if (normalized === 'hr' || normalized === 'admin') return 3;
  if (normalized === 'manager' || normalized === 'manger') return 2;
  if (normalized === 'employee' || normalized === 'member' || normalized === 'user') return 1;
  return 0;
}

function relationId(value: unknown): string {
  if (!value) return '';
  if (typeof value === 'string') return value.trim();
  if (typeof value === 'object' && value && 'id' in value) {
    const id = (value as { id?: unknown }).id;
    return String(id ?? '').trim();
  }
  return String(value).trim();
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => String(item ?? '').trim())
    .filter((item) => item.length > 0);
}

async function verifyGoogleIdToken(
  idToken: string,
  allowedClientIds: string[],
): Promise<TokenPayload> {
  const verifier = new OAuth2Client();
  const ticket = await verifier.verifyIdToken({
    idToken,
    audience: allowedClientIds,
  });
  const payload = ticket.getPayload();
  if (!payload) {
    throw new Error('Google payload missing after verification.');
  }
  return payload;
}

async function getOrCreateDirectusUser({
  services,
  schema,
  database,
  email,
  firstName,
  lastName,
  allowCreate,
  defaultRoleId,
}: {
  services: any;
  schema: any;
  database: any;
  email: string;
  firstName: string;
  lastName: string;
  allowCreate: boolean;
  defaultRoleId?: string;
}): Promise<DirectusUser> {
  const accountability = { admin: true };
  const usersService = new services.ItemsService('directus_users', {
    schema,
    accountability,
    knex: database,
  });

  const found = (await usersService.readByQuery({
    limit: 1,
    fields: ['id', 'email', 'first_name', 'last_name', 'role'],
    filter: { email: { _eq: email } },
  })) as DirectusUser[];

  if (Array.isArray(found) && found.length > 0) {
    return found[0];
  }

  if (!allowCreate) {
    throw new Error(ERROR.GOOGLE_ACCOUNT_NOT_ALLOWED);
  }

  const createPayload: JsonMap = {
    email,
    first_name: firstName || null,
    last_name: lastName || null,
    status: 'active',
  };

  if (defaultRoleId && defaultRoleId.trim().length > 0) {
    createPayload.role = defaultRoleId.trim();
  }

  const createdId = (await usersService.createOne(createPayload)) as string;
  const created = (await usersService.readOne(createdId, {
    fields: ['id', 'email', 'first_name', 'last_name', 'role'],
  })) as DirectusUser;

  return created;
}

async function createDirectusSessionForUser({
  services,
  schema,
  database,
  user,
  req,
}: {
  services: any;
  schema: any;
  database: any;
  user: DirectusUser;
  req: any;
}): Promise<SessionResult> {
  const authService = new services.AuthenticationService({
    schema,
    accountability: { admin: true },
    knex: database,
  });

  const ip = req.ip ?? req.headers['x-forwarded-for'] ?? null;
  const userAgent = req.headers['user-agent'] ?? null;

  const candidates: Array<() => Promise<unknown>> = [
    async () => {
      if (typeof authService.createSession === 'function' &&
          typeof authService.createAccessToken === 'function' &&
          typeof authService.createRefreshToken === 'function') {
        const session = await authService.createSession(user.id, {
          ip,
          userAgent,
          origin: 'google-mobile-exchange',
        });
        const access = await authService.createAccessToken(session, user);
        const refresh = await authService.createRefreshToken(session, user);
        return {
          access_token: String(access),
          refresh_token: String(refresh),
          expires: 900000,
        } satisfies SessionResult;
      }
      return null;
    },
    async () => {
      if (typeof authService.createTokenPair === 'function') {
        const pair = await authService.createTokenPair({
          user: user.id,
          ip,
          userAgent,
          provider: 'google-mobile-exchange',
        });
        if (!pair) return null;
        return {
          access_token: String((pair as any).access_token ?? ''),
          refresh_token: String((pair as any).refresh_token ?? ''),
          expires: Number((pair as any).expires ?? 900000),
        } satisfies SessionResult;
      }
      return null;
    },
  ];

  for (const run of candidates) {
    const out = await run();
    if (!out) continue;
    const session = out as SessionResult;
    if (session.access_token && session.refresh_token) {
      return session;
    }
  }

  throw new Error(ERROR.DIRECTUS_SESSION_CREATE_FAILED);
}

export default defineEndpoint((router: any, context: any) => {
  const { services, getSchema, database, logger } = context;

  router.post('/member-identities', async (req: any, res: any) => {
    const accountability = req.accountability;
    const callerUserId = String(accountability?.user ?? '').trim();
    if (!callerUserId) {
      return jsonError(res, 401, 'UNAUTHENTICATED');
    }

    const body = (req.body ?? {}) as MemberIdentityBody;
    const businessProfileId = String(body.business_profile ?? '').trim();
    const requestedMemberIds = asStringArray(body.member_ids).slice(0, 500);
    if (!businessProfileId) {
      return jsonError(res, 400, 'BUSINESS_PROFILE_REQUIRED');
    }

    try {
      const schema = await getSchema();
      const scopedMembersService = new services.ItemsService('business_profile_members', {
        schema,
        accountability,
        knex: database,
      });
      const adminMembersService = new services.ItemsService('business_profile_members', {
        schema,
        accountability: { admin: true },
        knex: database,
      });
      const adminUsersService = new services.ItemsService('directus_users', {
        schema,
        accountability: { admin: true },
        knex: database,
      });

      const callerMemberships = (await scopedMembersService.readByQuery({
        limit: 50,
        fields: ['id', 'member_role', 'status', 'department', 'business_profile', 'user'],
        filter: {
          business_profile: { _eq: businessProfileId },
          user: { _eq: callerUserId },
          status: { _eq: 'active' },
        },
      })) as MembershipRecord[];

      if (!Array.isArray(callerMemberships) || callerMemberships.length === 0) {
        return jsonError(res, 403, 'MEMBERSHIP_SCOPE_UNAVAILABLE');
      }

      const callerMembership = callerMemberships
        .slice()
        .sort(
          (a, b) => membershipRoleRank(String(b.member_role ?? '')) - membershipRoleRank(String(a.member_role ?? '')),
        )[0];

      const callerRole = lower(callerMembership.member_role);
      const callerDepartmentId = relationId(callerMembership.department);
      const isOwnerOrHr = callerRole === 'owner' || callerRole === 'hr' || callerRole === 'admin';
      const isManager = callerRole === 'manager' || callerRole === 'manger';

      const targetFilter: Record<string, unknown> = {
        business_profile: { _eq: businessProfileId },
        status: { _eq: 'active' },
      };
      if (requestedMemberIds.length > 0) {
        targetFilter.id = { _in: requestedMemberIds };
      }
      if (isManager) {
        if (!callerDepartmentId) {
          targetFilter.id = { _eq: callerMembership.id };
        } else {
          targetFilter.department = { _eq: callerDepartmentId };
        }
      } else if (!isOwnerOrHr) {
        targetFilter.id = { _eq: callerMembership.id };
      }

      const visibleMembers = (await adminMembersService.readByQuery({
        limit: requestedMemberIds.length > 0 ? requestedMemberIds.length : 500,
        fields: ['id', 'user'],
        filter: targetFilter,
      })) as MembershipRecord[];

      const userIds = visibleMembers
        .map((member) => relationId(member.user))
        .filter((id) => id.length > 0);

      const users = userIds.length === 0
        ? []
        : ((await adminUsersService.readByQuery({
            limit: userIds.length,
            fields: ['id', 'email', 'first_name', 'last_name'],
            filter: { id: { _in: userIds } },
          })) as DirectusUser[]);

      const usersById = new Map<string, DirectusUser>();
      for (const user of users) {
        const id = String(user.id ?? '').trim();
        if (!id) continue;
        usersById.set(id, user);
      }

      const payload = visibleMembers.map((member) => {
        const memberId = String(member.id ?? '').trim();
        const userId = relationId(member.user);
        const user = usersById.get(userId);
        return {
          id: memberId,
          user: user
            ? {
                id: user.id,
                email: user.email,
                first_name: user.first_name ?? null,
                last_name: user.last_name ?? null,
              }
            : null,
        };
      });

      return res.json({ data: payload });
    } catch (error) {
      logger?.error?.('member-identities endpoint failed', error);
      return jsonError(res, 500, 'MEMBER_IDENTITY_LOOKUP_FAILED');
    }
  });

  router.post('/', async (req: any, res: any) => {
    try {
      const body = (req.body ?? {}) as ExchangeBody;
      const idToken = String(body.idToken ?? '').trim();

      if (!idToken) {
        return jsonError(res, 400, ERROR.GOOGLE_TOKEN_MISSING);
      }

      const allowedClientIds = splitCsv(process.env.GOOGLE_MOBILE_ALLOWED_CLIENT_IDS);
      if (allowedClientIds.length === 0) {
        return jsonError(res, 500, ERROR.INTERNAL_ERROR, 'GOOGLE_MOBILE_ALLOWED_CLIENT_IDS is empty');
      }

      let payload: TokenPayload;
      try {
        payload = await verifyGoogleIdToken(idToken, allowedClientIds);
      } catch {
        return jsonError(res, 401, ERROR.GOOGLE_TOKEN_INVALID);
      }

      const email = lower(payload.email);
      if (!email) {
        return jsonError(res, 400, ERROR.GOOGLE_EMAIL_MISSING);
      }

      const emailVerified = payload.email_verified === true || String(payload.email_verified) === 'true';
      if (!emailVerified) {
        return jsonError(res, 403, ERROR.GOOGLE_EMAIL_NOT_VERIFIED);
      }

      const schema = await getSchema();
      const allowCreate = isTruthy(process.env.GOOGLE_MOBILE_ALLOW_USER_CREATE);
      const defaultRoleId = process.env.GOOGLE_MOBILE_DEFAULT_ROLE_ID;

      const user = await getOrCreateDirectusUser({
        services,
        schema,
        database,
        email,
        firstName: String(payload.given_name ?? ''),
        lastName: String(payload.family_name ?? ''),
        allowCreate,
        defaultRoleId,
      });

      const session = await createDirectusSessionForUser({
        services,
        schema,
        database,
        user,
        req,
      });

      return res.status(200).json({
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        expires: session.expires,
        user: {
          id: user.id,
          email: user.email,
          first_name: user.first_name ?? null,
          last_name: user.last_name ?? null,
        },
      });
    } catch (error: any) {
      const message = String(error?.message ?? '');
      if (message === ERROR.GOOGLE_ACCOUNT_NOT_ALLOWED) {
        return jsonError(res, 403, ERROR.GOOGLE_ACCOUNT_NOT_ALLOWED);
      }
      if (message === ERROR.DIRECTUS_SESSION_CREATE_FAILED) {
        return jsonError(res, 500, ERROR.DIRECTUS_SESSION_CREATE_FAILED);
      }
      logger?.error?.('[google-mobile-exchange] failed');
      return jsonError(res, 500, ERROR.INTERNAL_ERROR);
    }
  });
});
