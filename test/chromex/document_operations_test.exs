defmodule ChromEx.DocumentOperationsTest do
  use ExUnit.Case, async: false

  setup do
    collection_name = "test_docs_#{:rand.uniform(100000)}"
    {:ok, collection} = ChromEx.Collection.create(collection_name)

    on_exit(fn ->
      try do
        ChromEx.Collection.delete(collection_name)
      rescue
        _ -> :ok
      end
    end)

    %{collection: collection}
  end

  describe "add/3" do
    test "adds documents with auto-generated embeddings", %{collection: collection} do
      assert :ok = ChromEx.Collection.add(collection,
        ids: ["doc1", "doc2"],
        documents: ["First document", "Second document"]
      )

      assert {:ok, 2} = ChromEx.Collection.count(collection)
    end

    test "adds documents with pre-computed embeddings", %{collection: collection} do
      embeddings = ChromEx.Embeddings.generate(["Test doc"])

      assert :ok = ChromEx.Collection.add(collection,
        ids: ["doc1"],
        embeddings: embeddings,
        documents: ["Test doc"]
      )

      assert {:ok, 1} = ChromEx.Collection.count(collection)
    end

    test "adds documents with metadata as maps", %{collection: collection} do
      assert :ok = ChromEx.Collection.add(collection,
        ids: ["doc1"],
        documents: ["Test doc"],
        metadatas: [%{source: "test", year: 2024}]
      )

      {:ok, docs} = ChromEx.Collection.get_documents(collection, ids: ["doc1"])
      assert hd(docs["metadatas"])["source"] == "test"
    end

    test "adds documents with metadata as keyword lists", %{collection: collection} do
      assert :ok = ChromEx.Collection.add(collection,
        ids: ["doc1"],
        documents: ["Test doc"],
        metadatas: [[source: "test", year: 2024]]
      )

      {:ok, docs} = ChromEx.Collection.get_documents(collection, ids: ["doc1"])
      assert hd(docs["metadatas"])["source"] == "test"
    end

    test "supports positional IDs syntax", %{collection: collection} do
      assert :ok = ChromEx.Collection.add(collection, ["doc1", "doc2"],
        documents: ["First", "Second"]
      )

      assert {:ok, 2} = ChromEx.Collection.count(collection)
    end

    test "add!/3 returns :ok directly", %{collection: collection} do
      assert :ok = ChromEx.Collection.add!(collection,
        ids: ["doc1"],
        documents: ["Test"]
      )
    end
  end

  describe "get_documents/2" do
    setup %{collection: collection} do
      ChromEx.Collection.add(collection,
        ids: ["doc1", "doc2", "doc3"],
        documents: ["First", "Second", "Third"],
        metadatas: [%{type: "a"}, %{type: "b"}, %{type: "a"}]
      )

      :ok
    end

    test "retrieves documents by IDs", %{collection: collection} do
      assert {:ok, docs} = ChromEx.Collection.get_documents(collection,
        ids: ["doc1", "doc2"]
      )

      assert length(docs["ids"]) == 2
      assert "doc1" in docs["ids"]
      assert "doc2" in docs["ids"]
    end

    test "retrieves all documents when no filter specified", %{collection: collection} do
      assert {:ok, docs} = ChromEx.Collection.get_documents(collection)
      assert length(docs["ids"]) == 3
    end

    test "get_documents!/2 returns documents directly", %{collection: collection} do
      docs = ChromEx.Collection.get_documents!(collection, ids: ["doc1"])
      assert length(docs["ids"]) == 1
    end
  end

  describe "update_documents/3" do
    setup %{collection: collection} do
      ChromEx.Collection.add(collection,
        ids: ["doc1"],
        documents: ["Original"]
      )

      :ok
    end

    test "updates document content", %{collection: collection} do
      assert :ok = ChromEx.Collection.update_documents(collection, ["doc1"],
        documents: ["Updated"]
      )

      {:ok, docs} = ChromEx.Collection.get_documents(collection, ids: ["doc1"])
      assert hd(docs["documents"]) == "Updated"
    end

    test "update_documents!/3 returns :ok directly", %{collection: collection} do
      assert :ok = ChromEx.Collection.update_documents!(collection, ["doc1"],
        documents: ["Updated"]
      )
    end
  end

  describe "delete_documents/2" do
    setup %{collection: collection} do
      ChromEx.Collection.add(collection,
        ids: ["doc1", "doc2", "doc3"],
        documents: ["First", "Second", "Third"]
      )

      :ok
    end

    test "deletes documents by IDs", %{collection: collection} do
      assert :ok = ChromEx.Collection.delete_documents(collection, ids: ["doc1"])
      assert {:ok, 2} = ChromEx.Collection.count(collection)

      {:ok, docs} = ChromEx.Collection.get_documents(collection)
      refute "doc1" in docs["ids"]
    end

    test "delete_documents!/2 returns :ok directly", %{collection: collection} do
      assert :ok = ChromEx.Collection.delete_documents!(collection, ids: ["doc2"])
      assert {:ok, 2} = ChromEx.Collection.count(collection)
    end
  end
end
