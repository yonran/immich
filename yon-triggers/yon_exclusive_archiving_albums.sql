
-- Drop old trigger first (it references old table names that no longer exist)
DROP TRIGGER IF EXISTS yon_exclusive_archiving_albums ON album_asset;

CREATE OR REPLACE FUNCTION yon_exclusive_archiving_albums()
RETURNS TRIGGER AS $$
DECLARE
    asset_owner_id UUID;
    album_owner_id UUID;
    special_album_ids UUID[] := ARRAY[
        'a8991760-3b7c-4ff3-9236-8188e9a66b59', -- receipts
        'd9f5cc09-2fa3-40ac-adeb-6465118241f5', -- 550 oak park
        '692b133a-568f-4ec3-bd60-862f595120dd', -- foods
        '0fa90965-3832-4c00-85a8-e49f3d5d8308', -- hsa
        '728e15f6-5895-40b2-a2ae-661d56e3ed3d', -- gingmon documents
        'c14d149b-91c6-450d-a778-2c829e3840a0', -- real estate: 83 ervine
        '5fee7f89-7130-48f5-a16d-789f6d043dcc', -- cards ids
        'c8ab0286-0835-4f21-a596-15ec213c22a6', -- 3251 sacramento
        'fd06c605-513c-416a-ba8f-a59991fd19e1', -- tax
        '1a748bf0-dd19-49ba-b3cf-5211faf20162', -- machines
        -- '6ee340e1-7830-425f-9a29-7140aa8f737c', -- lakewood bumblebees
        '7d01c271-6a10-4118-8425-371554b34aaf', -- 7528 43rd Ave S A: repair window drip
        'bcd7d630-2acb-47af-a54a-576ba58aef6e', -- car 2003 prius
        '02768d13-f47d-48ee-be7d-aa872c286258', -- medical: kavi
        'c5412137-92a5-4edc-a0f5-13fb9279b81a', -- medical: noel
        -- 'c3e845fd-8bbd-4c9d-968f-c6535e73e477', -- Family
        '26a53b6b-8f81-450e-a8a7-5e087ddd6453', -- real estate properties: 2934 S Edmunds St, Seattle
        '6e263b90-1409-469a-a5a0-84a57eecc6c3', -- craigslist
        '73fe1527-a8be-438a-b337-a0758c1e0c6b', -- real estate: properties
        'dfb0c3ba-bfb3-47fb-a786-1d9f09c13c30', -- kavi documents
        '8f0bfa61-1f59-439c-9d1c-0be72106fbee', -- music
        '33df05dd-8e31-4351-812a-79c5136360f6', -- Lakewood Coop documents
        '3fb893f8-2129-4a9f-8e11-2f2115fc5aa4', -- gifts / letters
        '4ab71bc3-08d4-425e-8ee8-7a5d3089ccc2', -- real estate: contractors
        '51e80d44-8330-4247-b8e2-db8977839c0c', -- yonathan documents
        '98611e71-3176-467a-99c4-4d7a82784e57', -- 7528 43rd Ave S A: broken window
        'c628956e-10ee-4680-b8d7-131a990aef16', -- 7528 43rd Ave S
        '5ac0e193-dd72-4131-805f-2c5abb412cbe', -- possessions hardware
        'ba132a1d-05ad-49a9-90dc-750238163125', -- tax 2023
        '5550d003-ca4b-4222-b525-2350a4d889bd', -- car 2018 tesla
        'a8991760-3b7c-4ff3-9236-8188e9a66b59', -- receipts
        -- '827f3b3b-1819-4e7f-b1c6-8057b9c379e7', -- museums
        'e679df33-299a-4a24-8582-5569b0e4988e'  -- shopping

    ]::UUID[];
BEGIN
    -- Check if the inserted album is one of our special albums
    IF NEW."albumId" = ANY(special_album_ids) THEN
        -- Get the asset owner ID
        SELECT "ownerId" INTO asset_owner_id
        FROM "asset"
        WHERE "id" = NEW."assetId";
        
        -- Get the album owner ID
        SELECT "ownerId" INTO album_owner_id
        FROM "album"
        WHERE "id" = NEW."albumId";
        
        -- Only proceed if the asset owner and album owner match
        IF asset_owner_id = album_owner_id THEN
            -- Remove the asset from all other albums
            DELETE FROM "album_asset"
            WHERE "assetId" = NEW."assetId"
            AND "albumId" != NEW."albumId";
            
            -- Archive the asset
            UPDATE "asset"
            SET "visibility" = 'archive'
            WHERE "id" = NEW."assetId";
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER yon_exclusive_archiving_albums
AFTER INSERT ON "album_asset"
FOR EACH ROW
EXECUTE FUNCTION yon_exclusive_archiving_albums();