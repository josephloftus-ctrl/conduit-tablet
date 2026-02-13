"""Brave Search -> SearXNG format proxy.

Accepts SearXNG-style requests and translates them to Brave Search API calls,
so the Conduit server can use Brave Search without any code changes.
"""

import os

import httpx
from fastapi import FastAPI, Query
from fastapi.responses import JSONResponse

app = FastAPI()

BRAVE_API_KEY = os.environ.get("BRAVE_SEARCH_API_KEY", "")
BRAVE_URL = "https://api.search.brave.com/res/v1/web/search"


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/search")
async def search(q: str = Query(...), format: str = Query("json")):
    headers = {
        "Accept": "application/json",
        "X-Subscription-Token": BRAVE_API_KEY,
    }
    async with httpx.AsyncClient() as client:
        resp = await client.get(BRAVE_URL, params={"q": q, "count": 10}, headers=headers)
        resp.raise_for_status()
        data = resp.json()

    results = [
        {"title": r.get("title", ""), "url": r.get("url", ""), "content": r.get("description", "")}
        for r in data.get("web", {}).get("results", [])
    ]
    return JSONResponse({"results": results})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8889)
