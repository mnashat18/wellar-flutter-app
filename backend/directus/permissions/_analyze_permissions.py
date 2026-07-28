#!/usr/bin/env python3
"""
Batch 0C Verification: Full local JSON parsing of Directus permissions exports.
Read-only. Produces exact evidence report.
"""

import json
import os
import sys

BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(BASE, "..", "..", ".."))

def load_json(path):
    full = os.path.join(ROOT, path) if not os.path.isabs(path) else path
    try:
        with open(full, 'r', encoding='utf-8-sig') as f:
            return json.load(f)
    except Exception as e:
        print(f"  FAILED to parse {full}: {e}")
        return None

def resolve_policy_name(policy_id, policies_data):
    """Resolve policy ID to policy name."""
    if not policies_data:
        return policy_id
    for p in policies_data:
        if p.get('id') == policy_id:
            return p.get('name', policy_id)
    return f"{policy_id} (unresolved)"

def resolve_role_from_policy(policy_id, roles_data):
    """Find role name(s) that use a given policy."""
    if not roles_data:
        return []
    roles = []
    for r in roles_data:
        for pol_link in r.get('policies', []):
            if pol_link.get('policy') == policy_id:
                roles.append(r.get('name', 'unknown'))
    return roles if roles else []

TARGET_COLLECTIONS = [
    "business_profiles", "business_profile_members", "departments",
    "request_invites", "scan_requests", "wellness_scans", "scan_media",
    "scan_results", "alerts", "notifications", "activity_events",
    "push_subscriptions", "consent_logs", "reports_exports",
    "employee_baselines", "scan_media_files", "shift_templates",
    "workspace_applications", "requests", "directus_files",
    "directus_folders", "directus_users"
]

