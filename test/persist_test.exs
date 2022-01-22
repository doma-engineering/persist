defmodule PersistTest do
  @moduledoc """
  Tests for persistance layer
  """
  use ExUnit.Case, async: true
  alias Uptight.Text, as: T

  test "saves and loads the state" do
    target = {0, [1, {:a, %{"b" => :oo}}], %{nil => nil}}
    1 = Persist.save_state(1, __MODULE__)
    2 = Persist.save_state(2, __MODULE__)
    target = Persist.save_state(target, __MODULE__)
    loaded = Persist.load_state(__MODULE__)
    File.rm_rf(Persist.get_key_path(__MODULE__) |> T.un())
    assert loaded == target
  end
end
