defmodule ExDatalog do
  defstruct rules: [], facts: %{}

  alias ExDatalog.{Fact, Rule}
  alias __MODULE__

  def new, do: %__MODULE__{}

  def add_rule(%ExDatalog{rules: rules} = exDatalog, %Rule{} = rule) do
    {:ok, %ExDatalog{exDatalog | rules: [rule | rules]}}
  end

  def add_rule(%ExDatalog{rules: rules} = exDatalog, rule_module) when is_atom(rule_module) do
    new_rules =
      rule_module.__info__(:functions)
      |> Enum.filter(fn {_name, arity} -> arity == 2 or arity == 1 end)
      |> Enum.map(fn {name, arity} ->
        %Rule{name: to_string(name), module: rule_module, function: name, arity: arity}
      end)

    {:ok, %ExDatalog{exDatalog | rules: rules ++ new_rules}}
  end

  def add_rule(_, _), do: {:error, :invalid_rule}

  def add_fact(%ExDatalog{facts: facts} = exDatalog, %Fact{} = fact) do
    fact_key = fact_key(fact)
    updated_facts = Map.put(facts, fact_key, fact)
    {:ok, %ExDatalog{exDatalog | facts: updated_facts}}
  end

  def add_fact(_, _), do: {:error, :invalid_fact}

  def evaluate_query(%ExDatalog{rules: rules, facts: facts}, %{rule: rule} = query) do
    matching_rules = get_matching_rules(rules, rule)

    initial_facts = MapSet.new(Map.values(facts))

    all_facts = apply_rules(initial_facts, matching_rules)

    derived_facts = MapSet.difference(all_facts, initial_facts)

    {:ok, MapSet.to_list(apply_where_clause(derived_facts, query[:where]))}
  end

  def evaluate_query(_, _), do: {:error, :invalid_ExDatalog}

  defp apply_where_clause(facts, nil), do: facts

  defp apply_where_clause(facts, where_clause) do
    MapSet.filter(facts, fn fact ->
      Enum.all?(where_clause, fn {key, value} -> Map.get(fact, key) == value end)
    end)
  end

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

  defp apply_rule(%Rule{function: rule_fn}, facts) when is_function(rule_fn, 1) do
    try_apply_rule(rule_fn, facts)
  end

  defp apply_rule(%Rule{module: rule_module, function: function, arity: 1}, facts) do
    rule_fn = fn fact -> apply(rule_module, function, [fact]) end
    try_apply_rule(rule_fn, facts)
  end

  defp apply_rule(%Rule{function: rule_fn}, facts) when is_function(rule_fn, 2) do
    MapSet.new(
      for fact1 <- facts,
          fact2 <- facts,
          fact1 != fact2,
          new_fact <- try_apply_rule(rule_fn, fact1, fact2),
          do: new_fact
    )
  end

  defp apply_rule(%Rule{module: rule_module, function: function, arity: 2}, facts) do
    MapSet.new(
      for fact1 <- facts,
          fact2 <- facts,
          fact1 != fact2,
          new_fact <-
            try_apply_rule(
              fn a, b -> apply(rule_module, function, [a, b]) end,
              fact1,
              fact2
            ),
          do: new_fact
    )
  end

  defp apply_rule(_rule_fn, _facts), do: MapSet.new()

  defp try_apply_rule(rule_fn, facts) do
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