def main():
    # ===========================
    # A. Parse all source files
    # ===========================
    files_to_check = [
        "backend/directus/permissions/directus-permissions.json",
        "backend/directus/permissions/directus-permissions.commit-safe.json",
        "backend/directus/permissions/directus-permissions.post-batch1.json",
        "backend/directus/permissions/directus-policies.json",
        "backend/directus/permissions/directus-roles.json",
    ]

    parsed = {}
    for f in files_to_check:
        full_path = os.path.join(ROOT, f)
        exists = os.path.exists(full_path)
        size = os.path.getsize(full_path) if exists else 0
        data = load_json(f)
        status = "OK" if data is not None else "FAILED"
        num_records = 0
        top_type = "N/A"
        if data is not None:
            d = data.get('data', data)
            if isinstance(d, list):
                num_records = len(d)
                top_type = f"list[{num_records}]"
            elif isinstance(d, dict):
                num_records = 1
                top_type = "dict"
        parsed[f] = {
            'exists': exists,
            'size': size,
            'status': status,
            'num_records': num_records,
            'data': data
        }
        has_secrets = False
        # Quick check for real secrets in non-commit-safe files
        if exists and status == "OK":
            with open(full_path, 'r', encoding='utf-8-sig') as fh:
                raw = fh.read()
                if 'trycloudflare' in raw.lower() or 'sendpushnotification' in raw.lower():
                    has_secrets = True
        parsed[f]['has_secrets'] = has_secrets

    print("=" * 80)
    print("A. FILES INSPECTED")
    print("=" * 80)
    for f, info in parsed.items():
        print(f"\n  File: {f}")
        print(f"    Exists: {info['exists']}")
        print(f"    Size: {info['size']:,} bytes")
        print(f"    Parse: {info['status']}")
        print(f"    Records: {info['num_records']:,}")
        print(f"    Has secrets/URLs: {info['has_secrets']}")

    perms = parsed.get("backend/directus/permissions/directus-permissions.json", {}).get('data', {}).get('data', [])
    perms_cs = parsed.get("backend/directus/permissions/directus-permissions.commit-safe.json", {}).get('data', {})
    perms_cs_data = perms_cs.get('data', []) if isinstance(perms_cs, dict) else perms_cs
    policies_data = parsed.get("backend/directus/permissions/directus-policies.json", {}).get('data', {}).get('data', [])
    roles_data = parsed.get("backend/directus/permissions/directus-roles.json", {}).get('data', {}).get('data', [])

    print("\n" + "=" * 80)
    print("B. PARSE RESULTS")
    print("=" * 80)

    # Use commit-safe first, fallback to raw
    perm_list = perms_cs_data if len(perms_cs_data) > 0 else perms

    if len(perm_list) > 0:
        print(f"\n  Using permissions file with {len(perm_list):,} total permission rows")
    else:
        print("\n  ERROR: No permission rows parsed from either file!")
        return

    # ===========================
    # C. Extract permissions by target collection
    # ===========================
    print("\n" + "=" * 80)
    print("C. EXACT PERMISSION ROWS BY TARGET COLLECTION")
    print("=" * 80)

    collection_perms = {}
    for col in TARGET_COLLECTIONS:
        collection_perms[col] = []

    for p in perm_list:
        col = p.get('collection', '')
        if col in TARGET_COLLECTIONS:
            collection_perms[col].append(p)

    zero_permission_colls = []
    unfiltered_rows = []
    wildcard_fields_rows = []
    public_rows = []
    ai_rows = []
    planbiz_rows = []

    # Build policy->name mapping
    policy_names = {}
    if policies_data:
        for pol in policies_data:
            policy_names[pol['id']] = pol['name']

    for col in TARGET_COLLECTIONS:
        rows = collection_perms[col]
        if len(rows) == 0:
            zero_permission_colls.append(col)
            print(f"\n  {col}: NO PERMISSIONS (0 rows)")
            continue

        print(f"\n  {col}: {len(rows)} permission row(s)")
        for p in rows:
            pol_id = p.get('policy', '')
            pol_name = policy_names.get(pol_id, pol_id)
            roles = resolve_role_from_policy(pol_id, roles_data)
            role_str = ", ".join(roles) if roles else "none"
            perms_filter = p.get('permissions')
            fields = p.get('fields')
            action = p.get('action')
            validation = p.get('validation')
            presets = p.get('presets')

            is_unfiltered = perms_filter is None
            is_wildcard = fields == "*" or fields == ["*"]

            print(f"    ID={p['id']} | Policy={pol_name} ({pol_id[:8]}...) | Roles=[{role_str}]")
            print(f"      Action={action} | Fields={fields}")
            print(f"      Filter={json.dumps(perms_filter)[:200] if perms_filter else 'null'}")
            if validation:
                print(f"      Validation=present")
            if presets:
                print(f"      Presets=present")

            if is_unfiltered:
                unfiltered_rows.append({
                    'id': p['id'], 'collection': col, 'action': action,
                    'policy': pol_name, 'roles': role_str
                })
            if is_wildcard:
                wildcard_fields_rows.append({
                    'id': p['id'], 'collection': col, 'action': action,
                    'policy': pol_name, 'roles': role_str
                })
            if pol_name == '$t:public_label':
                public_rows.append({
                    'id': p['id'], 'collection': col, 'action': action,
                    'filter': 'null' if is_unfiltered else 'present',
                    'fields': fields
                })
            if pol_name == 'AI Server Access':
                ai_rows.append({
                    'id': p['id'], 'collection': col, 'action': action,
                    'filter': 'null' if is_unfiltered else 'present',
                    'fields': fields
                })
            if pol_name == 'plan_business':
                planbiz_rows.append({
                    'id': p['id'], 'collection': col, 'action': action,
                    'filter': 'null' if is_unfiltered else 'present',
                    'fields': fields
                })

    # ===========================
    # D. Zero-permission target collections
    # ===========================
    print("\n" + "=" * 80)
    print("D. ZERO-PERMISSION TARGET COLLECTIONS")
    print("=" * 80)
    if zero_permission_colls:
        for c in zero_permission_colls:
            print(f"  ✅ CONFIRMED ZERO: {c}")
    else:
        print("  All target collections have at least 1 permission row")

    # ===========================
    # E. Confirmed unfiltered rows
    # ===========================
    print("\n" + "=" * 80)
    print("E. CONFIRMED BROAD/UNFILTERED ROWS (permissions filter = null)")
    print("=" * 80)
    if unfiltered_rows:
        for r in unfiltered_rows:
            print(f"  ID={r['id']:>4} | {r['collection']:<30s} | {r['action']:<8s} | Policy={r['policy']:<20s} | Roles=[{r['roles']}]")
    else:
        print("  No unfiltered permission rows found")

    # ===========================
    # F. Public policy rows
    # ===========================
    print("\n" + "=" * 80)
    print("F. CONFIRMED PUBLIC POLICY ROWS")
    print("=" * 80)
    if public_rows:
        for r in public_rows:
            print(f"  ID={r['id']:>4} | {r['collection']:<30s} | {r['action']:<8s} | Filter={r['filter']:<8s} | Fields={r['fields']}")
    else:
        print("  No Public policy permission rows found")

    # ===========================
    # G. AI Server Access rows
    # ===========================
    print("\n" + "=" * 80)
    print("G. CONFIRMED AI SERVER ACCESS PERMISSION ROWS")
    print("=" * 80)
    if ai_rows:
        for r in ai_rows:
            print(f"  ID={r['id']:>4} | {r['collection']:<30s} | {r['action']:<8s} | Filter={r['filter']:<8s} | Fields={r['fields']}")
    else:
        print("  No AI Server Access permission rows found")

    # ===========================
    # H. plan_business rows
    # ===========================
    print("\n" + "=" * 80)
    print("H. CONFIRMED plan_business PERMISSION ROWS")
    print("=" * 80)
    if planbiz_rows:
        for r in planbiz_rows:
            print(f"  ID={r['id']:>4} | {r['collection']:<30s} | {r['action']:<8s} | Filter={r['filter']:<8s} | Fields={r['fields']}")
    else:
        print("  No plan_business permission rows found")

    # ===========================
    # I. Specific findings
    # ===========================
    print("\n" + "=" * 80)
    print("I. SPECIFIC FINDINGS")
    print("=" * 80)

    # Finding 8: notifications and activity_events
    notif_data = collection_perms.get('notifications', [])
    actevt_data = collection_perms.get('activity_events', [])
    print(f"\n  8a. notifications permissions: {len(notif_data)} rows" + (" (ZERO)" if len(notif_data) == 0 else ""))
    for p in notif_data:
        print(f"      ID={p['id']} Action={p['action']} Policy={policy_names.get(p['policy'], p['policy'])}")
    print(f"  8b. activity_events permissions: {len(actevt_data)} rows" + (" (ZERO)" if len(actevt_data) == 0 else ""))
    for p in actevt_data:
        print(f"      ID={p['id']} Action={p['action']} Policy={policy_names.get(p['policy'], p['policy'])}")

    # Finding 9: scan_requests, wellness_scans, scan_results, scan_media, request_invites
    for c in ['scan_requests', 'wellness_scans', 'scan_results', 'scan_media', 'request_invites']:
        rows = collection_perms.get(c, [])
        print(f"\n  9. {c}: {len(rows)} rows" + (" (ZERO)" if len(rows) == 0 else ""))
        for p in rows:
            print(f"      ID={p['id']} Action={p['action']} Policy={policy_names.get(p['policy'], p['policy'])} Filter={'null' if p.get('permissions') is None else 'present'}")

    # Finding 10: public directus_files read
    pub_files = [r for r in public_rows if r['collection'] == 'directus_files']
    print(f"\n  10. Public directus_files read: {len(pub_files)} rows")
    for r in pub_files:
        print(f"      ID={r['id']} Action={r['action']} Filter={r['filter']} Fields={r['fields']}")

    # Finding 11: plan_business business_profile_members read unfiltered
    pb_bpm = [r for r in planbiz_rows if r['collection'] == 'business_profile_members']
    print(f"\n  11. plan_business business_profile_members: {len(pb_bpm)} rows")
    for r in pb_bpm:
        print(f"      ID={r['id']} Action={r['action']} Filter={r['filter']} Fields={r['fields']}")

    # Finding 12: AI Server business_profiles/business_profile_members/departments
    ai_bp = [r for r in ai_rows if r['collection'] == 'business_profiles']
    ai_bpm = [r for r in ai_rows if r['collection'] == 'business_profile_members']
    ai_dept = [r for r in ai_rows if r['collection'] == 'departments']
    print(f"\n  12a. AI Server business_profiles: {len(ai_bp)} rows")
    for r in ai_bp:
        print(f"      ID={r['id']} Action={r['action']} Filter={r['filter']} Fields={r['fields']}")
    print(f"  12b. AI Server business_profile_members: {len(ai_bpm)} rows")
    for r in ai_bpm:
        print(f"      ID={r['id']} Action={r['action']} Filter={r['filter']} Fields={r['fields']}")
    print(f"  12c. AI Server departments: {len(ai_dept)} rows")
    for r in ai_dept:
        print(f"      ID={r['id']} Action={r['action']} Filter={r['filter']} Fields={r['fields']}")

    # ===========================
    # J. Summary
    # ===========================
    print("\n" + "=" * 80)
    print("J. SUMMARY STATISTICS")
    print("=" * 80)
    print(f"\n  Total permission rows in file: {len(perm_list):,}")
    print(f"  Target collections with permissions: {sum(1 for c in TARGET_COLLECTIONS if len(collection_perms.get(c, [])) > 0)}")
    print(f"  Target collections with ZERO permissions: {len(zero_permission_colls)}")
    print(f"  Unfiltered rows (null filter): {len(unfiltered_rows)}")
    print(f"  Wildcard fields rows (*): {len(wildcard_fields_rows)}")
    print(f"  Public policy rows: {len(public_rows)}")
    print(f"  AI Server Access rows: {len(ai_rows)}")
    print(f"  plan_business rows: {len(planbiz_rows)}")

if __name__ == '__main__':
    main()
