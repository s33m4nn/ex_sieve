# Date and Enum Validation Fix

## Problem
When users provided invalid date/datetime/time or enum values, the ExSieve library would crash with an `Ecto.Query.CastError` at query execution time.

### Date/DateTime Example
```
** (Ecto.Query.CastError) lib/ex_sieve/builder/where.ex:47: value `"2025a-09-01"` in `where` cannot be cast to type :date in query:

from d0 in Rts.Shipping.DeliveryNote,
  where: d0.day >= ^"2025a-09-01" and d0.day <= ^"2025-09-30" and d0.state == ^"fulfilled",
  select: count("*")
```

### Enum Example
```
** (Ecto.Query.CastError) lib/ex_sieve/builder/where.ex:143: value `"invoicing_one_time2"` in `where` cannot be cast to type #Ecto.Enum<values: [:invoicing_one_time, :invoicing_at_15, :invoicing_at_30]> in query:

from d0 in Rts.Shipping.Delivery,
  where: d0.billing_mode == ^"invoicing_one_time2"
```

## Solution
The fix adds early validation and casting of date/datetime/time and enum values before they are used in Ecto queries. Invalid values now return a proper error tuple instead of causing a crash:

```elixir
{:error, {:invalid_value, {field_name, invalid_value}}}
```

## Changes Made

### 1. Modified `lib/ex_sieve/builder/where.ex`
- Added `cast_values/2` function to validate and cast values based on attribute type
- Added `cast_values_by_type/3` with multiple clauses:
  - Handle Ecto.Enum types by validating against allowed enum values
  - Handle date/datetime/time types with proper ISO8601 parsing
  - Pass through other types unchanged
- Added `cast_value/2` functions for each temporal type (`:date`, `:time`, `:naive_datetime`, `:utc_datetime`, etc.)
- Added `normalize_datetime_result/1` helper to handle DateTime parsing results
- Updated `dynamic_predicate/4` to call `cast_values` before building the dynamic query

### 2. Updated Tests in `test/ex_sieve/builder/where_test.exs`
- Updated existing datetime test to expect casted NaiveDateTime values
- Added new test suite "invalid date/datetime values" with three test cases:
  - Test for invalid date value
  - Test for invalid datetime value  
  - Test for valid datetime value (to ensure valid values still work)
- Added new test suite "invalid enum values" with three test cases:
  - Test for invalid enum value
  - Test for valid enum value as string
  - Test for valid enum value as atom

### 3. Updated Test Schema `test/support/post.ex`
- Added `status` field with `Ecto.Enum` type for testing enum validation

## Behavior

### Before the Fix
```elixir
# Date validation - would crash with Ecto.Query.CastError
Repo.filter(Post, %{"inserted_at_gteq" => "2025a-09-01"})

# Enum validation - would crash with Ecto.Query.CastError
Repo.filter(Post, %{"status_eq" => "invalid_status"})
```

### After the Fix
```elixir
# Invalid dates now return a proper error
Repo.filter(Post, %{"inserted_at_gteq" => "2025a-09-01"})
# => {:error, {:invalid_value, {"inserted_at_gteq", "2025a-09-01"}}}

# Invalid enums now return a proper error
Repo.filter(Post, %{"status_eq" => "invalid_status"})
# => {:error, {:invalid_value, {"status_eq", "invalid_status"}}}

# Valid dates work as expected
Repo.filter(Post, %{"inserted_at_gteq" => "2025-09-01"})
# => #Ecto.Query<...>

# Valid enums work as expected
Repo.filter(Post, %{"status_eq" => "draft"})
# => #Ecto.Query<...>
```

## Supported Date/Time Types
The validation now handles:
- `:date` - ISO8601 date strings (e.g., "2025-09-01")
  - **Lenient parsing**: Also accepts dates without leading zeros (e.g., "2025-10-1", "2025-1-5")
  - Automatically normalizes to ISO8601 format before validation
- `:time` - ISO8601 time strings (e.g., "12:30:00")
- `:naive_datetime` - ISO8601 datetime strings (e.g., "2025-09-01T12:30:00")
- `:naive_datetime_usec` - ISO8601 datetime strings with microseconds
- `:utc_datetime` - ISO8601 datetime strings with timezone
- `:utc_datetime_usec` - ISO8601 datetime strings with microseconds and timezone

## Supported Enum Types
The validation handles:
- `Ecto.Enum` - Validates that provided values are in the allowed enum values
- Accepts both string and atom representations
- Converts strings to atoms when valid

## Examples of Valid and Invalid Values

### Valid Dates (with lenient parsing)
- `"2025-09-01"` - Standard ISO8601 ✓
- `"2025-10-1"` - Without leading zero on day ✓ (normalized to "2025-10-01")
- `"2025-1-5"` - Without leading zeros ✓ (normalized to "2025-01-05")
- `"2025-9-3"` - Single digit month and day ✓ (normalized to "2025-09-03")

### Invalid Dates (caught and return errors)
- `"2025a-09-01"` - Letter in date ✗
- `"2025-13-01"` - Invalid month ✗
- `"2025-09-32"` - Invalid day ✗
- `"not-a-date"` - Completely invalid format ✗
- `"2025-13-01T00:00:00"` - Invalid month in datetime ✗

### Invalid Enums (caught and return errors)
- `"invalid_status"` - Not in the allowed enum values ✗
- `"invoicing_one_time2"` - Typo in enum value ✗
- Any value not defined in the enum's `:values` option ✗

All invalid values now return `{:error, {:invalid_value, ...}}` instead of causing a crash.
