defmodule ChromEx.Embeddings do
  @moduledoc """
  Auto-generates embeddings using the same ONNX model as Python ChromaDB.

  This module provides a simple API for generating embeddings. Internally, it uses
  a pool of workers for parallel processing, with pool size defaulting to the number
  of CPU cores.

  ## Configuration

  You can configure the pool size in your config.exs:

      config :chromex, embedding_pool_size: 8

  ## Examples

      ChromEx.Embeddings.generate(["Hello world", "Goodbye world"])
      #=> [[0.1, 0.2, ...], [0.3, 0.4, ...]]
  """

  @doc """
  Generates embeddings for a list of texts using all-MiniLM-L6-v2 ONNX model.

  Returns a list of 384-dimensional embedding vectors, one for each input text.
  Embeddings are L2-normalized and suitable for semantic similarity search.

  This function uses a pool of workers for parallel processing, allowing multiple
  embedding requests to be processed concurrently.

  ## Examples

      ChromEx.Embeddings.generate(["Hello world", "Goodbye world"])
      #=> [[0.1, 0.2, ...], [0.3, 0.4, ...]]
  """
  @spec generate([String.t()]) :: [[float()]]
  def generate(texts) when is_list(texts) do
    ChromEx.EmbeddingsPool.generate(texts)
  end
end
