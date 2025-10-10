# URGENT: How to Apply the Fix in Your Phoenix App

## The Problem
The ex_sieve source code has been updated with the validation fix, but your Phoenix application is still using the old compiled BEAM files that don't have the fix.

## Solution: Update Your Phoenix App

### Step 1: Update your Phoenix app's mix.exs

Go to your Phoenix app directory and edit `mix.exs`:

```elixir
defp deps do
  [
    # Change this line to use the path dependency
    {:ex_sieve, path: "/Users/gabor/Developent/phoenix/ex_sieve"},
    # ... other dependencies
  ]
end
```

### Step 2: Force Recompilation

In your Phoenix app directory, run these commands:

```bash
# Remove old compiled files
rm -rf _build/dev/lib/ex_sieve
rm -rf _build/test/lib/ex_sieve
rm -rf deps/ex_sieve

# Get the updated dependency
mix deps.get

# Force recompile ex_sieve
mix deps.compile ex_sieve --force

# Recompile your app
mix compile --force
```

### Step 3: Restart Your Server

```bash
# Stop your Phoenix server (Ctrl+C twice)
# Then start it again
mix phx.server
```

### Step 4: Verify the Fix is Working

Test with an invalid enum value in your browser or IEx:

```elixir
# Start IEx
iex -S mix

# Test with invalid enum
YourApp.Repo.filter(YourSchema, %{"billing_mode_eq" => "invoicing_one_time2"})

# Should return:
{:error, {:invalid_value, {"billing_mode_eq", "invoicing_one_time2"}}}

# Instead of crashing with Ecto.Query.CastError
```

## Alternative: If path dependency doesn't work

If you can't use a path dependency, copy the fixed file directly:

```bash
# From your Phoenix app directory
cp /Users/gabor/Developent/phoenix/ex_sieve/lib/ex_sieve/builder/where.ex deps/ex_sieve/lib/ex_sieve/builder/where.ex

# Force recompile
mix deps.compile ex_sieve --force
mix compile --force

# Restart server
```

## How to Check if the Fix is Loaded

```elixir
# In IEx
iex> {:module, mod} = Code.ensure_loaded(ExSieve.Builder.Where)
iex> mod.module_info(:exports) |> Enum.member?({:cast_values_by_type, 3})
true  # Should be true if fix is loaded
```

## Still Not Working?

If you're still seeing the error after all these steps:

1. **Check which ex_sieve is being used:**
   ```bash
   mix deps | grep ex_sieve
   ```

2. **Verify the file was updated:**
   ```bash
   grep -n "cast_values_by_type" deps/ex_sieve/lib/ex_sieve/builder/where.ex
   # Should show line numbers if the fix is present
   ```

3. **Nuclear option - full clean:**
   ```bash
   mix deps.clean ex_sieve
   rm -rf _build
   mix deps.get
   mix compile
   ```

4. **Make sure you're testing in the right environment:**
   - If testing via browser: Make sure the server restarted after recompilation
   - If testing via IEx: Start a NEW IEx session after recompilation

## Why This Happens

Erlang/Elixir apps cache compiled `.beam` files in the `_build` directory. Even though you modified the source code in ex_sieve, your Phoenix app is still using the old compiled version until you force it to recompile the dependency.

