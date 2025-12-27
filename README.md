# ChromEx

**The open-source embedding database for Elixir**

ChromEx is an idiomatic Elixir client for [Chroma](https://github.com/chroma-core/chroma), the AI-native open-source embedding database. ChromEx embeds Chroma's Rust implementation directly via Rustler NIFs for maximum performance.

ChromEx makes it easy to build LLM applications with embeddings. It handles tokenization, embedding generation, and indexing automatically.

## Features

- 🚀 **Native Performance** - Embeds Chroma Rust core via Rustler NIFs
- 🤖 **Auto-embeddings** - Automatic embedding generation using ONNX models (same as Python ChromaDB)
- 🎯 **Simple API** - Idiomatic Elixir interface matching Chroma's design
- 🔍 **Metadata Filtering** - Query with rich metadata filters
- 💾 **Persistent Storage** - SQLite-backed storage with HNSW indexing
- 🏢 **Multi-tenancy** - Support for tenants and databases

## Installation

Add `chromex` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:chromex, "~> 0.1.5"}
  ]
end
```

### Prerequisites

**Required:**
- Elixir >= 1.18
- **Rust toolchain** (cargo must be available in PATH)
  - Required for compiling native Chroma bindings and ONNX embedding generation
  - The build process will fail if Rust is not installed
- **Protocol Buffers compiler** (protoc must be available in PATH)
  - Required for compiling Chroma's protobuf definitions
  - Installation instructions: https://github.com/protocolbuffers/protobuf#protobuf-compiler-installation

**Note for Livebook users:** Livebook environments may not have Rust available by default. If you encounter compilation errors, you'll need to either:
- Use a Livebook environment with Rust installed, or
- Provide pre-computed embeddings instead of using auto-embedding (see examples below)

### Building

The project automatically fetches and compiles the Chroma Rust source during the build process:

```bash
mix deps.get
mix compile
```

## Quick Start

```elixir
# Create a collection
{:ok, collection} = ChromEx.Collection.create("my_collection")

# Add documents with automatic embedding generation
ChromEx.Collection.add(collection,
  ids: ["id1", "id2", "id3"],
  documents: [
    "This is a document about cats",
    "This is a document about dogs",
    "This is a document about birds"
  ],
  metadatas: [
    %{topic: "pets", animal: "cat"},
    %{topic: "pets", animal: "dog"},
    %{topic: "birds", animal: "bird"}
  ]
)

# Query with natural language (auto-generates query embedding)
{:ok, results} = ChromEx.Collection.query(collection,
  query_texts: ["Tell me about cats"],
  n_results: 2
)

IO.inspect(results["documents"])
# => [["This is a document about cats", "This is a document about dogs"]]

IO.inspect(results["metadatas"])
# => [[%{"topic" => "pets", "animal" => "cat"}, %{"topic" => "pets", "animal" => "dog"}]]

IO.inspect(results["distances"])
# => [[0.45, 1.23]]
```

## Usage

### Auto-Embedding Generation

ChromEx automatically generates embeddings using the same ONNX model as Python ChromaDB (all-MiniLM-L6-v2). Just provide documents and ChromEx handles the rest:

```elixir
{:ok, collection} = ChromEx.Collection.create("my_docs")

# Add documents - embeddings generated automatically
ChromEx.Collection.add(collection,
  ids: ["doc1", "doc2"],
  documents: ["Machine learning in production", "Deep learning architectures"]
)

# Query with text - query embedding generated automatically
{:ok, results} = ChromEx.Collection.query(collection,
  query_texts: ["AI deployment"],
  n_results: 5
)
```

### Using Pre-computed Embeddings

If you have embeddings from OpenAI, Cohere, or custom models, you can provide them directly. This is useful in environments where Rust/ONNX isn't available (like some Livebook setups):

```elixir
# Generate embeddings from an external service
embeddings = YourEmbeddingService.generate(["First doc", "Second doc"])

ChromEx.Collection.add(collection,
  ids: ["id1", "id2"],
  embeddings: embeddings,  # Provide embeddings directly
  documents: ["First doc", "Second doc"],
  metadatas: [%{source: "web"}, %{source: "api"}]
)

# Query with pre-computed embeddings
query_embedding = YourEmbeddingService.generate(["search query"])

