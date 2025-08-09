# Database Maintenance and Custom Triggers

This document outlines the custom database modifications, maintenance procedures, and lessons learned from schema evolution.

## Custom Database Objects

### Trigger Overview
Located in `yon-triggers/` directory:

#### `yon_auto_add_to_family.sql`
**Purpose**: Automatically categorize and organize uploaded assets
- **WhatsApp Detection**: Detects files matching pattern `^IMG-[0-9]{8}-WA[0-9]+\..*$`
- **Album Assignment**: Auto-adds to specific album with UUID `6ee340e1-7830-425f-9a29-7140aa8f737c`
- **Auto-archiving**: Sets visibility to 'archive' for organizational assets
- **Permission Check**: Validates asset owner matches album owner
- **Family Album**: Auto-adds non-WhatsApp assets to family album with permission validation

#### `yon_exclusive_archiving_albums.sql`
**Purpose**: Enforce exclusive membership in document/organization albums
- **Special Albums**: Maintains array of 20+ album UUIDs for categories:
  - Receipts, tax documents, medical records
  - Real estate properties, repair documentation
  - Vehicle records, insurance documents
- **Exclusive Logic**: When asset added to special album, removes from all other albums
- **Auto-archiving**: Archives assets in special albums to reduce main timeline clutter

### Database Schema Dependencies

#### Current Schema (v1.137.3+)
```sql
-- Core tables (singular naming)
album (id, ownerId, albumName, ...)
asset (id, ownerId, originalFileName, visibility, ...)
album_asset (albumId, assetId)
album_user (albumId, userId, role)
```

#### Historical Schema (≤v1.132.3)
```sql  
-- Old tables (plural naming) 
albums (id, ownerId, ...)
assets (id, ownerId, ...)
albums_assets_assets (albumsId, assetsId)
albums_shared_users_users (albumsId, usersId, role)
```

## Schema Migration Impact

### v1.132.3 → v1.137.3 Breaking Changes
**Migration**: `1752267649968-StandardizeNames.ts` (commit `c699df002`)

**Table Renames**:
| Old Name | New Name |
|----------|----------|
| `albums` | `album` |  
| `assets` | `asset` |
| `albums_assets_assets` | `album_asset` |
| `albums_shared_users_users` | `album_user` |

**Column Renames**:  
| Old Name | New Name |
|----------|----------|
| `albumsId` | `albumId` |
| `assetsId` | `assetId` | 
| `usersId` | `userId` |

**Custom Trigger Impact**:
- ❌ **Migration ignored custom triggers**: Only updated Immich's built-in triggers
- ❌ **Broken references**: Custom triggers still referenced old table names
- ❌ **Runtime errors**: `ERROR: relation "albums" does not exist at character 91`

### Migration Process Limitations

#### What Immich Migration Handles
```sql
-- Immich's built-in triggers (updated automatically)
DROP TRIGGER "assets_delete_audit" ON "asset";
DROP TRIGGER "albums_updated_at" ON "album";  
CREATE OR REPLACE TRIGGER "assets_updated_at" ...
```

#### What Migration Ignores
- **Custom functions**: User-created PL/pgSQL functions
- **Custom triggers**: User-created triggers on renamed tables
- **Custom indexes**: User-created indexes on renamed columns
- **Custom constraints**: User-created constraints referencing old names

## Maintenance Procedures

### Pre-Upgrade Checklist
1. **Inventory custom objects**: List all custom triggers, functions, views
2. **Review migration notes**: Check Immich release notes for schema changes  
3. **Backup custom SQL**: Export custom trigger definitions
4. **Test migration**: Validate on staging environment if possible

### Post-Upgrade Procedure
1. **Check logs for errors**: `docker-compose logs | grep ERROR`
2. **Identify broken references**: Look for "relation does not exist" errors
3. **Update custom objects**: Modify SQL to use new table/column names
4. **Redeploy triggers**: Drop old, create new with updated references

### Example Fix Process
```sql
-- 1. Drop broken triggers (may fail if tables don't exist)
DROP TRIGGER IF EXISTS auto_add_to_album ON assets;        -- Old table
DROP TRIGGER IF EXISTS auto_add_to_album ON asset;         -- New table

-- 2. Update function with new table/column names
CREATE OR REPLACE FUNCTION add_asset_to_album() 
RETURNS TRIGGER AS $$
BEGIN
    -- Updated: albums -> album, assetsId -> assetId
    SELECT "ownerId" INTO album_owner_id FROM "album" WHERE "id" = ...;
    INSERT INTO "album_asset" ("albumId", "assetId") VALUES (...);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Recreate trigger on new table
CREATE TRIGGER auto_add_to_album AFTER INSERT ON asset
FOR EACH ROW EXECUTE FUNCTION add_asset_to_album();
```

## Development Workflow

### Testing Custom Triggers
```sql
-- Test trigger logic manually
INSERT INTO asset (id, ownerId, originalFileName, ...) 
VALUES ('test-uuid', 'owner-uuid', 'IMG-20240101-WA0001.jpg', ...);

-- Verify trigger actions
SELECT * FROM album_asset WHERE assetId = 'test-uuid';
SELECT visibility FROM asset WHERE id = 'test-uuid';
```

### Version Control Strategy
```bash
# Track trigger changes
git add yon-triggers/
git commit -m "Fix triggers for v1.137.3 schema changes

Update custom database triggers to use new singular table names
after schema standardization in c699df002.

Changes:
- albums → album  
- albums_assets_assets → album_asset
- albumsId/assetsId → albumId/assetId"
```

### Schema Evolution Monitoring
- **Release notes**: Monitor Immich GitHub releases for DB changes
- **Migration files**: Review `server/src/schema/migrations/` in new versions  
- **Test environment**: Validate upgrades before production deployment

## Troubleshooting

### Common Error Patterns
```sql
-- Relation errors
ERROR: relation "albums" does not exist at character 91

-- Column errors  
ERROR: column "albumsId" does not exist

-- Function errors
ERROR: function add_asset_to_album() does not exist
```

### Diagnostic Queries
```sql
-- List custom triggers
SELECT trigger_name, event_object_table, action_statement
FROM information_schema.triggers 
WHERE trigger_schema = 'public' 
AND trigger_name LIKE '%yon%';

-- Check table existence
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
AND (tablename LIKE '%asset%' OR tablename LIKE '%album%')
ORDER BY tablename;

-- Validate column names
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'album_asset' 
ORDER BY ordinal_position;
```

### Recovery Process
1. **Stop application**: Prevent additional errors
2. **Drop broken triggers**: Clean up failed objects
3. **Update SQL files**: Fix table/column references
4. **Redeploy triggers**: Apply corrected definitions  
5. **Validate functionality**: Test trigger behavior
6. **Monitor logs**: Confirm error resolution

## Future Considerations

### Schema Change Anticipation
- **Naming trends**: Immich moving toward singular table names
- **API evolution**: GraphQL schema may affect database structure
- **Performance optimizations**: Index changes may impact custom queries

### Maintenance Automation
- **Schema diffing**: Compare pre/post upgrade table structures
- **Trigger validation**: Automated testing of custom trigger behavior
- **Migration hooks**: Custom scripts to run during Immich upgrades

### Documentation Requirements
- **Trigger purpose**: Document business logic for each custom trigger
- **Dependencies**: Map relationships between custom objects
- **Update procedures**: Standard operating procedures for schema changes