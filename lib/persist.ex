defmodule Persist do
  @moduledoc """
  A simple KV for doma.
  """

  import DynHacks
  alias Uptight.Text

  @generations 3

  @doc """
  Saves state into file system and returns the state it saved or crashes.

  NB! No functions allowed.

  Or are they...

  iex(1)> (:erlang.term_to_binary(fn -> :ok end) |> :erlang.binary_to_term()).()
  :ok
  iex(2)> x = :enclosed
  :enclosed
  iex(3)> :io.format('~p~n', [:erlang.term_to_binary(fn -> x end)])
  <<131,112,0,0,0,157,0,76,80,224,147,120,219,253,166,238,44,96,86,8,53,142,187,
    0,0,0,45,0,0,0,1,100,0,8,101,114,108,95,101,118,97,108,97,45,98,2,98,135,4,
    88,100,0,13,110,111,110,111,100,101,64,110,111,104,111,115,116,0,0,0,106,0,0,
    0,0,0,0,0,0,104,4,116,0,0,0,1,100,0,3,95,64,48,100,0,8,101,110,99,108,111,
    115,101,100,100,0,4,110,111,110,101,100,0,4,110,111,110,101,108,0,0,0,1,104,
    5,100,0,6,99,108,97,117,115,101,97,9,106,106,108,0,0,0,1,104,3,100,0,3,118,
    97,114,97,9,100,0,3,95,64,48,106,106>>
  :ok


  In another shell:

  iex(1)> x = <<131,112,0,0,0,157,0,76,80,224,147,120,219,253,166,238,44,96,86,8,53,142,187,
  ...(1)>   0,0,0,45,0,0,0,1,100,0,8,101,114,108,95,101,118,97,108,97,45,98,2,98,135,4,
  ...(1)>   88,100,0,13,110,111,110,111,100,101,64,110,111,104,111,115,116,0,0,0,106,0,0,
  ...(1)>   0,0,0,0,0,0,104,4,116,0,0,0,1,100,0,3,95,64,48,100,0,8,101,110,99,108,111,
  ...(1)>   115,101,100,100,0,4,110,111,110,101,100,0,4,110,111,110,101,108,0,0,0,1,104,
  ...(1)>   5,100,0,6,99,108,97,117,115,101,97,9,106,106,108,0,0,0,1,104,3,100,0,3,118,
  ...(1)>   97,114,97,9,100,0,3,95,64,48,106,106>>
  iex(2)> :erlang.binary_to_term(x).()
  :enclosed

  Rather epic. Thank you, Joe!
  """
  @spec save_state(
          any(),
          atom() | {atom(), Uptight.Text.t() | atom() | pos_integer()},
          atom() | nil
        ) :: any()
  def save_state(
        state,
        module,
        host \\ nil
      ) do
    {_, new_tip_path, vs} = get_values_and_new_tip(module, host)
    :ok = File.touch(new_tip_path)
    :ok = File.write(new_tip_path, :erlang.term_to_binary(state))

    Task.start(fn ->
      discard_obsolete_snapshots(vs, module, host)
    end)

    state
  end

  defp discard_obsolete_snapshots(vs, module, host) do
    generations = Application.get_env(:persist, :generations) || @generations

    if length(vs) > generations do
      vs
      |> Enum.take(length(vs) - generations)
      |> Enum.map(&File.rm(snapshot_path(module, host, &1)))
    end
  end

  @spec load_state(
          atom() | {atom(), Uptight.Text.t() | atom() | pos_integer()},
          atom() | nil
        ) ::
          any()
  def load_state(
        module,
        host \\ nil
      ) do
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

  defp key_path(module, host) when is_atom(module) do
    [db_path(host), module |> Atom.to_string() |> pathsafe_str()] |> Path.join()
  end

  defp key_path({module, %Uptight.Text{text: bucket_name}}, host) do
    bucket_path(module, bucket_name, host)
  end

  defp key_path({module, bucket_id}, host) when is_atom(bucket_id) or is_number(bucket_id) do
    bucket_path(module, "#{bucket_id}", host)
  end

  defp bucket_path(module, bucket, host) do
    [db_path(host), module |> Atom.to_string() |> pathsafe_str(), bucket |> pathsafe_str()]
    |> Path.join()
  end

  def pathsafe(%Text{text: x}) do
    pathsafe_str(x) |> Text.new!()
  end

  def pathsafe_str(x_str) do
    for <<x <- x_str>>, String.match?(<<x>>, pathsafe_regex()), into: "" do
      <<x>>
    end
  end

  def pathsafe_regex() do
    ~r/^[[:lower:]]|[[:upper:]]|[[:digit:]]|-|_|@|\.$/
  end

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
