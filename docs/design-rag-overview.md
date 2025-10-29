# RAG JSON Payload Example

This document shows a **compact but realistic** JSON structure for sending a user query **plus retrieved documents** to an LLM that supports Retrieval-Augmented Generation (RAG).

---

## 1. Full Request Payload

```json
{
  "messages": [
    {
      "role": "user",
      "content": "What is the capital of France?"
    }
  ],
  "rag_documents": [
    {
      "id": "doc_001",
      "content": "France is a country in Western Europe. Its capital city is Paris, often called the City of Light.",
      "metadata": {
        "source": "wikipedia",
        "title": "France",
        "chunk_index": 12,
        "url": "https://en.wikipedia.org/wiki/France"
      }
    },
    {
      "id": "doc_002",
      "content": "Paris is the largest city and the capital of France, located on the Seine River.",
      "metadata": {
        "source": "travel_guide.pdf",
        "title": "Europe Travel Guide",
        "page": 45
      }
    }
  ]
}
```
Field,Purpose
messages,Conversation history (standard OpenAI-style).
rag_documents,List of retrieved chunks. Each entry must have id + content; metadata is optional but recommended.


```json
{
  "tool_calls": [
    {
      "id": "call_rag_01",
      "type": "function",
      "function": {
        "name": "retrieve_documents",
        "arguments": {
          "query": "capital of France",
          "doc_ids": ["doc_001"],
          "filters": { "source": "wikipedia" },
          "limit": 5
        }
      }
    }
  ]
}
```

Orchestrator steps

Run retrieval with the supplied query (and any filters/limit).
Append new documents to rag_documents (preserve unique ids).
Resubmit the updated JSON to the model for the final answer.


```json
{
  "id": "warpeace_chunk_1842",
  "content": "Pierre Bezukhov stood at the window, gazing at the snow-covered fields. He thought of Natasha and the letter he had just received...",
  "metadata": {
    "source": "war_and_peace.txt",
    "title": "War and Peace",
    "chapter": 14,
    "chunk_index": 1842,
    "char_start": 412300,
    "char_end": 412780
  }
}
```

Document
  → Split by paragraphs/sentences
  → Each chunk: 256–512 tokens
  → Overlap: 50–100 tokens (preserves context)
  → Embed each chunk → store in vector DB

256 tokens ≈ 1 KB  (very rough)
512 tokens ≈ 2 KB
