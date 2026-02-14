SELECT 
    c.relname AS name,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM pg_catalog.pg_attribute a
            WHERE a.attrelid = c.oid 
                AND a.attname IN ('start', 'end')
                AND NOT a.attisdropped
            HAVING COUNT(*) >= 2
        ) THEN 'e'
        ELSE 'v'
    END as kind,
    c.reltuples::INTEGER AS cnt
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
    AND n.nspname = '%s'
    AND c.relname NOT LIKE '_ag_label%';
