defmodule ExDatalog do
  defstruct rules: [], facts: %{}

  alias ExDatalog.{Fact, Rule}
  alias __MODULE__

  def new, do: %__MODULE__{}

  def add_rule(%ExDatalog{rules: rules} = exDatalog, %Rule{} = rule) do
    {:ok, %ExDatalog{exDatalog | rules: [rule | rules]}}
  end

  def add_rule(_, _), do: {:error, :invalid_rule}

  def add_fact(%ExDatalog{facts: facts} = exDatalog, %Fact{} = fact) do
    updated_facts = Map.put(facts, fact_key(fact), fact)
    {:ok, %ExDatalog{exDatalog | facts: updated_facts}}
  end

  def add_fact(_, _), do: {:error, :invalid_fact}

  def evaluate_query(%ExDatalog{rules: rules, facts: facts}, query_params) do
    matching_rules = get_matching_rules(rules, query_params[:rule])
    {:ok, apply_rules(facts, matching_rules, query_params[:rule])}
  end

  def evaluate_query(_, _), do: {:error, :invalid_ExDatalog}

  defp get_matching_rules(rules, nil), do: rules

  defp get_matching_rules(rules, relation) do
    Enum.filter(rules, fn rule -> rule.name == relation end)
  end

  defp apply_rules(facts, rules, query_rule) do
    iter_apply_rules(facts, rules, query_rule, %{}, %{})
  end

  defp iter_apply_rules(all_facts, rules, query_rule, derived, seen, previous_derived \\ %{}) do
    fact_chunks =
      Map.keys(all_facts) |> Enum.chunk_every(500) |> Enum.reject(&Map.has_key?(seen, &1))

    # Limit the number of concurrent tasks
    max_concurrency = 10

    results =
      fact_chunks
      |> Enum.chunk_every(max_concurrency)
      |> Enum.flat_map(fn chunk_group ->
        Enum.map(chunk_group, fn chunk ->
          Task.async(fn ->
            process_fact_chunk(chunk, all_facts, rules, derived)
          end)
        end)
        |> Task.await_many()
      end)

    {new_facts, new_derived} =
      Enum.reduce(results, {%{}, derived}, fn {fact_new_facts, fact_derived}, {acc, d_acc} ->
        {Map.merge(acc, fact_new_facts), Map.merge(d_acc, fact_derived)}
      end)

    updated_seen = update_seen(new_facts, seen)

    # Check if no new facts are derived
    if new_derived == previous_derived do
      if query_rule do
        Map.values(new_derived)
      else
        Map.values(all_facts)
      end
    else
      new_total_facts = Map.merge(all_facts, new_derived)
      iter_apply_rules(new_total_facts, rules, query_rule, %{}, updated_seen, new_derived)
    end
  end

  defp process_fact_chunk(chunk, all_facts, rules, derived) do
    Enum.reduce(chunk, {Map.new(), derived}, fn fact_key, {acc, d_acc} ->
      fact = Map.fetch!(all_facts, fact_key)

      Enum.reduce(all_facts, {acc, d_acc}, fn {_, existing_fact}, {acc_inner, d_acc_inner} ->
        process_fact(fact, existing_fact, rules, acc_inner, d_acc_inner)
      end)
    end)
  end

  defp update_seen(new_facts, seen) do
    Map.merge(seen, new_facts, fn _, _, new -> new end)
  end

  defp fact_key(fact) do
    {fact.object_id, fact.subject_id, fact.object_relation}
  end

  defp process_fact(fact1, fact2, rules, acc, derived) do
    Enum.reduce(rules, {acc, derived}, fn rule, {acc_inner, derived_inner} ->
      apply_rule(fact1, fact2, rule, acc_inner, derived_inner)
    end)
  end

  defp apply_rule(fact1, fact2, %Rule{rule: rule_fn}, acc, derived) do
    case apply_rule_fn(rule_fn, fact1, fact2) do
      nil ->
        {acc, derived}

      new_fact ->
        fact_key = fact_key(new_fact)

        if Map.has_key?(acc, fact_key) do
          {acc, derived}
        else
          {Map.put(acc, fact_key, new_fact), Map.put(derived, fact_key, new_fact)}
        end
    end
  rescue
    FunctionClauseError -> {acc, derived}
  end

  defp apply_rule_fn(rule_fn, fact1, _fact2) when is_function(rule_fn, 1),
    do: apply(rule_fn, [fact1])

  defp apply_rule_fn(rule_fn, fact1, fact2) when is_function(rule_fn, 2),
    do: apply(rule_fn, [fact1, fact2])

  defp apply_rule_fn(_, _, _), do: nil
end
