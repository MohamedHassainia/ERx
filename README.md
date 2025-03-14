# ERx - Reactive Extensions for Erlang

[![Erlang CI](https://github.com/MohamedHassainia/erx/actions/workflows/erlang.yml/badge.svg)](https://github.com/MohamedHassainia/erx/actions/workflows/erlang.yml)

A feature-rich implementation of Reactive Extensions (Rx) patterns in Erlang, providing a declarative way to work with asynchronous data streams. ERx helps you compose and transform complex data flows while handling synchronous and asynchronous operations seamlessly.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [Examples](#examples)
- [API Reference](#api-reference)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Observable Streams**: Create observables from lists, single values, or custom data sources
- **Rich Operators**: Map, filter, reduce, combine, and transform streams with powerful operators
- **Composition**: Chain operations together for complex data processing pipelines
- **Async Support**: Mix sync and async processing with transparent integration
- **Advanced Stream Patterns**:
  - Zip/combine multiple streams
  - Merge streams into a single sequence
  - Distinct and distinct-until-changed filtering
  - Concatenation and flattening of nested observables
- **Comprehensive Testing**: Property-based testing with PropEr

## Installation

Add ERx as a rebar3 dependency:

```erlang
{deps, [
    {erx, {git, "https://github.com/MohamedHassainia/erx.git", {tag, "0.1.0"}}}
]}.
```

Or build from source:

```bash
git clone https://github.com/MohamedHassainia/erx.git
cd erx
rebar3 compile
```

## Quick Start

```erlang
% Create an observable that emits numbers 1-5
Observable = observable:from_list([1,2,3,4,5]),

% Apply transformations: keep even numbers, square them
TransformedObs = observable:pipe(Observable, [
    operator:filter(fun(X) -> X rem 2 =:= 0 end),
    operator:map(fun(X) -> X * X end)
]),

% Subscribe to receive values
Subscriber = subscriber:create(
    fun(Value) -> io:format("Received: ~p~n", [Value]) end,
    fun(Error) -> io:format("Error: ~p~n", [Error]) end,
    fun() -> io:format("Completed!~n") end
),

observable:subscribe(TransformedObs, Subscriber).
% Output:
% Received: 4
% Received: 16
% Completed!
```

## Core Concepts

- **Observable**: A stream of data that can emit values, errors, or completion signals
- **Operator**: Functions that transform, filter, or manipulate observables
- **Subscriber**: Consumers that react to values emitted by observables
- **Pipe**: Chain multiple operators together for composable data processing

## Examples

### Asynchronous Processing

```erlang
% Create an observable that processes items asynchronously
AsyncObs = observable:pipe(
    observable:from_list([1,2,3,4,5]), 
    [
        operator:async(),
        operator:map(fun(X) -> 
            timer:sleep(100),  % Simulate work
            X * 10
        end)
    ]
),

observable:subscribe(AsyncObs, subscriber:create(
    fun(Value) -> io:format("Got async value: ~p~n", [Value]) end
)).
```

### Combining Streams

```erlang
% Combining multiple sources with zip
Names = observable:from_list(["Alice", "Bob", "Charlie"]),
Ages = observable:from_list([25, 30, 35]),

% Zip combines corresponding elements from each observable
ZippedObs = observable:zip([Names, Ages]),

observable:subscribe(ZippedObs, subscriber:create(
    fun([Name, Age]) -> 
        io:format("~s is ~p years old~n", [Name, Age]) 
    end
)).
% Output:
% Alice is 25 years old
% Bob is 30 years old
% Charlie is 35 years old
```

### Error Handling

```erlang
% Handle errors in streams
DivideByZero = observable:pipe(
    observable:from_list([2, 1, 0, 3]),
    [
        operator:map(fun(X) -> 
            try 10 / X of
                Result -> Result
            catch
                error:badarith -> throw({error, division_by_zero})
            end
        end)
    ]
),

observable:subscribe(DivideByZero, subscriber:create(
    fun(Value) -> io:format("Result: ~p~n", [Value]) end,
    fun(Error) -> io:format("Error: ~p~n", [Error]) end
)).
```

## API Reference

### Core Modules

- **observable**: Create and operate on observable streams
- **operator**: Transform and process observables
- **subscriber**: Consume values emitted by observables

### Key Functions

#### Observable Creation
- `observable:from_list/1`: Create from list
- `observable:from_value/1`: Create from single value
- `observable:value/1`: Create from single value with immediate completion
- `observable:create/1`: Create from custom producer function

#### Combination
- `observable:zip/1`: Combine corresponding elements from multiple observables
- `observable:merge/1`: Flatten multiple observables into one

#### Transformation
- `observable:pipe/2`: Apply multiple operators
- `observable:bind/2`: Apply a single operator

#### Subscription
- `observable:subscribe/2`: Consume values from an observable

## Testing

ERx uses PropEr for property-based testing:

```bash
rebar3 proper
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - See the LICENSE file for details.
