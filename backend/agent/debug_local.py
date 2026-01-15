import os
import asyncio
# Set environment variables BEFORE importing agent
os.environ["TOOLBOX_URL"] = "https://data-agent-toolbox-2xdw7zjtpq-ew.a.run.app"
os.environ["GCP_PROJECT_ID"] = "my-search-demo-alloydb"
os.environ["GCP_LOCATION"] = "europe-west1"
# Add DB_HOST for local debugging (requires local proxy)
os.environ["DB_HOST"] = "127.0.0.1"

from google.adk import Runner
from google.adk.sessions import InMemorySessionService
from google.genai.types import Content, Part
from agent import root_agent as agent

async def main():
    print("Initializing Runner...")
    session_service = InMemorySessionService()
    runner = Runner(agent=agent, app_name="property_agent", session_service=session_service)
    
    user_id = "debug_user"
    session_id = "debug_session"
    await session_service.create_session(app_name="property_agent", user_id=user_id, session_id=session_id)
    
    message = Content(role="user", parts=[Part(text="Show me 2-bedroom apartments in Zurich under 3000 CHF")])
    
    print("Running Agent...")
    async for event in runner.run_async(
        user_id=user_id,
        session_id=session_id,
        new_message=message
    ):
        print(f"\n--- Event Type: {type(event)} ---")
        print(f"Attributes: {dir(event)}")
        
        if hasattr(event, 'tool_response') and event.tool_response:
            print("\n!!! FOUND TOOL RESPONSE !!!")
            tr = event.tool_response
            # print(f"Tool Response Object: {tr}")
            if hasattr(tr, 'function_responses'):
                for fr in tr.function_responses:
                    print(f"Function Response Name: {fr.name}")
                    # print(f"Function Response Content: {fr.response}")
                    print(f"Function Response Type: {type(fr.response)}")
                    if isinstance(fr.response, dict):
                        print(f"Response Keys: {fr.response.keys()}")
        # Check for content parts
        if hasattr(event, 'content') and event.content:
            print(f"Event Content: {event.content}")
            if hasattr(event.content, 'parts'):
                for part in event.content.parts:
                    print(f"Part: {part}")
                    if hasattr(part, 'function_response'):
                        print(f"Part Function Response: {part.function_response}")
                        
        # Check for function responses via method
        if hasattr(event, 'get_function_responses'):
            frs = event.get_function_responses()
            if frs:
                print(f"Method get_function_responses() returned: {frs}")
                for fr in frs:
                    print(f"FR Name: {fr.name}")
                    print(f"FR Response: {fr.response}")

if __name__ == "__main__":
    asyncio.run(main())
