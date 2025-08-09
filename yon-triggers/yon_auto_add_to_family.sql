-- Drop old trigger first (it references old table names that no longer exist)
DROP TRIGGER IF EXISTS auto_add_to_album ON asset;

CREATE OR REPLACE FUNCTION add_asset_to_album()
RETURNS TRIGGER AS $$
DECLARE
    album_owner_id UUID;
    lakewood_album_id UUID := '6ee340e1-7830-425f-9a29-7140aa8f737c'::UUID;
BEGIN
    -- Check if the file is from WhatsApp by filename pattern
    IF NEW."originalFileName" ~ '^IMG-[0-9]{8}-WA[0-9]+\..*$' THEN
        -- Get the album owner ID
        SELECT "ownerId" INTO album_owner_id
        FROM "album"
        WHERE "id" = lakewood_album_id;
        
        -- Only proceed if the asset owner matches the album owner
        IF NEW."ownerId" = album_owner_id THEN
            -- Add the asset to the Lakewood Bumblebees album
            INSERT INTO "album_asset" ("albumsId", "assetsId")
            VALUES (lakewood_album_id, NEW."id");
            
            -- Archive the asset
            UPDATE "asset"
            SET "visibility" = 'archive'
            WHERE "id" = NEW."id";
        END IF;
    ELSE
        -- Only add the asset to the album if the asset's owner is either:
        -- 1. The owner of the album
        -- 2. An editor with access to the album
        IF EXISTS (
            -- Check if asset owner is the album owner
            SELECT 1 FROM "album" 
            WHERE "id" = 'c3e845fd-8bbd-4c9d-968f-c6535e73e477'
            AND "ownerId" = NEW."ownerId"
        ) OR EXISTS (
            -- Check if asset owner is an editor of the album
            SELECT 1 FROM "album_user"
            WHERE "albumsId" = 'c3e845fd-8bbd-4c9d-968f-c6535e73e477'
            AND "usersId" = NEW."ownerId"
            AND "role" = 'editor'
        ) THEN
            -- Insert the new asset into the specified album
            INSERT INTO "album_asset" ("albumsId", "assetsId")
            VALUES ('c3e845fd-8bbd-4c9d-968f-c6535e73e477', NEW."id");
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER auto_add_to_album
AFTER INSERT ON asset
FOR EACH ROW
EXECUTE FUNCTION add_asset_to_album();
