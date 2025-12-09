import os
from google.adk.agents import Agent
from toolbox_core import ToolboxSyncClient

# Initialize Toolbox Client
TOOLBOX_URL = os.getenv("TOOLBOX_URL", "http://127.0.0.1:5000")
toolbox = ToolboxSyncClient(TOOLBOX_URL)

# Load tools from Toolbox
# We load the 'search-properties' tool we defined in tools.yaml
try:
    tool = toolbox.load_tool("search-properties")
    tools = [tool]
except Exception as e:
    print(f"Warning: Could not load tools from {TOOLBOX_URL}: {e}")
    tools = []

# Define the Agent
agent = Agent(
    name="property_agent",
    model="gemini-2.5-flash", # User requested newer models (2.5+)
    description="Agent to answer questions about properties using natural language search.",
    instruction=(
        "You are a helpful real estate assistant. "
        "You can answer user questions about properties by searching the database. "
        "Use the 'search-properties' tool to find properties based on the user's description. "
        "When you find properties, do NOT list them all in detail in the chat. "
        "Instead, provide a brief, helpful summary (e.g., 'I found 5 apartments in Zurich. Prices range from...'). "
        "Mention that you have updated the main view with the results. "
        "Ask if the user wants to refine the search (e.g., by price, location, or amenities). "
        "IMPORTANT: If you find specific properties in the search results, you MUST also output a JSON block at the end of your response containing the property details. "
        "CRITICAL: The JSON block must ONLY contain properties that STRICTLY match the user's request. Filter out any irrelevant results returned by the tool (e.g. if user asks for 'wooden cabin', do NOT include apartments). "
        "The JSON block must be wrapped in ```json_properties and ``` tags. "
        "Format: "
        "```json_properties\n"
        "[\n"
        "  {\n"
        "    \"id\": 1,\n"
        "    \"title\": \"Title\",\n"
        "    \"price\": 1000,\n"
        "    \"city\": \"City\",\n"
        "    \"bedrooms\": 2,\n"
        "    \"description\": \"Description\",\n"
        "    \"image_gcs_uri\": \"gs://...\"\n"
        "  }\n"
        "]\n"
        "```"
    ),
    tools=tools,
)
