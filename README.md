## ExDatalog

ExDatalog is a library for defining and querying facts and rules in a Datalog-inspired logic programming system. It allows users to create complex logical rules and infer new facts based on these rules and the existing facts.

ExDatalog is a library for defining and querying facts and rules in a Datalog-inspired modelled as ReBAC (Relationship-Based Access Control).

### Installation

To use ExDatalog in your project, add it to your dependencies:

```elixir
def deps do
  [
    {:ex_datalog, "~> 0.1.0"}
  ]
end
```

### Usage

#### Defining Rules and Facts

Let's start by defining some rules. We will use a module-based approach to encapsulate our rules.

Rules in ExDatalog are defined using modules. Here’s an example of a rule that defines an ancestor relationship:

```elixir
defmodule AncestorRules do
  use ExDatalog

  ~PERM"""
  [
    {
      "name": "parent",
      "conditions": [
        ["$on", "$oid", "parent", "$sn", "$sid", null]
      ],
      "conclusions": [
        ["$on", "$oid", "parent", "$sn", "$sid", null]
      ]
    },
    {
      "name": "ancestor",
      "conditions": [
        ["$on1", "$grandparent", "parent", "$sn1", "$parent", null],
        ["$on2", "$parent", "parent", "$sn2", "$descendant", null]
      ],
      "conclusions": [
        ["user", "$grandparent", "ancestor", "user", "$descendant", null]
      ]
    }
  ]
  """
end
```

#### Adding Facts

Next, we add facts representing the family tree of individuals.

```elixir
datalog = ExDatalog.new()
{:ok, datalog} = ExDatalog.add_rule(datalog, AncestorRules)

{:ok, datalog} =
  ExDatalog.add_fact(datalog, %ExDatalog.Fact{
    object_id: "Alice",
    object_namespace: "user",
    subject_id: "Bob",
    subject_namespace: "user",
    object_relation: "parent"
  })

{:ok, datalog} =
  ExDatalog.add_fact(datalog, %ExDatalog.Fact{
    object_id: "Bob",
    object_namespace: "user",
    subject_id: "Charlie",
    subject_namespace: "user",
    object_relation: "parent"
  })
```

#### Querying Facts

To derive new facts based on the rules and facts, you can run queries. For example, to find all ancestors:

```elixir
{:ok, results} = ExDatalog.evaluate_query(datalog, %{rule: "ancestor"})
```

This should output:

```elixir
[
   %ExDatalog.Fact{
     object_namespace: "user",
     object_id: "Alice",
     object_relation: "ancestor",
     subject_namespace: "user",
     subject_id: "Charlie",
     subject_relation: nil
   }
 ]
```

#### Querying with Wildcards

You can use the wildcard \* to query all facts inferred by any rule:

```elixir
{:ok, results} = ExDatalog.evaluate_query(datalog, %{rule: "*"})
```

This will output all facts inferred by all rules, providing a complete picture of the relationships in the system.

This includes facts inferred by the parent and ancestor rules:

```elixir
[
   %ExDatalog.Fact{
     object_namespace: "user",
     object_id: "Alice",
     object_relation: "ancestor",
     subject_namespace: "user",
     subject_id: "Charlie",
     subject_relation: nil
   },
   %ExDatalog.Fact{
     object_namespace: "user",
     object_id: "Alice",
     object_relation: "parent",
     subject_namespace: "user",
     subject_id: "Bob",
     subject_relation: nil
   },
   %ExDatalog.Fact{
     object_namespace: "user",
     object_id: "Bob",
     object_relation: "parent",
     subject_namespace: "user",
     subject_id: "Charlie",
     subject_relation: nil
   }
 ]
```

#### Querying with Specific Conditions

You can also query with specific conditions using the where clause. For example, to find all where Alice matches the any rule:

```elixir
{:ok, results} = ExDatalog.evaluate_query(datalog, %{rule: "*", where: %{object_id: "Alice"}})
```

This should output:

```elixir
[
   %ExDatalog.Fact{
     object_namespace: "user",
     object_id: "Alice",
     object_relation: "ancestor",
     subject_namespace: "user",
     subject_id: "Charlie",
     subject_relation: nil
   },
   %ExDatalog.Fact{
     object_namespace: "user",
     object_id: "Alice",
     object_relation: "parent",
     subject_namespace: "user",
     subject_id: "Bob",
     subject_relation: nil
   }
 ]
```

### Inspiration

ExDatalog draws inspiration from several advanced systems and concepts in the field of access control and logical inference:

#### Google Zanzibar

Google Zanzibar is a consistent, highly available, and massively scalable global authorization system used by Google to manage permissions across its services. For more details, you can refer to the [Google Zanzibar whitepaper](https://research.google/pubs/pub48190/).

#### Permify

Permify is an open-source authorization service that provides a Zanzibar-like experience for developers. It simplifies complex permission management using a rule-based approach. For more insights, you can read about it [here](https://permify.co/post/google-zanzibar-in-a-nutshell/).

### Conclusion

ExDatalog provides a flexible and powerful way to define and query logical rules and facts. By using rules and facts, you can model complex relationships and make inferences in various domains, such as, authorization, organizational management, fraud detection, and more.
