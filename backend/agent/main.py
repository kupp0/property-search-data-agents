import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from agent import root_agent as agent

from google.adk import Runner
from google.adk.sessions import InMemorySessionService

from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # For development; restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Runner
# We need a session service. InMemory is fine for this demo/stateless usage.
session_service = InMemorySessionService()
runner = Runner(agent=agent, app_name="property_agent", session_service=session_service)

class ChatRequest(BaseModel):
    message: str
    session_id: str = "default_session"

from typing import Any, Optional

class ChatResponse(BaseModel):
    response: str
    tool_details: Optional[Any] = None
    used_prompt: Optional[str] = None

@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    try:
        # Use Runner to execute the agent
        user_id = "default_user"
        session_id = request.session_id
        app_name = "property_agent"
        
        # Ensure session exists
        session = await session_service.get_session(app_name=app_name, user_id=user_id, session_id=session_id)
        if not session:

            await session_service.create_session(app_name=app_name, user_id=user_id, session_id=session_id)
        
        response_text = ""
        tool_details = None
        used_prompt = None
        
        # Runner.run_async returns AsyncGenerator[Event, None]
        # We need to pass new_message as google.genai.types.Content
        
        from google.genai.types import Content, Part
        import json
        
        message = Content(role="user", parts=[Part(text=request.message)])
        
        async for event in runner.run_async(
            user_id=user_id,
            session_id=session_id,
            new_message=message
        ):
            # DEBUG: Print event type and attributes
            print(f"DEBUG: Received event type: {type(event)}")
            # print(f"DEBUG: Event attributes: {dir(event)}")
            
            # Capture Tool Call (the prompt sent to the tool)
            if hasattr(event, 'tool_call') and event.tool_call:
                print(f"DEBUG: Found tool_call in event")
                # Assuming single tool call for now
                # event.tool_call might be a ToolCall object with 'function_calls'
                if hasattr(event.tool_call, 'function_calls'):
                    for fc in event.tool_call.function_calls:
                        if 'prompt' in fc.args:
                            used_prompt = fc.args['prompt']
                            print(f"DEBUG: Captured tool prompt: {used_prompt}")

            # Capture Tool Response (the output from the tool)
            if hasattr(event, 'tool_response') and event.tool_response:
                 print(f"DEBUG: Found tool_response in event")
                 if hasattr(event.tool_response, 'function_responses'):
                    for fr in event.tool_response.function_responses:
                        # The tool returns a JSON string in 'response' field (usually)
                        # We need to parse it.
                        try:
                            print(f"DEBUG: Processing function response: {fr.name}")
                            # The response content is likely in fr.response
                            # But structure depends on ADK/GenAI types.
                            # Let's inspect what we can.
                            # For GDA tool, it returns a dict which is then JSON serialized.
                            
                            response_payload = fr.response
                            print(f"DEBUG: Raw response payload type: {type(response_payload)}")
                            
                            # If fr.response is a dict:
                            if isinstance(response_payload, dict):
                                if 'result' in response_payload:
                                     tool_details = response_payload['result']
                                else:
                                     tool_details = response_payload
                            # If it's a string, try to parse
                            elif isinstance(response_payload, str):
                                tool_details = json.loads(response_payload)
                                
                            print(f"DEBUG: Captured tool details keys: {tool_details.keys() if isinstance(tool_details, dict) else 'Not a dict'}")
                        except Exception as e:
                            print(f"DEBUG: Failed to parse tool response: {e}")

            
            # Extract text response
            if hasattr(event, 'content') and event.content:
                for part in event.content.parts or []:
                    if part.text:
                        response_text += part.text
            elif hasattr(event, 'text') and event.text:
                response_text += event.text
            
        print(f"DEBUG: Final response text: {response_text}")
        return ChatResponse(
            response=response_text or "Agent executed (no text response)",
            tool_details=tool_details,
            used_prompt=used_prompt
        )
    except Exception as e:
        import traceback
        traceback.print_exc()
        return ChatResponse(response=f"I encountered an issue processing your request: {str(e)}")

@app.get("/health")
def health():
    return {"status": "ok"}

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
