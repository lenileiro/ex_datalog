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

    if Enum.empty?(matching_rules) do
      {:ok, []}
    else
      all_facts = apply_rules(initial_facts, matching_rules)
      derived_facts = get_derived_facts(all_facts, initial_facts, matching_rules)
      {:ok, MapSet.to_list(apply_where_clause(derived_facts, Map.get(query, :where)))}
    end
  end

  def evaluate_query(_, _), do: {:error, :invalid_ExDatalog}

  defp get_matching_rules(rules, nil), do: rules
  defp get_matching_rules(rules, rule), do: Enum.filter(rules, &(&1.name == to_string(rule)))

  defp apply_rules(facts, rules) do
    new_facts = apply_rules_once(facts, rules)

    if MapSet.equal?(new_facts, facts) do
      new_facts
    else
      apply_rules(new_facts, rules)
    end
  end

  defp apply_rules_once(facts, rules) do
    Enum.reduce(rules, facts, fn rule, acc_facts ->
      new_facts = apply_rule(rule, acc_facts)
      MapSet.union(acc_facts, new_facts)
    end)
  end

  defp apply_rule(%Rule{function: rule_fn}, facts) when is_function(rule_fn, 1) do
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

  defp apply_rule(%Rule{function: rule_fn}, facts) when is_function(rule_fn, 2) do
    MapSet.new(
      for fact1 <- facts,
          fact2 <- facts,
          fact1 != fact2,
          new_fact <- try_apply_rule(rule_fn, fact1, fact2),
          do: new_fact
    )
  end

  defp apply_rule(%Rule{module: module, function: function, arity: 1}, facts) do
    rule_fn = fn fact -> apply(module, function, [fact]) end
    apply_rule(%Rule{function: rule_fn}, facts)
  end

  defp apply_rule(%Rule{module: module, function: function, arity: 2}, facts) do
    rule_fn = fn fact1, fact2 -> apply(module, function, [fact1, fact2]) end
    apply_rule(%Rule{function: rule_fn}, facts)
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

  defp get_derived_facts(all_facts, initial_facts, rules) do
    derived = MapSet.difference(all_facts, initial_facts)

    explicitly_derived =
      MapSet.filter(all_facts, fn fact ->
        Enum.any?(rules, &rule_derives_fact?(&1, fact, all_facts))
      end)

    MapSet.union(derived, explicitly_derived)
  end

  defp rule_derives_fact?(rule, fact, all_facts) do
    case rule do
      %Rule{function: f} when is_function(f, 1) ->
        try_apply_unary_rule(f, fact)

      %Rule{function: f} when is_function(f, 2) ->
        try_apply_binary_rule(f, fact, all_facts)

      %Rule{module: m, function: f, arity: 1} ->
        try_apply_unary_rule(&apply(m, f, [&1]), fact)

      %Rule{module: m, function: f, arity: 2} ->
        try_apply_binary_rule(&apply(m, f, [&1, &2]), fact, all_facts)
    end
  end

  defp try_apply_unary_rule(rule_fn, fact) do
    try do
      rule_fn.(fact) == fact
    rescue
      FunctionClauseError -> false
    end
  end

  defp try_apply_binary_rule(rule_fn, fact, all_facts) do
    Enum.any?(all_facts, fn other_fact ->
      try do
        rule_fn.(fact, other_fact) == fact or rule_fn.(other_fact, fact) == fact
      rescue
        FunctionClauseError -> false
      end
    end)
  end

  defp apply_where_clause(facts, nil), do: facts

  defp apply_where_clause(facts, where_clause) do
    MapSet.filter(facts, fn fact ->
      Enum.all?(where_clause, fn {key, value} -> Map.get(fact, key) == value end)
    end)
  end

  defp fact_key(fact), do: {fact.object_id, fact.subject_id, fact.object_relation}
end
