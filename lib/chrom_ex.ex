defmodule ChromEx do
  @moduledoc """
  Elixir bindings for Chroma vector database via native Rust integration
  """

  alias ChromEx.{Client, Collection, Database, Native}

  @doc """
  Starts the ChromEx client with configuration options
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Client.start_link(opts)
  end

  @doc """
  Returns current system heartbeat as nanoseconds since epoch
  """
  @spec heartbeat() :: integer()
  def heartbeat do
    Native.heartbeat()
  end

  @doc """
  Returns ChromEx version string
  """
  @spec version() :: String.t()
  def version do
    Native.get_version()
  end

  @doc """
  Returns maximum batch size for operations
  """
  @spec max_batch_size() :: non_neg_integer()
  def max_batch_size do
    Client.max_batch_size()
  end

  @doc """
  Resets all data in the database
  """
  @spec reset() :: :ok | {:error, term()}
  def reset do
    resource = Client.get_resource()

    case Native.reset(resource) do
      "ok" -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a new collection
  """
  defdelegate create_collection(name, opts \\ []), to: Collection, as: :create

  @doc """
  Gets an existing collection
  """
  defdelegate get_collection(name, opts \\ []), to: Collection, as: :get

  @doc """
  Deletes a collection
  """
  defdelegate delete_collection(name, opts \\ []), to: Collection, as: :delete

  @doc """
  Lists all collections
  """
  defdelegate list_collections(opts \\ []), to: Collection, as: :list

  @doc """
  Creates a new database
  """
  defdelegate create_database(name, opts \\ []), to: Database, as: :create

  @doc """
  Gets database information
  """
  defdelegate get_database(name, opts \\ []), to: Database, as: :get

  @doc """
  Deletes a database
  """
  defdelegate delete_database(name, opts \\ []), to: Database, as: :delete

  @doc """
  Lists all databases
  """
  defdelegate list_databases(opts \\ []), to: Database, as: :list
end
