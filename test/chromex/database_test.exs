defmodule ChromEx.DatabaseTest do
  use ExUnit.Case, async: false

  setup do
    database_name = "test_db_#{:rand.uniform(100000)}"

    on_exit(fn ->
      try do
        ChromEx.Database.delete(database_name)
      rescue
        _ -> :ok
      end
    end)

    %{database_name: database_name}
  end

  describe "create/2" do
    test "creates a new database", %{database_name: name} do
      assert {:ok, database} = ChromEx.Database.create(name)
      assert %ChromEx.Database{} = database
      assert database.tenant == "default_tenant"
    end

    test "create!/1 returns database directly", %{database_name: name} do
      database = ChromEx.Database.create!(name)
      assert %ChromEx.Database{} = database
    end
  end

  describe "get/2" do
    test "retrieves an existing database", %{database_name: name} do
      {:ok, _} = ChromEx.Database.create(name)
      assert {:ok, database} = ChromEx.Database.get(name)
      assert %ChromEx.Database{} = database
    end

    test "get!/1 returns database directly", %{database_name: name} do
      {:ok, _} = ChromEx.Database.create(name)
      database = ChromEx.Database.get!(name)
      assert %ChromEx.Database{} = database
    end
  end

  describe "list/1" do
    test "lists all databases" do
      assert {:ok, databases} = ChromEx.Database.list()
      assert is_list(databases)
      assert Enum.all?(databases, fn db -> %ChromEx.Database{} = db; true end)
    end

    test "list!/0 returns databases directly" do
      databases = ChromEx.Database.list!()
      assert is_list(databases)
      assert Enum.all?(databases, fn db -> %ChromEx.Database{} = db; true end)
    end
  end

  describe "delete/2" do
    test "deletes a database", %{database_name: name} do
      {:ok, _} = ChromEx.Database.create(name)
      assert :ok = ChromEx.Database.delete(name)
    end

    test "delete!/1 returns :ok", %{database_name: name} do
      {:ok, _} = ChromEx.Database.create(name)
      assert :ok = ChromEx.Database.delete!(name)
    end
  end

  describe "collections in databases" do
    test "creates collection in specific database", %{database_name: db_name} do
      {:ok, _} = ChromEx.Database.create(db_name)

      collection_name = "test_coll_#{:rand.uniform(100000)}"
      {:ok, collection} = ChromEx.Collection.create(collection_name, database: db_name)

      assert collection.database == db_name

      ChromEx.Collection.delete(collection_name, database: db_name)
    end
  end

  describe "multi-tenancy" do
    test "creates database with tenant and collection with full operations" do
      tenant = "test_tenant_#{:rand.uniform(100000)}"
      db_name = "test_db_#{:rand.uniform(100000)}"
      collection_name = "test_coll_#{:rand.uniform(100000)}"

      # First, create the database in the tenant
      {:ok, db} = ChromEx.Database.create(db_name, tenant: tenant)
      assert %ChromEx.Database{} = db
      assert db.tenant == tenant

      # Then create collection in that tenant/database
      {:ok, collection} =
        ChromEx.Collection.create(collection_name, tenant: tenant, database: db_name)

      assert collection.tenant == tenant
      assert collection.database == db_name

      # Add documents with auto-embedding
      ChromEx.Collection.add(collection, ids: ["id1"], documents: ["Test document"])

      # Query to verify it works
      {:ok, results} =
        ChromEx.Collection.query(collection, query_texts: ["Test"], n_results: 1)

      assert results["ids"] == [["id1"]]

      # Cleanup
      ChromEx.Collection.delete(collection_name, tenant: tenant, database: db_name)
      ChromEx.Database.delete(db_name, tenant: tenant)
    end
  end
end
