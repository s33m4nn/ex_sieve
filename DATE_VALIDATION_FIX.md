# Date Validation Fix

## Problem
When users provided invalid date/datetime values (e.g., `"2025a-09-01"`, `"2025-13-01"`), the ExSieve library would crash with an `Ecto.Query.CastError` at query execution time:

```
** (Ecto.Query.CastError) lib/ex_sieve/builder/where.ex:47: value `"2025a-09-01"` in `where` cannot be cast to type :date in query:

from d0 in Rts.Shipping.DeliveryNote,
  where: d0.day >= ^"2025a-09-01" and d0.day <= ^"2025-09-30" and d0.state == ^"fulfilled",
  select: count("*")
```

## Solution
The fix adds early validation and casting of date/datetime/time values before they are used in Ecto queries. Invalid values now return a proper error tuple instead of causing a crash:

```elixir
{:error, {:invalid_value, {field_name, invalid_value}}}
```

## Changes Made

### 1. Modified `lib/ex_sieve/builder/where.ex`
- Added `cast_values/2` function to validate and cast values based on attribute type
- Added `cast_values_by_type/3` to handle date/datetime/time types specifically
- Added `cast_value/2` functions for each temporal type (`:date`, `:time`, `:naive_datetime`, `:utc_datetime`, etc.)
- Added `normalize_datetime_result/1` helper to handle DateTime parsing results
- Updated `dynamic_predicate/4` to call `cast_values` before building the dynamic query

### 2. Updated Tests in `test/ex_sieve/builder/where_test.exs`
- Updated existing datetime test to expect casted NaiveDateTime values
- Added new test suite "invalid date/datetime values" with three test cases:
  - Test for invalid date value
  - Test for invalid datetime value  
  - Test for valid datetime value (to ensure valid values still work)

## Behavior

### Before the Fix
```elixir
# This would crash with Ecto.Query.CastError
Repo.filter(Post, %{"inserted_at_gteq" => "2025a-09-01"})
```

### After the Fix
```elixir
# Invalid dates now return a proper error
Repo.filter(Post, %{"inserted_at_gteq" => "2025a-09-01"})
# => {:error, {:invalid_value, {"inserted_at_gteq", "2025a-09-01"}}}

# Valid dates work as expected
Repo.filter(Post, %{"inserted_at_gteq" => "2025-09-01"})
# => #Ecto.Query<...>
```

## Supported Date/Time Types
The validation now handles:
- `:date` - ISO8601 date strings (e.g., "2025-09-01")
- `:time` - ISO8601 time strings (e.g., "12:30:00")
- `:naive_datetime` - ISO8601 datetime strings (e.g., "2025-09-01T12:30:00")
- `:naive_datetime_usec` - ISO8601 datetime strings with microseconds
- `:utc_datetime` - ISO8601 datetime strings with timezone
- `:utc_datetime_usec` - ISO8601 datetime strings with microseconds and timezone

## Examples of Invalid Values Caught
- `"2025a-09-01"` - Letter in date
- `"2025-13-01"` - Invalid month
- `"2025-09-32"` - Invalid day
- `"not-a-date"` - Completely invalid format
- `"2025-13-01T00:00:00"` - Invalid month in datetime

All of these now return `{:error, {:invalid_value, ...}}` instead of causing a crash.

