defmodule ChromEx.Collection do
  @moduledoc """
  ChromEx collection operations for document storage and retrieval
  """

  alias ChromEx.{Client, Native}

  defstruct [:id, :name, :tenant, :database, :metadata, :configuration]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          tenant: String.t(),
          database: String.t(),
          metadata: map() | nil,
          configuration: map() | nil
        }

  @default_tenant "default_tenant"
  @default_database "default_database"

  @doc """
  Creates a new collection
  """
  @spec create(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(name, opts \\ []) do
    resource = Client.get_resource()
    config = Keyword.get(opts, :configuration)
    metadata = Keyword.get(opts, :metadata)
    get_or_create = Keyword.get(opts, :get_or_create, true)
    tenant = Keyword.get(opts, :tenant, @default_tenant)
    database = Keyword.get(opts, :database, @default_database)

    config_json = if config, do: Jason.encode!(config), else: nil
    metadata_json = if metadata, do: Jason.encode!(metadata), else: nil

    case Native.create_collection(
           resource,
           name,
           config_json,
           metadata_json,
           get_or_create,
           tenant,
           database
         ) do
      json when is_binary(json) ->
        collection_data = Jason.decode!(json)

        {:ok,
         %__MODULE__{
           id: collection_data["id"],
           name: collection_data["name"],
           tenant: Map.get(collection_data, "tenant", tenant),
           database: Map.get(collection_data, "database", database),
           metadata: collection_data["metadata"],
           configuration: collection_data["configuration"]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new collection, raising on error
  """
  @spec create!(String.t(), keyword()) :: t()
  def create!(name, opts \\ []) do
    case create(name, opts) do
      {:ok, collection} -> collection
      {:error, reason} -> raise "Failed to create collection: #{inspect(reason)}"
    end
  end

  @doc """
  Retrieves an existing collection by name, raising on error
  """
  @spec get!(String.t(), keyword()) :: t()
  def get!(name, opts \\ []) do
    case get(name, opts) do
      {:ok, collection} -> collection
      {:error, reason} -> raise "Failed to get collection: #{inspect(reason)}"
    end
  end

  @doc """
  Retrieves an existing collection by name
  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def get(name, opts \\ []) do
    resource = Client.get_resource()
    tenant = Keyword.get(opts, :tenant, @default_tenant)
    database = Keyword.get(opts, :database, @default_database)

    case Native.get_collection(resource, name, tenant, database) do
      json when is_binary(json) ->
        collection_data = Jason.decode!(json)

        {:ok,
         %__MODULE__{
           id: collection_data["id"],
           name: collection_data["name"],
           tenant: Map.get(collection_data, "tenant", tenant),
           database: Map.get(collection_data, "database", database),
           metadata: collection_data["metadata"],
           configuration: collection_data["configuration"]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates an existing collection
  """
  @spec update(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = collection, opts) do
    resource = Client.get_resource()
    new_name = Keyword.get(opts, :name)
    new_metadata = Keyword.get(opts, :metadata)
    new_configuration = Keyword.get(opts, :configuration)

    new_metadata_json = if new_metadata, do: Jason.encode!(new_metadata), else: nil
    new_config_json = if new_configuration, do: Jason.encode!(new_configuration), else: nil

    case Native.update_collection(
           resource,
           collection.id,
           new_name,
           new_metadata_json,
           new_config_json
         ) do
      :ok ->
        updated = %__MODULE__{
          collection
          | name: new_name || collection.name,
            metadata: new_metadata || collection.metadata,
            configuration: new_configuration || collection.configuration
        }

        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a collection, raising on error
  """
  @spec delete!(String.t(), keyword()) :: :ok
  def delete!(name, opts \\ []) do
    case delete(name, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to delete collection: #{inspect(reason)}"
    end
  end

  @doc """
  Deletes a collection
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(name, opts \\ []) do
    resource = Client.get_resource()
    tenant = Keyword.get(opts, :tenant, @default_tenant)
    database = Keyword.get(opts, :database, @default_database)

    case Native.delete_collection(resource, name, tenant, database) do
      "ok" -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all collections, raising on error
  """
  @spec list!(keyword()) :: [t()]
  def list!(opts \\ []) do
    case list(opts) do
      {:ok, collections} -> collections
      {:error, reason} -> raise "Failed to list collections: #{inspect(reason)}"
    end
  end

  @doc """
  Lists all collections
  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, term()}
  def list(opts \\ []) do
    resource = Client.get_resource()
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset)
    tenant = Keyword.get(opts, :tenant, @default_tenant)
    database = Keyword.get(opts, :database, @default_database)

    case Native.list_collections(resource, limit, offset, tenant, database) do
      json when is_binary(json) ->
        collections =
          Jason.decode!(json)
          |> Enum.map(fn collection_data ->
            %__MODULE__{
              id: collection_data["id"],
              name: collection_data["name"],
              tenant: Map.get(collection_data, "tenant", tenant),
              database: Map.get(collection_data, "database", database),
              metadata: collection_data["metadata"],
              configuration: collection_data["configuration"]
            }
          end)

        {:ok, collections}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Counts all collections
  """
  @spec count_all(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_all(opts \\ []) do
    resource = Client.get_resource()
    tenant = Keyword.get(opts, :tenant, @default_tenant)
    database = Keyword.get(opts, :database, @default_database)

    case Native.count_collections(resource, tenant, database) do
      count when is_integer(count) -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Adds documents to a collection

  ## Examples

      # Positional IDs
      ChromEx.Collection.add(collection, ["id1", "id2"],
        embeddings: [[0.1, 0.2], [0.3, 0.4]],
        documents: ["doc1", "doc2"],
        metadatas: [%{key: "val"}, [key: "val"]]
      )

      # Keyword-based IDs (Python-style)
      ChromEx.Collection.add(collection,
        ids: ["id1", "id2"],
        embeddings: [[0.1, 0.2], [0.3, 0.4]],
        documents: ["doc1", "doc2"]
      )
  """
  @spec add(t(), [String.t()] | keyword(), keyword()) :: :ok | {:error, term()}
  def add(%__MODULE__{} = collection, ids_or_opts, opts \\ []) do
    cond do
      is_list(ids_or_opts) and Keyword.keyword?(ids_or_opts) ->
        add_impl(collection, Keyword.merge(ids_or_opts, opts))
      is_list(ids_or_opts) ->
        add_impl(collection, Keyword.put(opts, :ids, ids_or_opts))
      true ->
        raise ArgumentError, "Expected list of IDs or keyword list"
    end
  end

  defp add_impl(%__MODULE__{} = collection, opts) do
    resource = Client.get_resource()
    ids = Keyword.get(opts, :ids) || raise ArgumentError, "ids are required"
    documents = Keyword.get(opts, :documents)
    metadatas = Keyword.get(opts, :metadatas)
    uris = Keyword.get(opts, :uris)

    embeddings =
      case Keyword.get(opts, :embeddings) do
        nil ->
          if documents do
            ChromEx.Embeddings.generate(documents)
          else
            raise ArgumentError, "Either embeddings or documents must be provided"
          end

        provided_embeddings ->
          provided_embeddings
      end

    metadatas_json =
      if metadatas do
        Enum.map(metadatas, fn
          nil -> nil
          meta when is_map(meta) -> Jason.encode!(meta)
          meta when is_list(meta) -> Jason.encode!(Map.new(meta))
        end)
      end

    case Native.add(
           resource,
           ids,
           collection.id,
           embeddings,
           metadatas_json,
           documents,
           uris,
           collection.tenant,
           collection.database
         ) do
      "ok" -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Adds documents to a collection, raising on error
  """
  @spec add!(t(), [String.t()] | keyword(), keyword()) :: :ok
  def add!(collection, ids_or_opts, opts \\ []) do
    case add(collection, ids_or_opts, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to add documents: #{inspect(reason)}"
    end
  end

  @doc """
  Queries a collection for similar documents, raising on error

  ## Examples

      results = ChromEx.Collection.query!(collection,
        query_texts: ["search query"],
        n_results: 5
      )
  """
  @spec query!(t(), [[float()]] | keyword(), keyword()) :: map()
  def query!(collection, query_embeddings_or_opts, opts \\ []) do
    case query(collection, query_embeddings_or_opts, opts) do
      {:ok, results} -> results
      {:error, reason} -> raise "Failed to query collection: #{inspect(reason)}"
    end
  end

  @doc """
  Queries a collection for similar documents

  ## Examples

      # With query texts (auto-generates embeddings)
      ChromEx.Collection.query(collection,
        query_texts: ["search query"],
        n_results: 5
      )

      # With pre-computed embeddings
      ChromEx.Collection.query(collection, [[0.1, 0.2, ...]],
        n_results: 5
      )
  """
  @spec query(t(), [[float()]] | keyword(), keyword()) :: {:ok, map()} | {:error, term()}
  def query(collection, query_embeddings_or_opts, opts \\ [])

  def query(%__MODULE__{} = collection, query_embeddings, opts) when is_list(query_embeddings) and is_list(hd(query_embeddings)) and is_number(hd(hd(query_embeddings))) do
    query_impl(collection, query_embeddings, opts)
  end

  def query(%__MODULE__{} = collection, opts, _opts2) when is_list(opts) and is_tuple(hd(opts)) do
    query_texts = Keyword.get(opts, :query_texts)

    query_embeddings =
      if query_texts do
        ChromEx.Embeddings.generate(query_texts)
      else
        raise ArgumentError, "Either provide query_embeddings as second argument or query_texts in options"
      end

    query_impl(collection, query_embeddings, opts)
  end

  defp query_impl(%__MODULE__{} = collection, query_embeddings, opts) do
    resource = Client.get_resource()
    n_results = Keyword.get(opts, :n_results, 10)
    where = Keyword.get(opts, :where)
    where_document = Keyword.get(opts, :where_document)
    include = Keyword.get(opts, :include, ["metadatas", "documents", "distances"])

    where_json = if where, do: Jason.encode!(where), else: nil
    where_document_json = if where_document, do: Jason.encode!(where_document), else: nil

    case Native.query(
           resource,
           collection.id,
           query_embeddings,
           n_results,
           where_json,
           where_document_json,
           include,
           collection.tenant,
           collection.database
         ) do
      json when is_binary(json) -> {:ok, Jason.decode!(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves documents from a collection, raising on error
  """
  @spec get_documents!(t(), keyword()) :: map()
  def get_documents!(%__MODULE__{} = collection, opts \\ []) do
    case get_documents(collection, opts) do
      {:ok, docs} -> docs
      {:error, reason} -> raise "Failed to get documents: #{inspect(reason)}"
    end
  end

  @doc """
  Retrieves documents from a collection
  """
  @spec get_documents(t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_documents(%__MODULE__{} = collection, opts \\ []) do
    resource = Client.get_resource()
    ids = Keyword.get(opts, :ids)
    where = Keyword.get(opts, :where)
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset)
    where_document = Keyword.get(opts, :where_document)
    include = Keyword.get(opts, :include, ["metadatas", "documents"])

    where_json = if where, do: Jason.encode!(where), else: nil
    where_document_json = if where_document, do: Jason.encode!(where_document), else: nil

    case Native.get(
           resource,
           collection.id,
           ids,
           where_json,
           limit,
           offset,
           where_document_json,
           include,
           collection.tenant,
           collection.database
         ) do
      json when is_binary(json) -> {:ok, Jason.decode!(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates documents in a collection, raising on error
  """
  @spec update_documents!(t(), [String.t()], keyword()) :: :ok
  def update_documents!(%__MODULE__{} = collection, ids, opts \\ []) do
    case update_documents(collection, ids, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to update documents: #{inspect(reason)}"
    end
  end

  @doc """
  Updates documents in a collection
  """
  @spec update_documents(t(), [String.t()], keyword()) :: :ok | {:error, term()}
  def update_documents(%__MODULE__{} = collection, ids, opts \\ []) do
    resource = Client.get_resource()
    embeddings = Keyword.get(opts, :embeddings)
    metadatas = Keyword.get(opts, :metadatas)
    documents = Keyword.get(opts, :documents)
    uris = Keyword.get(opts, :uris)

    metadatas_json =
      if metadatas do
        Enum.map(metadatas, fn
          nil -> nil
          meta when is_map(meta) -> Jason.encode!(meta)
        end)
      end

    case Native.update(
           resource,
           collection.id,
           ids,
           embeddings,
           metadatas_json,
           documents,
           uris,
           collection.tenant,
           collection.database
         ) do
      "ok" -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Upserts documents in a collection, raising on error
  """
  @spec upsert!(t(), [String.t()], keyword()) :: :ok
  def upsert!(%__MODULE__{} = collection, ids, opts \\ []) do
    case upsert(collection, ids, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to upsert documents: #{inspect(reason)}"
    end
  end

  @doc """
  Upserts documents in a collection
  """
  @spec upsert(t(), [String.t()], keyword()) :: :ok | {:error, term()}
  def upsert(%__MODULE__{} = collection, ids, opts \\ []) do
    resource = Client.get_resource()
    embeddings = Keyword.get(opts, :embeddings)
    metadatas = Keyword.get(opts, :metadatas)
    documents = Keyword.get(opts, :documents)
    uris = Keyword.get(opts, :uris)

    metadatas_json =
      if metadatas do
        Enum.map(metadatas, fn
          nil -> nil
          meta when is_map(meta) -> Jason.encode!(meta)
        end)
      end

    case Native.upsert(
           resource,
           collection.id,
           ids,
           embeddings,
           metadatas_json,
           documents,
           uris,
           collection.tenant,
           collection.database
         ) do
      "ok" -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes documents from a collection, raising on error
  """
  @spec delete_documents!(t(), keyword()) :: :ok
  def delete_documents!(%__MODULE__{} = collection, opts \\ []) do
    case delete_documents(collection, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to delete documents: #{inspect(reason)}"
    end
  end

  @doc """
  Deletes documents from a collection
  """
  @spec delete_documents(t(), keyword()) :: :ok | {:error, term()}
  def delete_documents(%__MODULE__{} = collection, opts \\ []) do
    resource = Client.get_resource()
    ids = Keyword.get(opts, :ids)
    where = Keyword.get(opts, :where)
    where_document = Keyword.get(opts, :where_document)

    where_json = if where, do: Jason.encode!(where), else: nil
    where_document_json = if where_document, do: Jason.encode!(where_document), else: nil

    case Native.delete(
           resource,
           collection.id,
           ids,
           where_json,
           where_document_json,
           collection.tenant,
           collection.database
         ) do
      "ok" -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Counts documents in a collection, raising on error
  """
  @spec count!(t()) :: non_neg_integer()
  def count!(%__MODULE__{} = collection) do
    case count(collection) do
      {:ok, count} -> count
      {:error, reason} -> raise "Failed to count documents: #{inspect(reason)}"
    end
  end

  @doc """
  Counts documents in a collection
  """
  @spec count(t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(%__MODULE__{} = collection) do
    resource = Client.get_resource()

    case Native.count(resource, collection.id, collection.tenant, collection.database) do
      count when is_integer(count) -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end
end
