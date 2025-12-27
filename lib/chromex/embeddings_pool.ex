defmodule ChromEx.EmbeddingsPool do
  @moduledoc """
  NimblePool-based pool of EmbeddingsWorker processes for parallel embedding generation.

  Pool size defaults to CPU core count for optimal parallelism.
  """

  @behaviour NimblePool

  @doc """
  Starts the embeddings pool with the given options.

  ## Options

    * `:pool_size` - Number of worker processes (default: System.schedulers_online())
  """
  def child_spec(opts) do
    pool_size = Keyword.get(opts, :pool_size, System.schedulers_online())

    %{
      id: __MODULE__,
      start: {NimblePool, :start_link, [pool_worker_spec(pool_size)]},
      type: :worker
    }
  end

  defp pool_worker_spec(pool_size) do
    [
      worker: {__MODULE__, []},
      name: __MODULE__,
      pool_size: pool_size
    ]
  end

  @doc """
  Generates embeddings using a worker from the pool.

  Returns a list of 384-dimensional embedding vectors, one for each input text.
  """
  @spec generate([String.t()]) :: [[float()]]
  def generate(texts) when is_list(texts) do
    NimblePool.checkout!(
      __MODULE__,
      :checkout,
      fn _from, worker ->
        result = ChromEx.EmbeddingsWorker.generate(worker, texts)
        {result, worker}
      end,
      60_000
    )
  end

  # NimblePool callbacks

  @impl NimblePool
  def init_pool(_opts) do
    {:ok, nil}
  end

  @impl NimblePool
  def init_worker(_pool_state) do
    {:ok, worker} = ChromEx.EmbeddingsWorker.start_link([])
    {:ok, worker, nil}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, worker, pool_state) do
    {:ok, worker, worker, pool_state}
  end

  @impl NimblePool
  def handle_checkin(_client_state, _from, worker, pool_state) do
    {:ok, worker, pool_state}
  end

  @impl NimblePool
  def terminate_worker(_reason, worker, pool_state) do
    Process.exit(worker, :shutdown)
    {:ok, pool_state}
  end
end
