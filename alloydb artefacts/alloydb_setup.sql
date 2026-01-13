/*
===================================================================================
ALLOYDB AI: DATABASE & SCHEMA BOOTSTRAP
===================================================================================

This script initializes the foundation for the Semantic Search Demo.
It performs the following critical operations:

1. SCHEMA SETUP: Creates a dedicated "search" schema to keep the workspace clean.
2. EXTENSIONS: Enables Google ML, Vector, ScaNN, and AI Natural Language extensions.
3. TABLE DDL: Creates the `property_listings` table with:
   - Automatic Text Embeddings (using `generative-embedding-001` via database trigger).
   - Placeholder for Image Embeddings (populated later via Python).
4. DATA LOAD: Inserts sample real estate data for Switzerland.
5. INDEXING: Creates high-performance ScaNN indexes.
   * NOTE: Uses MANUAL mode because the dataset is small (<10k rows).

PRE-REQUISITES:
- Ensure the Vertex AI API is enabled in your Google Cloud Project.
- Ensure the AlloyDB Service Account has "Vertex AI User" permissions.
===================================================================================
*/

-- 1. SCHEMA INITIALIZATION
-- ===================================================================================

-- NOTE: Ensure you have created a database named 'search' before running this script.
-- CREATE DATABASE search;

-- We use the default 'public' schema in the 'search' database.
-- DROP SCHEMA IF EXISTS "search" CASCADE; -- REMOVED
-- CREATE SCHEMA "search"; -- REMOVED

-- Set the path to public (default)
SET search_path TO public;


-- 2. EXTENSION MANAGEMENT
-- ===================================================================================

-- Enable the Google ML Integration (Bridge to Vertex AI)
CREATE EXTENSION IF NOT EXISTS google_ml_integration CASCADE;

-- Enable pgvector (Base vector data type support)
CREATE EXTENSION IF NOT EXISTS vector CASCADE;

-- Enable AlloyDB ScaNN (High-performance vector indexing)
CREATE EXTENSION IF NOT EXISTS alloydb_scann CASCADE;

-- Enable Parameterized Views (Required for Toolbox)
CREATE EXTENSION IF NOT EXISTS parameterized_views CASCADE;

-- Enable Natural Language Support (For the NL2SQL features configured later)
CREATE EXTENSION IF NOT EXISTS alloydb_ai_nl CASCADE;

-- Update extensions to ensure latest versions are active
ALTER EXTENSION alloydb_ai_nl UPDATE;

--Register latest embedding model to AlloyDB
-- Example to register a different embedding model:
CALL google_ml.create_model(
  model_id => 'my_gemini_embedding_model',
  model_provider => 'google',
  model_qualified_name => 'gemini-embedding-001', -- Or the specific one you want
  model_type => 'text_embedding',
  model_auth_type => 'alloydb_service_agent_iam'
);

-- Check registered models
SELECT * FROM google_ml.model_info_view;


-- VERIFICATION: Check integration status
-- Expectation: Should show valid version and model support enabled
SELECT extname, extversion FROM pg_extension WHERE extname = 'google_ml_integration';
SHOW google_ml_integration.enable_model_support;

-- TEST: Sanity check the embedding connection to Gemini
-- If this fails, check your IAM permissions.
SELECT google_ml.embedding(
   model_id => 'gemini-embedding-001',
   content => 'Sanity check for Vertex AI connection'
) AS test_vector;


-- 3. TABLE CREATION
-- ===================================================================================

DROP TABLE IF EXISTS property_listings CASCADE;

CREATE TABLE property_listings (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(12, 2) NOT NULL,
    bedrooms INT,
    city VARCHAR(100),
    image_gcs_uri TEXT,
    -- COLUMN A: Text Embeddings (Managed by Database)
    -- Automatically generates a 3072-dim vector when you insert text into 'description'.
    description_embedding VECTOR(3072) GENERATED ALWAYS AS (
      embedding('gemini-embedding-001', description)
    ) STORED,
    -- COLUMN B: Image Embeddings (Managed by Application)
    -- Populated by 'bootstrap_images.py' using the Multimodal model (3072 dims).
    image_embedding VECTOR(1408) 
);


-- 4. SAMPLE DATA INSERTION
-- ===================================================================================
-- Embeddings for 'description' are generated automatically upon insertion. Use Gemini to customize the sample data to your cities and add more samples if you like.
-- Image URIs and Image Embeddings are left NULL here (populated in the Python step).


-- Run the 100_sample_records.sql file to populate the table with sample data.



/* ===================================================================================
 STOP! INTERMEDIATE STEP REQUIRED
===================================================================================
 At this stage, run the Python script: /backend/bootstrap_images.py
 
 This script will:
 1. Generate images using Vertex AI Imagen.
 2. Upload them to Google Cloud Storage.
 3. Calculate Visual Embeddings.
 4. Update the database rows below with the image URI and image_vector.
 
 Once the Python script is finished, proceed to Step 5.
===================================================================================
*/

-- Verify data exists
SELECT count(*) as property_count FROM property_listings;


-- 5. INDEX CREATION (ScaNN)
-- ===================================================================================
-- Index 1: Text Description Index
-- Uses Cosine Distance for semantic similarity.
-- Index 1: Text Description Index
-- Uses Cosine Distance for semantic similarity.
CREATE INDEX idx_scann_property_desc ON property_listings
USING scann (description_embedding)
WITH (
    -- 'auto' mode requires ~10k rows. For this demo, we force MANUAL mode.
    mode = 'MANUAL',
    num_leaves = 1,     -- 1 partition is optimal for < 1000 rows.
    quantizer = 'SQ8'   -- Standard quantization for balance of speed/accuracy.
);

-- Index 2: Visual Search Index
-- Indexes the Multi-modal embedding column.
CREATE INDEX idx_scann_image_search ON property_listings
USING scann (image_embedding)
WITH (
    mode = 'MANUAL',
    num_leaves = 1,     -- Kept at 1 to ensure stability with small demo dataset.
    quantizer = 'SQ8'
);


-- 6. VALIDATION QUERIES
-- ===================================================================================

-- Test A: Simple Semantic Search
-- Finds "Student" vibes even without the word "Student" (looking for "Quiet", "Study").
SELECT title, description, price, city
FROM property_listings
ORDER BY description_embedding <=> embedding('gemini-embedding-001', 'a quiet place to study near by University')::vector
LIMIT 3;

-- Test B: Hybrid Search (Semantic + Filters)
-- Finds modern apartments, specifically in Zurich, specifically under 15k.
SELECT id, title, price, city
FROM property_listings
WHERE price < 15000.00
  AND city = 'Zurich'
ORDER BY description_embedding <=> embedding('gemini-embedding-001', 'a modern apartment for a professional working in the city')::vector
LIMIT 3;

-- Test C: Concept/Vibe Search
-- "Live near water" -> matches descriptions mentioning lakes or rivers.
SELECT
    title,
    price,
    city,
    -- Show the actual distance score (0 is perfect match, 1 is no match)
    description_embedding <=> embedding('gemini-embedding-001', 'I want to live near the water')::vector AS cosine_distance
FROM property_listings
ORDER BY cosine_distance ASC
LIMIT 3;