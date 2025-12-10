/*
===================================================================================
ALLOYDB AI: COMPLETE NATURAL LANGUAGE CONFIGURATION
===================================================================================
Combined Setup & Hardening Script
-----------------------------------------------------------------------------------
1. SETUP:       Extensions and Configuration creation.
2. CONTEXT:     Schema registration and AI Context Tuning.
3. CONCEPTS:    Mapping columns to real-world types.
4. TEMPLATES:   The "Grammar" (Single Master Template).
5. FRAGMENTS:   The "Vocabulary" (Business Rules & Filters).
===================================================================================
*/

-- 0. SETUP & INITIALIZATION
-- ===================================================================================
SET search_path TO "search", public;

-- Install/Update the Natural Language extension
CREATE EXTENSION IF NOT EXISTS parameterized_views CASCADE;
CREATE EXTENSION IF NOT EXISTS alloydb_ai_nl CASCADE;
ALTER EXTENSION alloydb_ai_nl UPDATE;

-- Check version
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL;

-- Create the configuration
SELECT alloydb_ai_nl.g_create_configuration('property_search_config');

-- 1. SCHEMA CONTEXT & TUNING
-- ===================================================================================

-- Register the table so the AI knows it exists
SELECT alloydb_ai_nl.g_manage_configuration(
    operation           => 'register_table_view',
    configuration_id_in => 'property_search_config',
    table_views_in      => ARRAY['search.property_listings']
);

-- Generate the baseline context from the database schema
SELECT alloydb_ai_nl.generate_schema_context(
    'property_search_config',
    TRUE -- Overwrite existing
);

-- [TUNING] Fix Empty Results for Amenities
SELECT alloydb_ai_nl.update_generated_column_context(
    'search.property_listings.description',
    'Contains details like pools, balconies, or views. Prefer using vector search / ordering for these features rather than strict WHERE clauses to avoid empty results.'
);


-- APPLY the tuned context to the active configuration
SELECT alloydb_ai_nl.apply_generated_schema_context('property_search_config');

-- 2. CONCEPT TYPES & VALUE INDEXING
-- ===================================================================================

-- Associate 'city' column with the built-in 'city_name' concept
SELECT alloydb_ai_nl.associate_concept_type(
    column_names_in => 'search.property_listings.city',
    concept_type_in => 'city_name',
    nl_config_id_in => 'property_search_config'
);

-- Generate and Apply Concept associations
SELECT alloydb_ai_nl.generate_concept_type_associations('property_search_config');
SELECT alloydb_ai_nl.apply_generated_concept_type_associations('property_search_config');

-- Create Value Index (Critical for looking up specific strings like "Zurich")
SELECT alloydb_ai_nl.create_value_index(nl_config_id_in => 'property_search_config');
SELECT alloydb_ai_nl.refresh_value_index(nl_config_id_in => 'property_search_config');


-- #################################################################
-- ########################## QUERY TEMPLATES ######################
-- #################################################################
-- ===================================================================================

-- Check Auto generation based on query history: 
-- SELECT alloydb_ai_nl.generate_templates('property_search_config');

-- ### 1 ### With semantic intent in the search query

-- ### 1 ### With semantic intent in the search query
SELECT alloydb_ai_nl.add_template(
    nl_config_id => 'property_search_config',
    intent       => 'Show me modern appartments in Zurich with industrial look up to 6k with min 2 rooms',
    sql          => $$
        SELECT image_gcs_uri, id, title, description, bedrooms, price, city
        FROM search.property_listings
        WHERE LOWER("city") = LOWER('Zurich')          -- Filter by city
          AND "price" <= 6000            -- Filter by price up to 6000
          AND "bedrooms" >= 2            -- Filter by min 2 rooms 
        ORDER BY -- weighted similarity score
          ((0.6 * (1 - ("description_embedding" <=> embedding('gemini-embedding-001', 'modern appartments with industrial look')::vector))) + 
           (0.4 * (1 - ("image_embedding" <=> ai.text_embedding(model_id => 'multimodalembedding@001', content => 'modern appartments with industrial look')::vector))))
        DESC
        LIMIT 25
    $$,
    check_intent => TRUE
); 

-- ### 2 ### Only where predicates
SELECT alloydb_ai_nl.add_template(
    nl_config_id => 'property_search_config',
    intent       => 'Show me appartments in Zurich up to 6k with min 2 rooms',
    sql          => $$
        SELECT image_gcs_uri, id, title, description, bedrooms, price, city
        FROM search.property_listings
        WHERE LOWER("city") = LOWER('Zurich')          -- Filter by city
          AND "price" <= 6000            -- Filter by price up to 6000
          AND "bedrooms" >= 2            -- Filter by min 2 rooms 
        LIMIT 25
    $$,
    check_intent => TRUE
); 

-- ### 3 ### Only semantic search
SELECT alloydb_ai_nl.add_template(
    nl_config_id => 'property_search_config',
    intent       => 'Show me lovely wooden cabin',
    sql          => $$
        SELECT image_gcs_uri, id, title, description, bedrooms, price, city
        FROM search.property_listings
        ORDER BY -- weighted similarity score
          ((0.6 * (1 - ("description_embedding" <=> embedding('gemini-embedding-001', 'Lovely wooden cabin')::vector))) + 
           (0.4 * (1 - ("image_embedding" <=> ai.text_embedding(model_id => 'multimodalembedding@001', content => 'Lovely wooden cabbin')::vector))))
        DESC
        LIMIT 25
    $$,
    check_intent => TRUE
); 


-- 4. BUSINESS LOGIC FRAGMENTS
-- ===================================================================================

-- [Fragment] "Luxury" Definition
SELECT alloydb_ai_nl.add_fragment(
    nl_config_id  => 'property_search_config',
    table_aliases => ARRAY['search.property_listings'],
    intent        => 'luxury',
    fragment      => 'price >= 8000'
);

-- [Fragment] "Cheap/Budget" Definition
SELECT alloydb_ai_nl.add_fragment(
    nl_config_id  => 'property_search_config',
    table_aliases => ARRAY['search.property_listings'],
    intent        => 'cheap',
    fragment      => 'price <= 2500'
);

-- [Fragment] "Family Friendly" Definition
SELECT alloydb_ai_nl.add_fragment(
    nl_config_id  => 'property_search_config',
    table_aliases => ARRAY['search.property_listings'],
    intent        => 'family appartment',
    fragment      => 'bedrooms >= 3'
);

-- [Fragment] "Studio" Definition
SELECT alloydb_ai_nl.add_fragment(
    nl_config_id  => 'property_search_config',
    table_aliases => ARRAY['search.property_listings'],
    intent        => 'studio',
    fragment      => 'bedrooms = 0'
);



-- 5. VERIFICATION
-- ===================================================================================

-- List active templates
SELECT id, intent, sql 
FROM alloydb_ai_nl.template_store_view 
WHERE config = 'property_search_config';

-- List active fragments
SELECT *, intent, fragment 
FROM alloydb_ai_nl.fragment_store_view 
WHERE config = 'property_search_config';

-- Test Query
-- Expected: Filters for City='Zurich', Price<=2500, Beds>=3, Description NOT Ground floor
SELECT alloydb_ai_nl.get_sql(
    'property_search_config',
    'Show me cheap family apartments in Zurich not ground floor'
) ->> 'sql';
