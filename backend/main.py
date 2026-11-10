from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from assistant.assistant_controller import controller as AssistantAudioController
from project_config import setup_app_config

setup_app_config()

app = FastAPI()

origins = [
    "http://localhost:3000",
    "http://localhost",
    "http://3.107.175.59:3000",  # Your frontend ECS task IP
    "*",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,  # Set to False to allow "*" wildcard matching
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(AssistantAudioController, tags=['assistant'])

@app.get("/")
def read_root():
    return {"message": "Hello World from CI/CD Backend v1"}
