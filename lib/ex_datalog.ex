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
    fact_key = fact_key(fact)
    updated_facts = Map.put(facts, fact_key, fact)
    {:ok, %ExDatalog{exDatalog | facts: updated_facts}}
  end

  def add_fact(_, _), do: {:error, :invalid_fact}

  def evaluate_query(%ExDatalog{rules: rules, facts: facts}, query_params) do
    matching_rules = get_matching_rules(rules, query_params[:rule])
    initial_facts = MapSet.new(Map.values(facts))
    all_facts = apply_rules(initial_facts, matching_rules)
    derived_facts = MapSet.difference(all_facts, initial_facts)

    result =
      case query_params[:rule] do
        nil -> MapSet.to_list(all_facts)
        _rule -> MapSet.to_list(derived_facts)
      end

    {:ok, result}
  end

  def evaluate_query(_, _), do: {:error, :invalid_ExDatalog}

  defp get_matching_rules(rules, nil), do: rules

  defp get_matching_rules(rules, relation) do
    Enum.filter(rules, fn rule -> rule.name == relation end)
  end

  defp apply_rules(facts, rules) do
    Stream.iterate(facts, &apply_rules_once(&1, rules))
    |> Stream.chunk_every(2, 1)
    |> Enum.find_value(fn [prev, curr] -> if MapSet.equal?(prev, curr), do: curr end)
  end

  defp apply_rules_once(facts, rules) do
    Enum.reduce(rules, facts, fn rule, acc_facts ->
      new_facts = apply_rule(rule, acc_facts)
      MapSet.union(acc_facts, new_facts)
    end)
  end

  defp apply_rule(%Rule{rule: rule_fn}, facts) do
    case :erlang.fun_info(rule_fn)[:arity] do
      1 ->
        MapSet.new(
          Enum.flat_map(facts, fn fact ->
            try do
              case rule_fn.(fact) do
                nil -> []
                new_fact -> [new_fact]
              end
            rescue
              FunctionClauseError -> []
            end
          end)
        )

      2 ->
        MapSet.new(
          for fact1 <- facts,
              fact2 <- facts,
              fact1 != fact2,
              new_fact <- try_apply_rule(rule_fn, fact1, fact2),
              do: new_fact
        )

      _ ->
        MapSet.new()
    end
  end

  defp try_apply_rule(rule_fn, fact1, fact2) do
    try do
      case rule_fn.(fact1, fact2) do
        nil -> []
        new_fact -> [new_fact]
      end
    rescue
      FunctionClauseError -> []
    end
  end

  defp fact_key(fact) do
    {fact.object_id, fact.subject_id, fact.object_relation}
  end
end
