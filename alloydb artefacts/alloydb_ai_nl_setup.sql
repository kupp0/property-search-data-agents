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
CREATE EXTENSION IF NOT EXISTS alloydb_ai_nl CASCADE;
ALTER EXTENSION alloydb_ai_nl UPDATE;

-- Create the configuration holder
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

-- [TUNING] Fix Case Sensitivity for Cities
SELECT alloydb_ai_nl.update_generated_column_context(
    'search.property_listings.city',
    'The city name stored in Title Case (e.g. Zurich, Geneva). When filtering by city, ALWAYS convert input to Title Case or use the ILIKE operator to ignore case.'
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


-- 3. QUERY TEMPLATES (The "Master" Logic)
-- ===================================================================================
-- ACTIVE TEMPLATE: The "Natural" Master Template
-- This allows Fragments (Where clauses) and Concepts (City names) to work alongside Vector Search.

SELECT alloydb_ai_nl.add_template(
  nl_config_id => 'property_search_config',
  intent => 'modern apartment in Zurich',
  sql => $$
    SELECT image_gcs_uri, id, title, description, bedrooms, price, city
    FROM search.property_listings
    -- THE INSTRUCTION:
    -- We show the AI that "Zurich" (Concept) goes to WHERE
    -- and "modern" (Vibe) goes to Embedding.
    WHERE 1=1 AND city = 'Zurich'
    ORDER BY description_embedding <=> embedding('gemini-embedding-001', 'modern')::vector
    LIMIT 10
  $$,
  check_intent => TRUE
);


/*
-- LEGACY / ALTERNATIVE TEMPLATES
-- These are commented out to prevent "Template Hijacking"

-- 1. The "Greedy" Parameterized Template (AVOID - Eats city names into vector search)
SELECT alloydb_ai_nl.add_template(
  nl_config_id => 'property_search_config',
  intent => 'close to water',
  sql => $$ ... $$,
  parameterized_intent => '$1', -- This was the greedy part
  parameterized_sql => $$ ... $$
);

-- 2. Simple Semantic Search (Redundant with Master Template)
SELECT alloydb_ai_nl.add_template(
  nl_config_id => 'property_search_config',
  intent => 'Find properties like "a quiet place to study"',
  sql => $$ ... $$
);

-- 3. Exact Attribute Search (Too specific, prevents fragments)
SELECT alloydb_ai_nl.add_template(
  nl_config_id => 'property_search_config',
  intent => 'Are there any 3-bedroom places in Geneva?',
  sql => $$ ... $$
);

-- 4. Parameterized Sorting (Too rigid, prevents "Family" or "Ground Floor" logic)
SELECT alloydb_ai_nl.add_template(
  nl_config_id => 'property_search_config',
  intent => 'Show me the cheapest apartments in Geneva',
  sql => $$ ... $$
);
*/


-- 4. BUSINESS LOGIC FRAGMENTS
-- ===================================================================================

-- [Fragment] Negation handling
SELECT alloydb_ai_nl.add_fragment(
    nl_config_id  => 'property_search_config',
    table_aliases => ARRAY['search.property_listings'],
    intent        => 'not ground floor',
    fragment      => $$ (description NOT ILIKE '%ground floor%' AND description NOT ILIKE '%parterre%') $$
);

-- [Fragment] Ambiguity handling for "New"
SELECT alloydb_ai_nl.add_fragment(
    nl_config_id  => 'property_search_config',
    table_aliases => ARRAY['search.property_listings'],
    intent        => 'new',
    fragment      => $$ (description ILIKE '%newly built%' OR description ILIKE '%first occupation%' OR description ILIKE '%modern%') $$
);

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
    intent        => 'family',
    fragment      => 'bedrooms >= 3'
);

-- [Fragment] "Studio" Definition
SELECT alloydb_ai_nl.add_fragment(
    nl_config_id  => 'property_search_config',
    table_aliases => ARRAY['search.property_listings'],
    intent        => 'studio',
    fragment      => 'bedrooms = 0'
);

-- [Fragment] "Outdoor Space" Definition
SELECT alloydb_ai_nl.add_fragment(
    nl_config_id  => 'property_search_config',
    table_aliases => ARRAY['search.property_listings'],
    intent        => 'outdoor space',
    fragment      => $$ (description ILIKE '%garden%' OR description ILIKE '%terrace%' OR description ILIKE '%balcony%') $$
);


-- 5. VERIFICATION
-- ===================================================================================

-- List active templates
SELECT id, intent, sql 
FROM alloydb_ai_nl.template_store_view 
WHERE config = 'property_search_config';

-- List active fragments
SELECT intent, fragment 
FROM alloydb_ai_nl.fragment_store_view 
WHERE config = 'property_search_config';

-- Test Query
-- Expected: Filters for City='Zurich', Price<=2500, Beds>=3, Description NOT Ground floor
SELECT alloydb_ai_nl.get_sql(
    'property_search_config',
    'Show me cheap family apartments in Zurich not ground floor'
) ->> 'sql';

-- NOTE: Assuming "cheap" refers to the lowest price. 
SELECT "title", "description", "price" FROM "search"."property_listings" WHERE "city" = 'Zurich' -- Filter for apartments in Zurich AND "bedrooms" >= 2 -- Filter for family apartments (assuming >= 2 bedrooms) ORDER BY "price" ASC NULLS LAST LIMIT 10; -- Limit to the top 10 cheapest
