# ERx - Reactive Extensions for Erlang

An implementation of Reactive Extensions (Rx) patterns in Erlang, providing a composable way to work with asynchronous data streams.

## Features

- Observable streams with map, filter, reduce operations
- Zipping and merging multiple streams
- Error handling and completion signals
- Property-based testing using PropEr

## Examples

```erlang
% Create an observable from a list and apply transformations
Observable = observable:pipe(
    observable:from_list([1,2,3,4,5]),
    [
        operator:filter(fun(X) -> X > 2 end),
        operator:map(fun(X) -> X * X end)
    ]
).

% Subscribe to receive values
Subscriber = subscriber:create(
    fun(Value) -> io:format("Received: ~p~n", [Value]) end
).
observable:subscribe(Observable, [Subscriber]).
```

## Installation

Add as a rebar3 dependency:

```erlang
{deps, [
    {ereactive, {git, "https://github.com/MohamedHassainia/ereactive.git", {tag, "0.1.0"}}}
]}.
```

## Testing

The project uses PropEr for property-based testing:

```bash
rebar3 proper
```

## License

MIT License - See LICENSE file for details
