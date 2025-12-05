defmodule ChromEx.QueryTest do
  use ExUnit.Case, async: false

  setup do
    collection_name = "test_query_#{:rand.uniform(100000)}"
    {:ok, collection} = ChromEx.Collection.create(collection_name)

    ChromEx.Collection.add(collection,
      ids: ["doc1", "doc2", "doc3"],
      documents: [
        "Cats are wonderful pets",
        "Dogs are loyal companions",
        "Birds can fly high"
      ],
      metadatas: [
        %{animal: "cat", year: 2024},
        %{animal: "dog", year: 2023},
        %{animal: "bird", year: 2024}
      ]
    )

    on_exit(fn ->
      try do
        ChromEx.Collection.delete(collection_name)
      rescue
        _ -> :ok
      end
    end)

    %{collection: collection}
  end

  describe "query/3 with query_texts" do
    test "queries with auto-generated embeddings", %{collection: collection} do
      assert {:ok, results} = ChromEx.Collection.query(collection,
        query_texts: ["cats"],
        n_results: 2
      )

      assert is_map(results)
      assert Map.has_key?(results, "ids")
      assert Map.has_key?(results, "distances")
      assert Map.has_key?(results, "documents")
      assert Map.has_key?(results, "metadatas")

      assert length(hd(results["ids"])) <= 2
    end

    test "query!/3 returns results directly", %{collection: collection} do
      results = ChromEx.Collection.query!(collection,
        query_texts: ["dogs"],
        n_results: 1
      )

      assert is_map(results)
      assert length(hd(results["ids"])) == 1
    end
  end

  describe "query/3 with pre-computed embeddings" do
    test "queries with provided embeddings", %{collection: collection} do
      [query_embedding] = ChromEx.Embeddings.generate(["cats"])

      assert {:ok, results} = ChromEx.Collection.query(collection,
        [query_embedding],
        n_results: 2
      )

      assert is_map(results)
      assert length(hd(results["ids"])) <= 2
    end
  end

  describe "query/3 with metadata filters" do
    test "filters with single condition", %{collection: collection} do
      assert {:ok, results} = ChromEx.Collection.query(collection,
        query_texts: ["animals"],
        where: %{"year" => 2024},
        n_results: 10
      )

      metadatas = hd(results["metadatas"])
      assert Enum.all?(metadatas, fn m -> m["year"] == 2024 end)
      assert length(metadatas) == 2
    end

    test "filters with $and operator", %{collection: collection} do
      assert {:ok, results} = ChromEx.Collection.query(collection,
        query_texts: ["animals"],
        where: %{"$and" => [%{"year" => 2024}, %{"animal" => "cat"}]},
        n_results: 10
      )

      metadatas = hd(results["metadatas"])
      assert Enum.all?(metadatas, fn m ->
        m["year"] == 2024 and m["animal"] == "cat"
      end)
      assert length(metadatas) == 1
    end

    test "filters with $or operator", %{collection: collection} do
      assert {:ok, results} = ChromEx.Collection.query(collection,
        query_texts: ["animals"],
        where: %{"$or" => [%{"animal" => "cat"}, %{"animal" => "dog"}]},
        n_results: 10
      )

      metadatas = hd(results["metadatas"])
      assert length(metadatas) == 2
    end

    test "filters with $gte operator", %{collection: collection} do
      assert {:ok, results} = ChromEx.Collection.query(collection,
        query_texts: ["animals"],
        where: %{"year" => %{"$gte" => 2024}},
        n_results: 10
      )

      metadatas = hd(results["metadatas"])
      assert Enum.all?(metadatas, fn m -> m["year"] >= 2024 end)
    end

    test "filters with $in operator", %{collection: collection} do
      assert {:ok, results} = ChromEx.Collection.query(collection,
        query_texts: ["animals"],
        where: %{"animal" => %{"$in" => ["cat", "bird"]}},
        n_results: 10
      )

      metadatas = hd(results["metadatas"])
      assert length(metadatas) == 2
      assert Enum.all?(metadatas, fn m -> m["animal"] in ["cat", "bird"] end)
    end
  end

  describe "query/3 with n_results" do
    test "respects n_results parameter", %{collection: collection} do
      assert {:ok, results} = ChromEx.Collection.query(collection,
        query_texts: ["animals"],
        n_results: 1
      )

      assert length(hd(results["ids"])) == 1
    end

    test "returns all results when n_results exceeds document count", %{collection: collection} do
      assert {:ok, results} = ChromEx.Collection.query(collection,
        query_texts: ["animals"],
        n_results: 100
      )

      assert length(hd(results["ids"])) == 3
    end
  end
end
