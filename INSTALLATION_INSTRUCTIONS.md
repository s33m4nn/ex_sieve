# Installation Instructions for the Fix

## The Problem
Both date/datetime and Ecto.Enum validation fixes have been implemented in the ex_sieve source code, but you need to ensure your application is using the updated version.

## What Was Fixed
1. **Date/DateTime Validation** - Invalid dates like `"2025a-09-01"` now return proper errors
2. **Ecto.Enum Validation** - Invalid enum values like `"invoicing_one_time2"` now return proper errors

## To Apply the Fix

### If you're developing ex_sieve itself:
```bash
# Clean and recompile
mix deps.clean ex_sieve --build
mix compile --force

# Run tests to verify
mix test test/ex_sieve/builder/where_test.exs
```

### If ex_sieve is a dependency in your Phoenix app:
You have two options:

**Option A: Use a Git dependency (temporary fix)**
In your Phoenix app's `mix.exs`:
```elixir
defp deps do
  [
    # ... other deps
    {:ex_sieve, git: "https://github.com/your-fork/ex_sieve", branch: "fix-validation"},
    # ... other deps
  ]
end
```

**Option B: Use a path dependency (local development)**
In your Phoenix app's `mix.exs`:
```elixir
defp deps do
  [
    # ... other deps
    {:ex_sieve, path: "/Users/gabor/Developent/phoenix/ex_sieve"},
    # ... other deps
  ]
end
```

Then in your Phoenix app:
```bash
mix deps.get
mix deps.compile ex_sieve --force
mix compile --force
```

## Testing the Fix

Once installed, invalid values should return errors instead of crashing:

```elixir
# In your Phoenix app's IEx console
iex> YourApp.Repo.filter(YourSchema, %{"date_field_gteq" => "2025a-09-01"})
{:error, {:invalid_value, {"date_field_gteq", "2025a-09-01"}}}

iex> YourApp.Repo.filter(YourSchema, %{"enum_field_eq" => "invalid_value"})
{:error, {:invalid_value, {"enum_field_eq", "invalid_value"}}}
```

## Verifying the Fix is Active

To confirm the fix is being used:
```bash
# In your Phoenix app
iex -S mix

iex> :code.which(ExSieve.Builder.Where)
# Should show path to the compiled module

iex> File.read!(:code.which(ExSieve.Builder.Where) |> to_string())
|> String.contains?("cast_values_by_type")
true  # Should return true if the fix is loaded
```

## If You're Still Getting Errors

1. **Ensure recompilation**: Run `mix clean && mix compile` in your Phoenix app
2. **Check the dependency**: Verify mix.exs is pointing to the correct version
3. **Restart your server**: Stop and restart your Phoenix server
4. **Check for cached beam files**: Remove `_build` directory and recompile

## Next Steps

Once the fix is working, you can:
1. Create a pull request to the ex_sieve repository
2. Wait for it to be merged and released
3. Update your app to use the official released version

