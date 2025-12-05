defmodule ChromExTest do
  use ExUnit.Case
  doctest ChromEx

  test "greets the world" do
    assert ChromEx.hello() == :world
  end
end
