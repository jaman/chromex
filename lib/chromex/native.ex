defmodule ChromEx.Native do
  @moduledoc false

  use Rustler,
    otp_app: :chromex,
    crate: "chromex_native"

  def init(_allow_reset, _persist_path, _hnsw_cache_size),
    do: :erlang.nif_error(:nif_not_loaded)

  def heartbeat(), do: :erlang.nif_error(:nif_not_loaded)
  def get_version(), do: :erlang.nif_error(:nif_not_loaded)
  def get_max_batch_size(_resource), do: :erlang.nif_error(:nif_not_loaded)

  def create_collection(
        _resource,
        _name,
        _config,
        _metadata,
        _get_or_create,
        _tenant,
        _database
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def get_collection(_resource, _name, _tenant, _database),
    do: :erlang.nif_error(:nif_not_loaded)

  def delete_collection(_resource, _name, _tenant, _database),
    do: :erlang.nif_error(:nif_not_loaded)

  def list_collections(_resource, _limit, _offset, _tenant, _database),
    do: :erlang.nif_error(:nif_not_loaded)

  def count_collections(_resource, _tenant, _database),
    do: :erlang.nif_error(:nif_not_loaded)

  def update_collection(_resource, _collection_id, _new_name, _new_metadata, _new_config),
    do: :erlang.nif_error(:nif_not_loaded)

  def add(
        _resource,
        _ids,
        _collection_id,
        _embeddings,
        _metadatas,
        _documents,
        _uris,
        _tenant,
        _database
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def query(
        _resource,
        _collection_id,
        _query_embeddings,
        _n_results,
        _where,
        _where_document,
        _include,
        _tenant,
        _database
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def get(
        _resource,
        _collection_id,
        _ids,
        _where,
        _limit,
        _offset,
        _where_document,
        _include,
        _tenant,
        _database
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def update(
        _resource,
        _collection_id,
        _ids,
        _embeddings,
        _metadatas,
        _documents,
        _uris,
        _tenant,
        _database
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def upsert(
        _resource,
        _collection_id,
        _ids,
        _embeddings,
        _metadatas,
        _documents,
        _uris,
        _tenant,
        _database
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def delete(_resource, _collection_id, _ids, _where, _where_document, _tenant, _database),
    do: :erlang.nif_error(:nif_not_loaded)

  def count(_resource, _collection_id, _tenant, _database),
    do: :erlang.nif_error(:nif_not_loaded)

  def create_database(_resource, _name, _tenant), do: :erlang.nif_error(:nif_not_loaded)
  def get_database(_resource, _name, _tenant), do: :erlang.nif_error(:nif_not_loaded)
  def delete_database(_resource, _name, _tenant), do: :erlang.nif_error(:nif_not_loaded)
  def list_databases(_resource, _limit, _offset, _tenant), do: :erlang.nif_error(:nif_not_loaded)

  def create_tenant(_resource, _name), do: :erlang.nif_error(:nif_not_loaded)
  def get_tenant(_resource, _name), do: :erlang.nif_error(:nif_not_loaded)

  def reset(_resource), do: :erlang.nif_error(:nif_not_loaded)
end
