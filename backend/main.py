from fastapi import FastAPI

app = FastAPI(title="RAG SaaS API")


@app.get("/health")
def health_check():
    return {"status": "healthy", "message": "FastAPI backend is running!"}
