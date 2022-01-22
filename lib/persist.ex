defmodule Persist do
  @moduledoc """
  A simple KV for doma.
  """

  import DynHacks

  @generations 3

  @doc """
  Saves state into file system and returns the state it saved or crashes.

  NB! No functions allowed.
  """
  @spec save_state(any, atom, atom | nil) :: any
  def save_state(state, module, host \\ nil) do
    {_, new_tip_path, vs} = get_values_and_new_tip(module, host)
    :ok = File.touch(new_tip_path)
    :ok = File.write(new_tip_path, :erlang.term_to_binary(state))

    Task.start(fn ->
      discard_obsolete_snapshots(vs, module, host)
    end)

    state
  end

  defp discard_obsolete_snapshots(vs, module, host) do
    if length(vs) > @generations do
      vs
      |> Enum.take(length(vs) - @generations)
      |> Enum.map(&File.rm(snapshot_path(module, host, &1)))
    end
  end

  @spec load_state(atom, atom | nil) :: any
  def load_state(module, host \\ nil) do
    {_, _, vs} = get_values_and_new_tip(module, host)

    load_latest_state(
      vs
      |> Enum.reverse()
      |> Enum.map(fn x -> [key_path(module, host), x] |> Path.join() end)
    )
  end

  defp load_latest_state([]) do
    nil
  end

  defp load_latest_state([h | t]) do
    case File.read(h) do
      {:ok, fc} ->
        :erlang.binary_to_term(fc)

      _ ->
        File.rm(h)
        load_latest_state(t)
    end
  end

  defp mk_key(module, host) do
    r_m(
      key_path(module, host),
      &File.mkdir_p/1
    )
  end

  defp get_values_and_new_tip(module, host) do
    key = mk_key(module, host)

    vs =
      Enum.sort(
        File.ls(key) |> elem(1),
        &(String.to_integer(&1) <= String.to_integer(&2))
      )

    {tip, vs} =
      case vs do
        [] ->
          {"1", vs}

        [h | []] ->
          {bump_tip(h), vs}

        [_ | t] ->
          {t |> Enum.reverse() |> hd() |> bump_tip(), vs}
      end

    {tip, Path.join([key, tip]), vs}
  end

  defp bump_tip(tip_n) do
    ((tip_n |> String.to_integer()) + 1) |> Integer.to_string()
  end

  defp snapshot_path(module, host, snapshot) do
    Path.join([key_path(module, host), snapshot])
  end

  defp key_path(module, host), do: [db_path(host), module |> Atom.to_string()] |> Path.join()

  @spec get_key_path(atom, atom | nil) :: Uptight.Text.t()
  def get_key_path(module, host \\ nil),
    do: key_path(module, host) |> Uptight.Text.new!()

  @spec get_db_path(atom | nil) :: Uptight.Text.t()
  def get_db_path(host \\ nil), do: db_path(host) |> Uptight.Text.new!()

  @spec db_path(atom | nil) :: Path.t()
  defp db_path(host) do
    n = (host || :erlang.node()) |> Atom.to_string()
    Path.join(["db", n])
  end
end
