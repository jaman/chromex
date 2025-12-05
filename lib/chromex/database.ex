defmodule ChromEx.Database do
  @moduledoc """
  ChromEx database operations for managing databases within tenants
  """

  alias ChromEx.{Client, Native}

  defstruct [:id, :name, :tenant]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          tenant: String.t()
        }

  @default_tenant "default_tenant"

  @doc """
  Creates a new database
  """
  @spec create(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(name, opts \\ []) do
    resource = Client.get_resource()
    tenant = Keyword.get(opts, :tenant, @default_tenant)

    case Native.create_database(resource, name, tenant) do
      json when is_binary(json) ->
        database_data = Jason.decode!(json)

        {:ok,
         %__MODULE__{
           id: database_data["id"],
           name: database_data["name"],
           tenant: Map.get(database_data, "tenant", tenant)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves database information
  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def get(name, opts \\ []) do
    resource = Client.get_resource()
    tenant = Keyword.get(opts, :tenant, @default_tenant)

    case Native.get_database(resource, name, tenant) do
      json when is_binary(json) ->
        database_data = Jason.decode!(json)

        {:ok,
         %__MODULE__{
           id: database_data["id"],
           name: database_data["name"],
           tenant: Map.get(database_data, "tenant", tenant)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a database
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(name, opts \\ []) do
    resource = Client.get_resource()
    tenant = Keyword.get(opts, :tenant, @default_tenant)

    case Native.delete_database(resource, name, tenant) do
      "ok" -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all databases
  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, term()}
  def list(opts \\ []) do
    resource = Client.get_resource()
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset)
    tenant = Keyword.get(opts, :tenant, @default_tenant)

    case Native.list_databases(resource, limit, offset, tenant) do
      json when is_binary(json) ->
        databases =
          Jason.decode!(json)
          |> Enum.map(fn database_data ->
            %__MODULE__{
              id: database_data["id"],
              name: database_data["name"],
              tenant: Map.get(database_data, "tenant", tenant)
            }
          end)

        {:ok, databases}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new database, raising on error
  """
  @spec create!(String.t(), keyword()) :: t()
  def create!(name, opts \\ []) do
    case create(name, opts) do
      {:ok, database} -> database
      {:error, reason} -> raise "Failed to create database: #{inspect(reason)}"
    end
  end

  @doc """
  Retrieves database information, raising on error
  """
  @spec get!(String.t(), keyword()) :: t()
  def get!(name, opts \\ []) do
    case get(name, opts) do
      {:ok, database} -> database
      {:error, reason} -> raise "Failed to get database: #{inspect(reason)}"
    end
  end

  @doc """
  Deletes a database, raising on error
  """
  @spec delete!(String.t(), keyword()) :: :ok
  def delete!(name, opts \\ []) do
    case delete(name, opts) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to delete database: #{inspect(reason)}"
    end
  end

  @doc """
  Lists all databases, raising on error
  """
  @spec list!(keyword()) :: [t()]
  def list!(opts \\ []) do
    case list(opts) do
      {:ok, databases} -> databases
      {:error, reason} -> raise "Failed to list databases: #{inspect(reason)}"
    end
  end
end