{:ok, results} = ChromEx.Collection.query(collection,
  query_embeddings: query_embedding,
  n_results: 10
)
```

### Metadata Filtering

Chroma uses a structured query language for metadata filtering with operators like `$and`, `$or`, `$eq`, `$ne`, `$gt`, `$gte`, `$lt`, `$lte`, `$in`, `$nin`.

```elixir
# Add documents with rich metadata
ChromEx.Collection.add(collection,
  ids: ["id1", "id2", "id3"],
  documents: ["Doc A", "Doc B", "Doc C"],
  metadatas: [
    %{source: "web", year: 2024, category: "tech"},
    %{source: "api", year: 2023, category: "science"},
    %{source: "web", year: 2024, category: "science"}
  ]
)

# Query with single condition
{:ok, results} = ChromEx.Collection.query(collection,
  query_texts: ["search term"],
  where: %{"year" => 2024},
  n_results: 5
)

# Query with multiple conditions using $and
{:ok, results} = ChromEx.Collection.query(collection,
  query_texts: ["search term"],
  where: %{"$and" => [%{"year" => 2024}, %{"source" => "web"}]},
  n_results: 5
)

# Query with $or operator
{:ok, results} = ChromEx.Collection.query(collection,
  query_texts: ["search term"],
  where: %{"$or" => [%{"year" => 2024}, %{"year" => 2023}]},
  n_results: 5
)

# Query with comparison operators
{:ok, results} = ChromEx.Collection.query(collection,
  query_texts: ["search term"],
  where: %{"year" => %{"$gte" => 2023}},
  n_results: 5
)

# Query with $in operator
{:ok, results} = ChromEx.Collection.query(collection,
  query_texts: ["search term"],
  where: %{"source" => %{"$in" => ["web", "api"]}},
  n_results: 5
)
```

### Collection Management

```elixir
# Create or get collection
{:ok, collection} = ChromEx.Collection.create("my_collection", get_or_create: true)

# List all collections
{:ok, collections} = ChromEx.Collection.list()

# Count documents in collection
{:ok, count} = ChromEx.Collection.count(collection)

# Delete collection
ChromEx.Collection.delete("my_collection")
```

### Document Operations

```elixir
# Get documents by IDs
{:ok, docs} = ChromEx.Collection.get_documents(collection, ids: ["id1", "id2"])

# Update documents (both styles work)
ChromEx.Collection.update_documents(collection, ["id1"],
  documents: ["Updated content"],
  metadatas: [%{updated_at: DateTime.utc_now()}]
)

# Or with keyword-based IDs
ChromEx.Collection.update_documents(collection,
  ids: ["id1"],
  documents: ["Updated content"]
)

# Upsert (insert or update)
ChromEx.Collection.upsert(collection, ["id1", "id2"],
  documents: ["New or updated doc 1", "New or updated doc 2"]
)

# Or with keyword-based IDs
ChromEx.Collection.upsert(collection,
  ids: ["id1", "id2"],
  documents: ["New or updated doc 1", "New or updated doc 2"]
)

# Delete documents
ChromEx.Collection.delete_documents(collection, ids: ["id1"])

# Delete by metadata
ChromEx.Collection.delete_documents(collection, where: %{"source" => "old"})
```

### Bang (!) Variants

All functions have bang variants that raise on error:

```elixir
collection = ChromEx.Collection.create!("my_collection")
ChromEx.Collection.add!(collection, ids: ["id1"], documents: ["doc"])
results = ChromEx.Collection.query!(collection, query_texts: ["search"])
```

### Idiomatic Elixir Features

ChromEx supports multiple calling styles for ergonomic Elixir code:

```elixir
# Keyword list style
ChromEx.Collection.add(collection,
  ids: ["id1", "id2"],
  documents: ["Doc 1", "Doc 2"],
  metadatas: [%{key: "value"}, [key: "value"]]  # Maps or keyword lists
)

# IDs as second argument
ChromEx.Collection.add(collection, ["id1", "id2"],
  documents: ["Doc 1", "Doc 2"]
)

# All as keywords
ChromEx.Collection.add(collection,
  ids: ["id1"],
  documents: ["Doc 1"]
)
```

### Multi-tenancy

```elixir
# First, create the database in the tenant
{:ok, _db} = ChromEx.Database.create("production", tenant: "acme_corp")

# Then create collection in that tenant/database
{:ok, collection} = ChromEx.Collection.create("my_collection",
  tenant: "acme_corp",
  database: "production"
)

# All operations are scoped to the tenant/database
ChromEx.Collection.add(collection, ids: ["id1"], documents: ["Doc"])
```

### Database Management

```elixir
# Create database
{:ok, db} = ChromEx.Database.create("production", tenant: "acme_corp")

# Get database
{:ok, db} = ChromEx.Database.get("production", tenant: "acme_corp")

