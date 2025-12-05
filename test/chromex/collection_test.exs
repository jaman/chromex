defmodule ChromEx.CollectionTest do
  use ExUnit.Case, async: false

  setup do
    collection_name = "test_collection_#{:rand.uniform(100000)}"
    on_exit(fn -> cleanup_collection(collection_name) end)
    %{collection_name: collection_name}
  end

  defp cleanup_collection(name) do
    try do
      ChromEx.Collection.delete(name)
    rescue
      _ -> :ok
    end
  end

  describe "create/2" do
    test "creates a new collection", %{collection_name: name} do
      assert {:ok, collection} = ChromEx.Collection.create(name)
      assert collection.name == name
      assert collection.tenant == "default_tenant"
      assert collection.database == "default_database"
    end

    test "creates collection with get_or_create option", %{collection_name: name} do
      assert {:ok, collection1} = ChromEx.Collection.create(name, get_or_create: true)
      assert {:ok, collection2} = ChromEx.Collection.create(name, get_or_create: true)
      assert collection1.id == collection2.id
    end

    test "create!/1 returns collection directly", %{collection_name: name} do
      collection = ChromEx.Collection.create!(name)
      assert collection.name == name
    end
  end

  describe "get/2" do
    test "retrieves an existing collection", %{collection_name: name} do
      {:ok, _} = ChromEx.Collection.create(name)
      assert {:ok, collection} = ChromEx.Collection.get(name)
      assert collection.name == name
    end

    test "returns error for non-existent collection" do
      assert {:error, _} = ChromEx.Collection.get("nonexistent_collection_xyz")
    end

    test "get!/1 returns collection directly", %{collection_name: name} do
      {:ok, _} = ChromEx.Collection.create(name)
      collection = ChromEx.Collection.get!(name)
      assert collection.name == name
    end
  end

  describe "list/1" do
    test "lists all collections", %{collection_name: name} do
      {:ok, _} = ChromEx.Collection.create(name)
      assert {:ok, collections} = ChromEx.Collection.list()
      assert is_list(collections)
      assert Enum.any?(collections, fn c -> c.name == name end)
    end

    test "list!/0 returns collections directly", %{collection_name: name} do
      {:ok, _} = ChromEx.Collection.create(name)
      collections = ChromEx.Collection.list!()
      assert is_list(collections)
    end
  end

  describe "delete/2" do
    test "deletes a collection", %{collection_name: name} do
      {:ok, _} = ChromEx.Collection.create(name)
      assert :ok = ChromEx.Collection.delete(name)
      assert {:error, _} = ChromEx.Collection.get(name)
    end

    test "delete!/1 returns :ok", %{collection_name: name} do
      {:ok, _} = ChromEx.Collection.create(name)
      assert :ok = ChromEx.Collection.delete!(name)
    end
  end

  describe "count/1" do
    test "counts documents in collection", %{collection_name: name} do
      {:ok, collection} = ChromEx.Collection.create(name)
      assert {:ok, 0} = ChromEx.Collection.count(collection)

      ChromEx.Collection.add(collection,
        ids: ["id1", "id2"],
        documents: ["doc1", "doc2"]
      )

      assert {:ok, 2} = ChromEx.Collection.count(collection)
    end

    test "count!/1 returns count directly", %{collection_name: name} do
      {:ok, collection} = ChromEx.Collection.create(name)
      assert 0 = ChromEx.Collection.count!(collection)
    end
  end
end
