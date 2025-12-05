defmodule ChromEx.Client do
  @moduledoc """
  ChromEx client that manages the Chroma bindings resource lifecycle
  """

  use GenServer

  alias ChromEx.Native

  defstruct [:resource, :persist_path, :allow_reset, :hnsw_cache_size]

  @type t :: %__MODULE__{
          resource: reference(),
          persist_path: String.t() | nil,
          allow_reset: boolean(),
          hnsw_cache_size: non_neg_integer()
        }

  @default_cache_size_mb 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes a new Chroma client with specified configuration
  """
  @spec init(keyword()) :: {:ok, t()} | {:error, term()}
  def init(opts) do
    allow_reset = Keyword.get(opts, :allow_reset, false)
    persist_path = Keyword.get(opts, :persist_path)
    hnsw_cache_size = Keyword.get(opts, :hnsw_cache_size_mb, @default_cache_size_mb)

    case Native.init(allow_reset, persist_path, hnsw_cache_size) do
      resource when is_reference(resource) ->
        {:ok,
         %__MODULE__{
           resource: resource,
           persist_path: persist_path,
           allow_reset: allow_reset,
           hnsw_cache_size: hnsw_cache_size
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc """
  Gets the client resource for direct NIF calls
  """
  @spec get_resource() :: reference() | nil
  def get_resource do
    GenServer.call(__MODULE__, :get_resource)
  end

  @doc """
  Gets maximum batch size for operations
  """
  @spec max_batch_size() :: non_neg_integer()
  def max_batch_size do
    GenServer.call(__MODULE__, :max_batch_size)
  end

  def handle_call(:get_resource, _from, %__MODULE__{resource: resource} = state) do
    {:reply, resource, state}
  end

  def handle_call(:max_batch_size, _from, %__MODULE__{resource: resource} = state) do
    result = Native.get_max_batch_size(resource)
    {:reply, result, state}
  end
end