# Delete database
ChromEx.Database.delete("production", tenant: "acme_corp")
```

### Configuration

Configure ChromEx in your application:

```elixir
# config/config.exs
config :chromex,
  allow_reset: false,
  persist_path: "./chroma_data",
  hnsw_cache_size_mb: 1000,
  # Pool size for parallel embedding generation (defaults to CPU cores)
  embedding_pool_size: 8
```

Or configure at runtime:

```elixir
# In your application.ex
children = [
  {ChromEx.Client, [
    allow_reset: false,
    persist_path: "./chroma_data",
    hnsw_cache_size_mb: 1000
  ]},
  {ChromEx.EmbeddingsPool, [pool_size: 8]}
]
```

## Architecture

ChromEx consists of three layers:

1. **Native Layer** (`ChromEx.Native`) - Rustler NIFs interfacing with Chroma Rust code
2. **Domain Layer** (`ChromEx.Collection`, `ChromEx.Database`) - Idiomatic Elixir APIs
3. **Facade Layer** (`ChromEx`) - Top-level convenience functions

The build process:
- Cargo.toml references Chroma's Git repository
- Rust dependencies are resolved and compiled during `mix compile`
- Rustler generates NIFs loaded at runtime
- ONNX models are downloaded and cached on first use

## API Reference

### ChromEx

Core client functions:

- `heartbeat/0` - System heartbeat check
- `version/0` - Get version string
- `reset/0` - Reset all data (dangerous!)

### ChromEx.Collection

Collection and document operations:

- `create/2`, `create!/2` - Create collection
- `get/2`, `get!/2` - Get existing collection
- `delete/1`, `delete!/1` - Delete collection
- `list/1`, `list!/1` - List all collections
- `add/3`, `add!/3` - Add documents (auto-embeds if no embeddings provided)
- `query/3`, `query!/3` - Query similar documents (supports `query_texts` for auto-embedding)
- `get_documents/2`, `get_documents!/2` - Get documents by ID or filter
- `update_documents/3`, `update_documents!/3` - Update documents
- `upsert/3`, `upsert!/3` - Insert or update documents
- `delete_documents/2`, `delete_documents!/2` - Delete documents
- `count/1`, `count!/1` - Count documents

### ChromEx.Database

Database management:

- `create/2`, `create!/2` - Create database
- `get/2`, `get!/2` - Get database
- `delete/2`, `delete!/2` - Delete database

### ChromEx.Embeddings

Embedding generation (used automatically by Collection operations):

- `generate/1` - Generate embeddings for list of texts

## Performance

ChromEx uses the same embedding model as Python ChromaDB (all-MiniLM-L6-v2 via ONNX), providing:
- **384-dimensional embeddings**
- **L2-normalized vectors**
- **Identical results to Python ChromaDB**
- **Fast ONNX inference** via Ortex
- **Parallel embedding generation** via worker pool (defaults to CPU core count)

The embedding pool allows multiple embedding requests to be processed concurrently, with each worker maintaining its own model instance for maximum parallelism. Pool size automatically defaults to the number of CPU cores but can be configured via `:embedding_pool_size`.

Benchmark results show comparable performance to Python for embedding generation and query operations.

## Comparison with Python ChromaDB

ChromEx aims for API compatibility with Python ChromaDB:

| Python | Elixir |
|--------|--------|
| `client.create_collection("name")` | `ChromEx.Collection.create("name")` |
| `collection.add(ids=[...], documents=[...])` | `ChromEx.Collection.add(collection, ids: [...], documents: [...])` |
| `collection.query(query_texts=["..."], n_results=5)` | `ChromEx.Collection.query(collection, query_texts: ["..."], n_results: 5)` |
| `collection.get(ids=[...])` | `ChromEx.Collection.get_documents(collection, ids: [...])` |
| `collection.update(ids=[...], documents=[...])` | `ChromEx.Collection.update_documents(collection, ids: [...], documents: [...])` |
| `collection.delete(ids=[...])` | `ChromEx.Collection.delete_documents(collection, ids: [...])` |

## License

ChromEx is licensed under the MIT License. See [LICENSE](LICENSE) for details.

This project uses the [Chroma vector database](https://github.com/chroma-core/chroma), which is licensed under the Apache License 2.0. See [LICENSE-CHROMA](LICENSE-CHROMA) for Chroma's license terms.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Resources

- [Chroma Documentation](https://docs.trychroma.com)
- [Chroma GitHub](https://github.com/chroma-core/chroma)
- [Rustler Documentation](https://hexdocs.pm/rustler)
